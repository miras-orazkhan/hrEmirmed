require "test_helper"

class RecruitmentPlanningTest < ActionDispatch::IntegrationTest
  setup do
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "Клиника")
    @other_department = Branch.create!(name: "Астана").departments.create!(name: "Клиника")
    @hr = staff("hr", %w[read.vacancy_template manage.vacancy_template approve.vacancy_template
      read.job_requisition read.recruitment_campaign read.all_recruitment])
    @recruiter = staff("recruiter", %w[read.vacancy_template read.job_requisition
      manage.job_requisition read.recruitment_campaign launch.recruitment_campaign])
    @other_recruiter = staff("other_recruiter", @recruiter.role.permissions)
    @manager = staff("manager", %w[read.vacancy_template read.job_requisition create.job_requisition
      update.job_requisition conduct.interview supervise.internship])
    @template = Recruitment::Planning.new(@hr).create_template({
      "title" => "Врач-терапевт", "duties" => "Приём пациентов", "recruiter_id" => @recruiter.id,
      "mandatory_requirements" => [ "Действующий сертификат" ], "professional_skills" => [ "Диагностика" ]
    })
    Recruitment::Planning.new(@hr).approve_template(@template.id)
  end

  test "template revision preserves version and requires new approval" do
    original = @template.latest_version
    patch "/api/v1/vacancy_templates/#{@template.id}", params: { vacancy_template: { title: "Врач общей практики" } }, headers: auth(@hr), as: :json
    assert_response :success
    assert_equal "draft", response.parsed_body["status"]
    assert_equal 2, response.parsed_body.dig("current_version", "version_number")
    assert_equal "Врач-терапевт", original.reload.title
    create_request
    assert_response :conflict
    post "/api/v1/vacancy_templates/#{@template.id}/approve", headers: auth(@hr)
    assert_response :success
    create_request
    assert_response :created
  end

  test "HR creates template through API and department manager cannot create one" do
    attributes = { vacancy_template: { title: "Медсестра", duties: "Уход за пациентами",
      recruiter_id: @recruiter.id, mandatory_requirements: [ "Сертификат" ] } }
    post "/api/v1/vacancy_templates", params: attributes, headers: auth(@manager), as: :json
    assert_response :forbidden
    assert_difference "VacancyTemplate.count", 1 do
      post "/api/v1/vacancy_templates", params: attributes, headers: auth(@hr), as: :json
    end
    assert_response :created
    assert_equal "draft", response.parsed_body["status"]
    assert_equal [ "Сертификат" ], response.parsed_body.dig("current_version", "mandatory_requirements")
    assert_equal @hr.id, response.parsed_body["created_by_id"]
  end

  test "manager cannot modify approve or read draft templates" do
    patch "/api/v1/vacancy_templates/#{@template.id}", params: { vacancy_template: { title: "Changed" } }, headers: auth(@manager), as: :json
    assert_response :forbidden
    post "/api/v1/vacancy_templates/#{@template.id}/approve", headers: auth(@manager)
    assert_response :forbidden
    Recruitment::Planning.new(@hr).revise_template(@template.id, { "duties" => "Новые обязанности" })
    get "/api/v1/vacancy_templates/#{@template.id}", headers: auth(@manager)
    assert_response :not_found
  end

  test "same template requests share pending campaign and assigned recruiter" do
    create_request
    assert_response :created
    first = response.parsed_body
    create_request
    assert_response :created
    assert_equal first["recruitment_campaign_id"], response.parsed_body["recruitment_campaign_id"]
    assert_equal @recruiter.id, first["recruiter_id"]
    assert_equal "ready", first["status"]
    assert_equal 1, RecruitmentCampaign.count
    assert_equal "pending_approval", RecruitmentCampaign.first.status
    assert_raises(ActiveRecord::InvalidForeignKey) do
      JobRequisition.transaction(requires_new: true) do
        JobRequisition.where(id: first["id"]).update_all(recruiter_id: @other_recruiter.id)
      end
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      JobRequisition.transaction(requires_new: true) do
        JobRequisition.where(id: first["id"]).update_all(status: "closed")
      end
    end
  end

  test "only assigned recruiter can launch and invalid search query rolls back" do
    create_request
    campaign = RecruitmentCampaign.first
    post "/api/v1/recruitment_campaigns/#{campaign.id}/launch", params: { recruitment_campaign: { search_query: "Врач" } }, headers: auth(@other_recruiter), as: :json
    assert_response :forbidden
    post "/api/v1/recruitment_campaigns/#{campaign.id}/launch", params: { recruitment_campaign: { search_query: " " } }, headers: auth(@recruiter), as: :json
    assert_response :unprocessable_entity
    assert_equal "ready", JobRequisition.first.status
    launch(campaign)
    assert_response :success
    assert_equal "active", campaign.reload.status
    assert_equal @recruiter.id, campaign.approved_by_id
    assert_equal "recruiting", JobRequisition.first.status
  end

  test "new request joins active campaign without additional approval" do
    create_request
    campaign = RecruitmentCampaign.first
    launch(campaign)
    approved_at = campaign.reload.approved_at
    create_request
    assert_response :created
    assert_equal "recruiting", response.parsed_body["status"]
    assert_equal approved_at, campaign.reload.approved_at
  end

  test "pausing one request leaves others running and last pause stops campaign" do
    create_request
    first = JobRequisition.last
    create_request
    second = JobRequisition.last
    campaign = RecruitmentCampaign.first
    launch(campaign)
    post "/api/v1/job_requisitions/#{first.id}/pause", headers: auth(@recruiter)
    assert_response :success
    assert_equal "active", campaign.reload.status
    assert_equal "recruiting", second.reload.status
    post "/api/v1/job_requisitions/#{second.id}/pause", headers: auth(@recruiter)
    assert_response :success
    assert_equal "paused", campaign.reload.status
  end

  test "resuming last paused request waits for explicit campaign approval" do
    create_request
    requisition = JobRequisition.last
    campaign = RecruitmentCampaign.first
    launch(campaign)
    post "/api/v1/job_requisitions/#{requisition.id}/pause", headers: auth(@recruiter)
    post "/api/v1/job_requisitions/#{requisition.id}/resume", headers: auth(@recruiter)
    assert_response :success
    assert_equal "ready", requisition.reload.status
    assert_equal "paused", campaign.reload.status
    launch(campaign)
    assert_response :success
    assert_equal "recruiting", requisition.reload.status
  end

  test "new request in paused campaign waits for recruiter and paused ones stay paused" do
    create_request
    first = JobRequisition.last
    campaign = RecruitmentCampaign.first
    launch(campaign)
    post "/api/v1/job_requisitions/#{first.id}/pause", headers: auth(@recruiter)
    create_request
    assert_equal "ready", response.parsed_body["status"]
    launch(campaign)
    assert_response :success
    assert_equal "paused", first.reload.status
    assert_equal "recruiting", JobRequisition.last.status
  end

  test "cancelled request cannot resume and campaign without ready requests cannot launch" do
    create_request
    requisition = JobRequisition.last
    campaign = RecruitmentCampaign.first
    post "/api/v1/job_requisitions/#{requisition.id}/cancel", headers: auth(@recruiter)
    assert_response :success
    post "/api/v1/job_requisitions/#{requisition.id}/resume", headers: auth(@recruiter)
    assert_response :conflict
    launch(campaign)
    assert_response :conflict
    assert_equal "cancelled", requisition.reload.status
  end

  test "condition updates preserve old salary and cannot override system fields" do
    create_request
    requisition = JobRequisition.last
    original = requisition.latest_version
    patch "/api/v1/job_requisitions/#{requisition.id}", params: { job_requisition: {
      salary_amount: "650000.50", status: "closed", filled_positions_count: 2,
      recruiter_id: @other_recruiter.id, vacancy_template_version_id: 999, title: "Changed"
    } }, headers: auth(@manager), as: :json
    assert_response :success
    assert_equal "650000.5", response.parsed_body.dig("current_version", "salary_amount")
    assert_equal BigDecimal("500000"), original.reload.salary_amount
    assert_equal "ready", requisition.reload.status
    assert_equal 0, requisition.filled_positions_count
    assert_equal @recruiter.id, requisition.recruiter_id
    assert_raises(ActiveRecord::ReadOnlyRecord) { original.update!(work_schedule: "Changed") }
  end

  test "existing request pins template version after template revision" do
    create_request
    requisition = JobRequisition.last
    pinned = requisition.vacancy_template_version_id
    Recruitment::Planning.new(@hr).revise_template(@template.id, { "title" => "Updated title" })
    assert_equal pinned, requisition.reload.vacancy_template_version_id
    assert_equal "Врач-терапевт", requisition.vacancy_template_version.title
  end

  test "requests cannot be created or edited for another department" do
    create_request(department_id: @other_department.id)
    assert_response :forbidden
    assert_equal 0, JobRequisition.count
    create_request
    requisition = JobRequisition.last
    @manager.update!(branch: @other_department.branch, departments: [ @other_department ])
    patch "/api/v1/job_requisitions/#{requisition.id}", params: { job_requisition: { salary_amount: "1" } }, headers: auth(@manager), as: :json
    assert_response :forbidden
    get "/api/v1/job_requisitions/#{requisition.id}", headers: auth(@manager)
    assert_response :not_found
  end

  test "foreign recruiter cannot see or transition request and HR can read all" do
    create_request
    requisition = JobRequisition.last
    # Put the other recruiter outside the department scope as well.
    @other_recruiter.update!(branch: @other_department.branch, departments: [ @other_department ])
    get "/api/v1/job_requisitions/#{requisition.id}", headers: auth(@other_recruiter)
    assert_response :not_found
    post "/api/v1/job_requisitions/#{requisition.id}/pause", headers: auth(@other_recruiter)
    assert_response :forbidden
    get "/api/v1/recruitment_campaigns/#{requisition.recruitment_campaign_id}", headers: auth(@other_recruiter)
    assert_response :not_found
    get "/api/v1/job_requisitions/#{requisition.id}", headers: auth(@hr)
    assert_response :success
  end

  test "invalid conditions roll back campaign request version and audit" do
    counts = [ RecruitmentCampaign.count, JobRequisition.count, JobRequisitionVersion.count, AuditEvent.count ]
    create_request(salary_amount: "-1", positions_count: 0)
    assert_response :unprocessable_entity
    assert_equal counts, [ RecruitmentCampaign.count, JobRequisition.count, JobRequisitionVersion.count, AuditEvent.count ]
  end

  test "mandatory internship requires criteria and defaults supervisor to manager" do
    Recruitment::Planning.new(@hr).revise_template(@template.id, {
      "internship_required" => true, "internship_criteria" => [ "Работа с пациентом" ]
    })
    Recruitment::Planning.new(@hr).approve_template(@template.id)
    create_request
    assert_response :unprocessable_entity
    create_request(internship_duration: "3 смены")
    assert_response :created
    assert_equal @manager.id, response.parsed_body.dig("current_version", "internship_supervisor_id")
  end

  test "unauthorized interviewer and unavailable recruiter are rejected" do
    create_request(interviewer_id: @hr.id)
    assert_response :unprocessable_entity
    @recruiter.update!(active: false)
    create_request
    assert_response :conflict
  end

  test "changing recruiter after campaign creation requires explicit transfer workflow" do
    create_request
    patch "/api/v1/vacancy_templates/#{@template.id}", params: { vacancy_template: { recruiter_id: @other_recruiter.id } }, headers: auth(@hr), as: :json
    assert_response :conflict
    assert_equal @recruiter.id, @template.reload.recruiter_id
    assert_equal 1, @template.versions.count
  end

  test "lists return latest versions and support cursor pagination" do
    create_request
    first = JobRequisition.last
    patch "/api/v1/job_requisitions/#{first.id}", params: { job_requisition: { work_schedule: "2/2" } }, headers: auth(@manager), as: :json
    create_request
    get "/api/v1/job_requisitions", params: { limit: 1 }, headers: auth(@manager)
    assert_response :success
    assert_equal 2, response.parsed_body.first.dig("current_version", "version_number")
    cursor = response.headers.fetch("X-Next-Cursor")
    get "/api/v1/job_requisitions", params: { limit: 1, cursor: cursor }, headers: auth(@manager)
    assert_response :success
    assert_equal 1, response.parsed_body.first.dig("current_version", "version_number")
    get "/api/v1/job_requisitions/#{first.id}/versions", headers: auth(@manager)
    assert_equal [ 1, 2 ], response.parsed_body.pluck("version_number")
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

  def create_request(**overrides)
    attributes = { department_id: @department.id, vacancy_template_id: @template.id,
      positions_count: 2, salary_amount: "500000.00", salary_currency: "KZT", work_schedule: "5/2",
      desired_start_on: "2026-12-01", interviewer_id: @manager.id, interview_format: "onsite" }
    post "/api/v1/job_requisitions", params: { job_requisition: attributes.merge(overrides) }, headers: auth(@manager), as: :json
  end

  def launch(campaign)
    post "/api/v1/recruitment_campaigns/#{campaign.id}/launch", params: {
      recruitment_campaign: { search_query: "Терапевт, действующий сертификат, Алматы" }
    }, headers: auth(@recruiter), as: :json
  end
end
