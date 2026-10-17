require "test_helper"
require "tempfile"

class WebInterfaceTest < ActionDispatch::IntegrationTest
  setup do
    Web::SessionsController::LOGIN_LIMIT_STORE.clear
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "Клиника")
    @admin = staff("web_admin", [])
    @hr = staff("web_hr", %w[read.vacancy_template manage.vacancy_template approve.vacancy_template
      read.job_requisition create.job_requisition update.job_requisition manage.job_requisition
      read.recruitment_campaign launch.recruitment_campaign read.all_recruitment])
    @recruiter = staff("web_recruiter", %w[read.vacancy_template read.job_requisition create.job_requisition
      update.job_requisition manage.job_requisition read.recruitment_campaign launch.recruitment_campaign
      read.candidate read.all_candidates create.candidate update.candidate manage.candidate_application])
    @interviewer = staff("web_interviewer", %w[read.candidate conduct.interview])
    @rejection_reason = RejectionReason.create!(name: "Не подходит")
  end

  test "web login rejects bad credentials and logout revokes cookie-backed session" do
    post "/session", params: { session: { login: @hr.login, password: "wrong-password" } }
    assert_response :unprocessable_entity
    assert_equal 0, AuthSession.count

    login(@hr)
    assert_response :see_other
    session_row = AuthSession.order(:id).last
    assert session_row
    assert response.headers["Set-Cookie"].present?
    get "/"
    assert_response :redirect
    assert_equal "/job_requisitions", response.headers["Location"].delete_prefix("http://www.example.com")

    delete "/session"
    assert_response :see_other
    assert_not AuthSession.exists?(session_row.id)
    get "/candidates"
    assert_response :redirect
    assert_equal "/session/new", response.headers["Location"].delete_prefix("http://www.example.com")
  end

  test "expired and disabled web sessions are rejected and home route follows permissions" do
    login(@hr)
    expired = AuthSession.order(:id).last
    expired.update!(expires_at: 1.second.ago)
    get "/vacancy_templates", headers: { "Turbo-Frame" => "applications_candidate_1" }
    assert_response :see_other
    assert_equal "/session/new", response.headers["Location"].delete_prefix("http://www.example.com")
    get response.headers["Location"], headers: { "Turbo-Frame" => "applications_candidate_1" }
    assert_response :success
    assert_includes response.body, '<meta name="turbo-visit-control" content="reload">'

    login(@recruiter)
    get "/"
    assert_response :redirect
    assert_equal "/candidates", response.headers["Location"].delete_prefix("http://www.example.com")
    @recruiter.update!(active: false)
    get "/candidates"
    assert_response :redirect
    assert_equal "/session/new", response.headers["Location"].delete_prefix("http://www.example.com")
  end

  test "candidate form persists multiple contacts and redisplays invalid values" do
    login(@recruiter)
    post "/candidates", params: { candidate: {
      full_name: "Айгуль Кандидат", city: "Алматы", preferred_language: "ru",
      contacts_attributes: [
        { kind: "phone", value: "+7 701 123 45 67" },
        { kind: "email", value: "aigul@example.test" }
      ]
    } }
    assert_response :see_other
    candidate = Candidate.order(:id).last
    assert_equal %w[email phone], candidate.contacts.order(:kind).pluck(:kind)
    assert_equal 2, candidate.contacts.count

    patch "/candidates/#{candidate.id}", params: { candidate: {
      full_name: "Айгуль Обновлённая", city: "Караганда", contacts_attributes: [
        { kind: "phone", value: "+7 701 555 00 11" },
        { kind: "email", value: "updated@example.test" }
      ]
    } }
    assert_response :see_other
    assert_equal "Айгуль Обновлённая", candidate.reload.full_name
    assert_equal [ "updated@example.test", "+7 701 555 00 11" ], candidate.contacts.order(:kind).pluck(:value)

    post "/candidates", params: { candidate: {
      full_name: "", city: "Астана", contacts_attributes: [
        { kind: "phone", value: "+7 777 000 00 01" },
        { kind: "email", value: "invalid-address" }
      ]
    } }
    assert_response :unprocessable_entity
    assert_includes response.body, "+7 777 000 00 01"
    assert_includes response.body, "invalid-address"
    assert_equal 1, Candidate.count
  end

  test "candidate list search and cursor flow returns every item and supports Turbo frame" do
    login(@recruiter)
    51.times do |index|
      Candidate.create!(full_name: format("Кандидат %03d", index), created_by: @recruiter,
        responsible_recruiter: @recruiter,
        contacts: index == 50 ? [ CandidateContact.new(kind: "email", value: "special@example.test") ] : [])
    end
    get "/candidates", params: { q: "Кандидат" }
    assert_response :success
    assert_includes response.body, "Кандидат 000"
    assert_includes response.body, "Кандидат 049"
    assert_not_includes response.body, "Кандидат 050"
    assert_match(/workflow_list/, response.body)
    assert_match(/turbo-frame/, response.body)
    cursor = response.body[/name=[\"']cursor[\"'][^>]*value=[\"'](\d+)[\"']/i, 1]
    cursor ||= response.body[/[?&]cursor=(\d+)/, 1]
    assert cursor, "first page should provide a continuation cursor"
    get "/candidates", params: { q: "Кандидат", cursor: cursor }, headers: { "Turbo-Frame" => "workflow_list" }
    assert_response :success
    assert_includes response.body, "Кандидат 050"
    assert_not_includes response.body, "Кандидат 049"
    get "/candidates", params: { q: "special@example.test" }
    assert_response :success
    assert_includes response.body, "Кандидат 050"
    get "/candidates", params: { q: "нет такого" }
    assert_response :success
    assert_match(/ничего|не найден|нет кандидатов/i, response.body)
  end

  test "requisition and campaign pagination links retain active filters" do
    login(@hr)
    planning = Recruitment::Planning.new(@hr)
    51.times do |index|
      template = planning.create_template({ "title" => "Шаблон #{index}", "duties" => "Работа",
        "recruiter_id" => @recruiter.id })
      planning.approve_template(template.id)
      planning.create_requisition({ "department_id" => @department.id, "vacancy_template_id" => template.id,
        "positions_count" => 1, "salary_amount" => "500000", "salary_currency" => "KZT",
        "work_schedule" => "5/2", "desired_start_on" => "2026-12-01", "interviewer_id" => @interviewer.id,
        "interview_format" => "onsite" })
    end

    get "/job_requisitions", params: { department_id: @department.id }
    assert_response :success
    next_link = css_select("a[rel='next']").first
    assert next_link, "department-filtered requisition page should offer a next page"
    requisition_query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
    assert_equal @department.id.to_s, requisition_query["department_id"]

    get "/recruitment_campaigns", params: { status: "pending_approval" }
    assert_response :success
    next_link = css_select("a[rel='next']").first
    assert next_link, "status-filtered campaign page should offer a next page"
    campaign_query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
    assert_equal "pending_approval", campaign_query["status"]
  end

  test "application mutations return matching candidate Turbo frame" do
    login(@recruiter)
    candidate = Candidate.create!(full_name: "Turbo candidate", created_by: @recruiter,
      responsible_recruiter: @recruiter)
    requisition = create_requisition
    frame = "applications_candidate_#{candidate.id}"
    headers = { "Turbo-Frame" => frame }

    post "/candidate_applications", params: { candidate_application: {
      candidate_id: candidate.id, job_requisition_id: requisition.id
    } }, headers: headers
    assert_response :see_other
    application = CandidateApplication.order(:id).last
    get response.headers["Location"], headers: headers
    assert_response :success
    assert_select "turbo-frame##{frame}"

    post "/candidate_applications/#{application.id}/advance", headers: headers
    assert_response :see_other
    assert_equal "test_review", application.reload.stage
    get response.headers["Location"], headers: headers
    assert_response :success
    assert_select "turbo-frame##{frame}"

    post "/candidate_applications/#{application.id}/finish", params: { candidate_application: {
      outcome: "withdrawn", allow_next_application: "false", decision_comment: "Решение принято"
    } }, headers: headers
    assert_response :see_other
    assert_equal "completed", application.reload.status
    get response.headers["Location"], headers: headers
    assert_response :success
    assert_select "turbo-frame##{frame}"
  end

  test "invalid finish keeps decision comment and selected boolean in candidate Turbo frame" do
    login(@recruiter)
    candidate = Candidate.create!(full_name: "Invalid decision candidate", created_by: @recruiter,
      responsible_recruiter: @recruiter)
    requisition = create_requisition
    application = Candidates::Applications.new(@recruiter).start(candidate_id: candidate.id,
      job_requisition_id: requisition.id)
    frame = "applications_candidate_#{candidate.id}"
    headers = { "Turbo-Frame" => frame }

    post "/candidate_applications/#{application.id}/finish", params: { candidate_application: {
      outcome: "hired", allow_next_application: "true", decision_comment: "Сохранить комментарий"
    } }, headers: headers
    assert_response :unprocessable_entity
    assert_select "turbo-frame##{frame}"
    assert_includes response.body, "Сохранить комментарий"
    assert_select "select[name='candidate_application[allow_next_application]'] option[value='true'][selected]"

    post "/candidate_applications/#{application.id}/finish", params: { candidate_application: {
      outcome: "rejected", rejection_reason_id: "", allow_next_application: "false",
      decision_comment: "Причина ещё не выбрана"
    } }, headers: headers
    assert_response :unprocessable_entity
    assert_select "turbo-frame##{frame}"
    assert_includes response.body, "Причина ещё не выбрана"
    assert_select "select[name='candidate_application[outcome]'] option[value='rejected'][selected]"
    assert_select "select[name='candidate_application[allow_next_application]'] option[value='false'][selected]"
    assert_equal "active", application.reload.status
  end

  test "interviewer sees own candidate and assigned applications without requisition permission" do
    requisition, candidate, application = create_interview_application
    Candidates::Applications.new(@interviewer).finish(application.id,
      { "outcome" => "withdrawn", "allow_next_application" => true })
    other_interviewer = staff("web_other_interviewer", %w[read.candidate conduct.interview])
    other_requisition = create_requisition(interviewer: other_interviewer)
    other_application = Candidates::Applications.new(@recruiter).start(candidate_id: candidate.id,
      job_requisition_id: other_requisition.id)
    2.times { other_application = Candidates::Applications.new(@recruiter).advance(other_application.id) }

    login(@interviewer)
    get "/candidates/#{candidate.id}"
    assert_response :success
    assert_includes response.body, candidate.full_name
    assert_select "#candidate_application_#{application.id}"
    assert_select "#candidate_application_#{other_application.id}", count: 0
    assert_includes response.body, requisition.vacancy_template_version.title
    assert_not_includes response.body, "job_requisition"
    get "/job_requisitions/#{requisition.id}"
    assert_response :forbidden
  end

  test "foreign resume is hidden and visible resume download is private" do
    candidate = Candidate.create!(full_name: "Private dossier", created_by: @recruiter,
      responsible_recruiter: @recruiter)
    login(@recruiter)
    upload_resume(candidate, "%PDF-1.7\nprivate resume\n%%EOF\n")
    assert_response :see_other
    resume = candidate.resumes.first
    get "/candidates/#{candidate.id}/resumes/#{resume.id}"
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]

    outsider = staff("web_outsider", %w[read.candidate conduct.interview])
    login(outsider)
    get "/candidates/#{candidate.id}/resumes/#{resume.id}"
    assert_response :not_found
    get "/rails/active_storage/blobs/redirect/#{resume.original.blob.signed_id}/resume.pdf"
    assert_response :not_found
  end

  test "candidate PII is escaped in rendered HTML" do
    login(@recruiter)
    candidate = Candidate.create!(full_name: '<script>alert("x")</script>', city: "Алматы",
      summary: '<img src=x onerror="alert(1)">', created_by: @recruiter, responsible_recruiter: @recruiter)
    candidate.contacts.create!(kind: "email", value: "private@example.test")
    get "/candidates/#{candidate.id}"
    assert_response :success
    assert_not_includes response.body, '<script>alert("x")</script>'
    assert_not_includes response.body, '<img src=x onerror="alert(1)">'
    assert_includes response.body, "&lt;script&gt;"
  end

  test "web forms render create and edit states and redisplay invalid workflow submissions" do
    login(@recruiter)
    get "/candidates/new"
    assert_response :success
    candidate = Candidates::Registry.new(@recruiter).create({ "full_name" => "Форма", "contacts" => [] })
    get "/candidates/#{candidate.id}/edit"
    assert_response :success
    get "/candidates/#{candidate.id}/resumes"
    assert_response :success

    requisition = create_requisition
    get "/job_requisitions/new"
    assert_response :success
    post "/job_requisitions", params: { job_requisition: {
      department_id: @department.id, vacancy_template_id: requisition.vacancy_template_id, positions_count: 0,
      salary_amount: "500000", salary_currency: "KZT", work_schedule: "5/2",
      desired_start_on: "2026-12-01", interviewer_id: @interviewer.id, interview_format: "onsite"
    } }
    assert_response :unprocessable_entity
    assert_select "form[action='/job_requisitions']"
    get "/job_requisitions/#{requisition.id}/edit"
    assert_response :success
    get "/recruitment_campaigns/#{requisition.recruitment_campaign_id}"
    assert_response :success
    patch "/job_requisitions/#{requisition.id}", params: { job_requisition: { positions_count: 0 } }
    assert_response :unprocessable_entity
    assert_select "form[action='/job_requisitions/#{requisition.id}']"

    delete "/session"
    login(@hr)
    get "/vacancy_templates/new"
    assert_response :success
    get "/vacancy_templates/#{requisition.vacancy_template_id}/edit"
    assert_response :success
    patch "/vacancy_templates/#{requisition.vacancy_template_id}", params: { vacancy_template: {
      title: "", duties: "", recruiter_id: @recruiter.id, internship_required: "0"
    } }
    assert_response :unprocessable_entity
    assert_select "form[action='/vacancy_templates/#{requisition.vacancy_template_id}']"

    post "/vacancy_templates", params: { vacancy_template: {
      title: "", duties: "", recruiter_id: @recruiter.id, internship_required: "0"
    } }
    assert_response :unprocessable_entity
    assert_select "form[action='/vacancy_templates']"
  end

  test "HTML template approval, requisition creation, and campaign launch validate forms" do
    login(@hr)
    post "/vacancy_templates", params: { vacancy_template: {
      title: "Врач-терапевт", duties: "Приём пациентов", recruiter_id: @recruiter.id,
      mandatory_requirements_lines: "Действующий сертификат", professional_skills_lines: "Диагностика",
      internship_required: "0"
    } }
    assert_response :see_other
    template = VacancyTemplate.order(:id).last
    assert_equal "draft", template.status
    post "/vacancy_templates/#{template.id}/approve"
    assert_response :see_other
    assert_equal "approved", template.reload.status

    post "/job_requisitions", params: { job_requisition: {
      department_id: @department.id, vacancy_template_id: template.id, positions_count: 1,
      salary_amount: "500000", salary_currency: "KZT", work_schedule: "5/2",
      desired_start_on: "2026-12-01", interviewer_id: @interviewer.id, interview_format: "onsite"
    } }
    assert_response :see_other
    requisition = JobRequisition.order(:id).last
    campaign = requisition.recruitment_campaign
    assert_equal "pending_approval", campaign.status
    delete "/session"
    login(@recruiter)
    post "/recruitment_campaigns/#{campaign.id}/launch", params: { recruitment_campaign: { search_query: " " } }
    assert_response :unprocessable_entity
    assert_equal "ready", requisition.reload.status
    assert_includes response.body, "search_query"
    post "/recruitment_campaigns/#{campaign.id}/launch", params: { recruitment_campaign: { search_query: "Врач" } }
    assert_response :see_other
    assert_equal "active", campaign.reload.status
  end

  private

  def staff(login, permissions)
    role = Role.create!(name: login, permissions: permissions)
    User.create!(login: login, full_name: login, password: "long-test-password", role: role,
      branch: @branch, departments: [ @department ])
  end

  def login(user)
    post "/session", params: { session: { login: user.login, password: "long-test-password" } }
  end

  def create_interview_application
    requisition = create_requisition
    candidate = Candidate.create!(full_name: "Интервьюируемый", created_by: @recruiter,
      responsible_recruiter: @recruiter)
    application = Candidates::Applications.new(@recruiter).start(candidate_id: candidate.id,
      job_requisition_id: requisition.id)
    2.times { application = Candidates::Applications.new(@recruiter).advance(application.id) }
    [ requisition, candidate, application ]
  end

  def create_requisition(interviewer: @interviewer)
    planning = Recruitment::Planning.new(@hr)
    template = planning.create_template({ "title" => "Врач-терапевт", "duties" => "Приём",
      "recruiter_id" => @recruiter.id })
    planning.approve_template(template.id)
    requisition = planning.create_requisition({ "department_id" => @department.id,
      "vacancy_template_id" => template.id, "positions_count" => 1, "salary_amount" => "500000",
      "salary_currency" => "KZT", "work_schedule" => "5/2", "desired_start_on" => "2026-12-01",
      "interviewer_id" => interviewer.id, "interview_format" => "onsite" })
    Recruitment::Planning.new(@recruiter).launch_campaign(requisition.recruitment_campaign_id, search_query: "Врач")
    requisition
  end

  def upload_resume(candidate, bytes)
    tempfile = Tempfile.new([ "resume", ".pdf" ])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    post "/candidates/#{candidate.id}/resumes", params: {
      file: Rack::Test::UploadedFile.new(tempfile.path, "application/pdf", true, original_filename: "resume.pdf")
    }
  ensure
    tempfile&.close!
  end
end
