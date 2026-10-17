require "test_helper"
require "timeout"

class CandidateApplicationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @branch = Branch.create!(name: "Applications #{suffix}")
    @department = @branch.departments.create!(name: "HR")
    @role = Role.create!(name: "applications_#{suffix}", permissions: Role::PERMISSIONS)
    @user = User.create!(login: "applications_#{suffix}", full_name: "Recruiter", password: "long-test-password",
      branch: @branch, departments: [ @department ], role: @role)
    @candidate = Candidate.create!(full_name: "Candidate", created_by: @user, responsible_recruiter: @user)
    planner = Recruitment::Planning.new(@user)
    # Different campaigns ensure the candidate lock, rather than campaign lock, serializes starts.
    @requisitions = 2.times.map do
      template = planner.create_template({ "recruiter_id" => @user.id, "title" => "Doctor", "duties" => "Patient care" })
      planner.approve_template(template.id)
      requisition = planner.create_requisition({ "department_id" => @department.id, "vacancy_template_id" => template.id,
        "positions_count" => 2, "salary_amount" => "500000", "salary_currency" => "KZT", "work_schedule" => "5/2",
        "desired_start_on" => "2026-12-01", "interviewer_id" => @user.id, "interview_format" => "onsite" })
      planner.launch_campaign(requisition.recruitment_campaign_id, search_query: "Doctor")
      requisition
    end
  end

  teardown do
    if @user&.persisted?
      AuditEvent.where(actor_user_id: @user.id).delete_all
      CandidateApplication.where(created_by_id: @user.id).delete_all
      Candidate.where(created_by_id: @user.id).delete_all
      requisitions = JobRequisition.where(created_by_id: @user.id)
      JobRequisitionVersion.where(job_requisition_id: requisitions.select(:id)).delete_all
      requisitions.delete_all
      templates = VacancyTemplate.where(created_by_id: @user.id)
      RecruitmentCampaign.where(vacancy_template_id: templates.select(:id)).delete_all
      VacancyTemplateVersion.where(vacancy_template_id: templates.select(:id)).delete_all
      templates.delete_all
      @user.destroy!
    end
    @role&.destroy!
    @department&.destroy!
    @branch&.reload&.destroy!
  end

  test "two campaigns cannot start concurrent applications for same candidate" do
    ready = Queue.new
    start = Queue.new
    threads = @requisitions.map do |requisition|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          workflow = Candidates::Applications.new(User.find(@user.id))
          ready << true
          start.pop
          workflow.start(candidate_id: @candidate.id, job_requisition_id: requisition.id)
          :started
        rescue Recruitment::Planning::InvalidTransition
          :rejected
        end
      end
    end
    results = Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      threads.map(&:value)
    end
    assert_equal [ :rejected, :started ], results.sort
    assert_equal 1, CandidateApplication.where(candidate_id: @candidate.id, status: "active").count
    assert_equal 1, AuditEvent.where(actor_user_id: @user.id, action: "candidate_application.started").count
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end
end
