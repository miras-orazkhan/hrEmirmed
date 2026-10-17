require "test_helper"

class CandidateApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "Клиника")
    @admin = staff("admin", [])
    @recruiter = staff("recruiter", %w[read.candidate read.all_candidates manage.candidate_application launch.recruitment_campaign manage.job_requisition])
    @other_recruiter = staff("other", @recruiter.role.permissions)
    @interviewer = staff("interviewer", %w[read.candidate conduct.interview])
    @supervisor = staff("supervisor", %w[read.candidate supervise.internship])
    @candidate = Candidate.create!(full_name: "Кандидат", responsible_recruiter: @recruiter, created_by: @recruiter)
    @reason = RejectionReason.create!(name: "Не соответствует требованиям")
    @requisition = create_requisition
  end

  test "start pins conditions and prevents simultaneous active applications" do
    start_application
    assert_response :created
    application = CandidateApplication.last
    pinned_version = application.job_requisition_version_id
    Recruitment::Planning.new(@admin).revise_requisition(@requisition.id, { "salary_amount" => "700000" })
    assert_equal pinned_version, application.reload.job_requisition_version_id
    assert_equal BigDecimal("500000"), application.job_requisition_version.salary_amount
    start_application
    assert_response :conflict
    assert_equal 1, CandidateApplication.count
  end

  test "only recruiter assigned to requisition starts applications" do
    start_application(user: @other_recruiter)
    assert_response :forbidden
    assert_equal 0, CandidateApplication.count
  end

  test "only assigned decision makers can advance and cannot mark candidate hired" do
    start_application
    application = CandidateApplication.last
    advance(application, @recruiter)
    assert_equal "test_review", application.reload.stage
    advance(application, @recruiter)
    assert_equal "interview", application.reload.stage
    advance(application, @recruiter)
    assert_response :forbidden
    advance(application, @interviewer)
    assert_response :success
    assert_equal "offer", application.reload.stage
    advance(application, @recruiter)
    assert_response :conflict
    finish(application, outcome: "hired")
    assert_response :conflict
    assert_equal "active", application.reload.status
    assert_equal 0, @requisition.reload.filled_positions_count
  end

  test "revising interviewer assignment does not transfer existing application" do
    start_application
    application = CandidateApplication.last
    replacement = staff("replacement", %w[read.candidate conduct.interview])
    Recruitment::Planning.new(@admin).revise_requisition(@requisition.id, { "interviewer_id" => replacement.id })
    2.times { advance(application, @recruiter) }
    advance(application, replacement)
    assert_response :not_found
    advance(application, @interviewer)
    assert_response :success
    assert_equal "offer", application.reload.stage
  end

  test "mandatory internship is decided by pinned supervisor" do
    @requisition = create_requisition(internship_required: true)
    start_application
    application = CandidateApplication.last
    2.times { advance(application, @recruiter) }
    advance(application, @interviewer)
    assert_equal "internship", application.reload.stage
    advance(application, @interviewer)
    assert_response :forbidden
    advance(application, @supervisor)
    assert_response :success
    assert_equal "offer", application.reload.stage
  end

  test "interviewer access begins on transfer and hides other candidate history" do
    start_application
    first = CandidateApplication.last
    get "/api/v1/candidate_applications/#{first.id}", headers: auth(@interviewer)
    assert_response :not_found
    finish(first, allow_next_application: true)
    start_application
    second = CandidateApplication.last
    2.times { advance(second, @recruiter) }
    get "/api/v1/candidate_applications", params: { candidate_id: @candidate.id }, headers: auth(@interviewer)
    assert_response :success
    assert_equal [ second.id ], response.parsed_body.pluck("id")
    get "/api/v1/candidate_applications/#{first.id}", headers: auth(@interviewer)
    assert_response :not_found
  end

  test "refusal requires active reason and explicit boolean followup decision" do
    start_application
    application = CandidateApplication.last
    finish(application, allow_next_application: nil)
    assert_response :conflict
    finish(application, allow_next_application: "false")
    assert_response :conflict
    @reason.update!(active: false)
    finish(application)
    assert_response :not_found
    @reason.update!(active: true)
    finish(application, allow_next_application: false)
    assert_response :success
    assert_equal false, application.reload.allow_next_application
    assert_equal "completed", application.status
    assert_equal "screening", application.stage
    start_application
    assert_response :conflict
  end

  test "withdrawal with permission allows next application and cannot be repeated" do
    start_application
    application = CandidateApplication.last
    finish(application, outcome: "withdrawn", allow_next_application: true)
    assert_response :success
    assert_nil application.reload.rejection_reason_id
    finish(application, outcome: "withdrawn", allow_next_application: true)
    assert_response :conflict
    start_application
    assert_response :created
    assert_equal 2, CandidateApplication.count
  end

  test "pause blocks starts decisions and advancement" do
    start_application
    application = CandidateApplication.last
    Recruitment::Planning.new(@recruiter).transition_requisition(@requisition.id, "pause")
    advance(application, @recruiter)
    assert_response :conflict
    finish(application)
    assert_response :conflict
    assert_equal "active", application.reload.status
    start_application
    assert_response :conflict
  end

  test "interview refusal and next option belong to assigned interviewer" do
    start_application
    application = CandidateApplication.last
    2.times { advance(application, @recruiter) }
    finish(application)
    assert_response :forbidden
    finish(application, user: @interviewer, allow_next_application: true)
    assert_response :success
    assert_equal @interviewer.id, application.reload.decided_by_id
    start_application
    assert_response :created
  end

  private

  def staff(login, permissions)
    role = Role.create!(name: login, permissions: permissions)
    User.create!(login: login, full_name: login, password: "long-test-password", role: role,
      branch: @branch, departments: [ @department ])
  end

  def auth(user)
    _, token = AuthSession.issue!(user)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_requisition(internship_required: false)
    planning = Recruitment::Planning.new(@admin)
    template = planning.create_template({ "title" => "Врач", "duties" => "Приём", "recruiter_id" => @recruiter.id,
      "internship_required" => internship_required, "internship_criteria" => internship_required ? [ "Навыки" ] : [] })
    planning.approve_template(template.id)
    requisition = planning.create_requisition({ "department_id" => @department.id, "vacancy_template_id" => template.id,
      "positions_count" => 2, "salary_amount" => "500000", "salary_currency" => "KZT", "work_schedule" => "5/2",
      "desired_start_on" => "2026-12-01", "interviewer_id" => @interviewer.id, "interview_format" => "onsite",
      "internship_supervisor_id" => @supervisor.id, "internship_duration" => "3 смены" })
    planning.launch_campaign(requisition.recruitment_campaign_id, search_query: "Врач")
    requisition
  end

  def start_application(user: @recruiter)
    post "/api/v1/candidate_applications", params: { candidate_application: {
      candidate_id: @candidate.id, job_requisition_id: @requisition.id
    } }, headers: auth(user), as: :json
  end

  def advance(application, user)
    post "/api/v1/candidate_applications/#{application.id}/advance", headers: auth(user)
  end

  def finish(application, user: @recruiter, **overrides)
    attributes = { outcome: "rejected", rejection_reason_id: @reason.id, allow_next_application: false }.merge(overrides)
    post "/api/v1/candidate_applications/#{application.id}/finish", params: { candidate_application: attributes }, headers: auth(user), as: :json
  end
end
