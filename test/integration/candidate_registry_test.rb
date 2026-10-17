require "test_helper"

class CandidateRegistryTest < ActionDispatch::IntegrationTest
  setup do
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "Клиника")
    @hr = staff("registry_hr", %w[read.candidate read.all_candidates create.candidate update.candidate
      resolve.candidate_duplicate manage.all_candidate_duplicates manage.rejection_reason
      manage.vacancy_template approve.vacancy_template create.job_requisition])
    @recruiter = staff("registry_recruiter", %w[read.candidate read.all_candidates create.candidate update.candidate
      manage.candidate_application launch.recruitment_campaign manage.job_requisition resolve.candidate_duplicate])
    @other_recruiter = staff("registry_other", %w[read.candidate read.all_candidates create.candidate update.candidate
      manage.candidate_application launch.recruitment_campaign manage.job_requisition resolve.candidate_duplicate])
    @interviewer = staff("registry_interviewer", %w[read.candidate conduct.interview])
    @template = create_template
    @requisition = create_requisition(@recruiter)
  end

  test "recruiter creates searchable candidate contacts and source atomically" do
    attributes = { full_name: "Айгуль Садыкова", city: "Алматы",
      contacts: [ { kind: "phone", value: "+7 (701) 123-45-67" }, { kind: "email", value: "AIGUL@example.com" } ],
      sources: [ { provider: "hh_kz", external_id: "resume-100" } ] }
    assert_difference({ "Candidate.count" => 1, "CandidateContact.count" => 2, "CandidateSource.count" => 1 }) do
      post "/api/v1/candidates", params: { candidate: attributes }, headers: auth(@recruiter), as: :json
    end
    assert_response :created
    candidate = Candidate.find(response.parsed_body.fetch("id"))
    assert_equal @recruiter.id, candidate.responsible_recruiter_id
    assert_equal @recruiter.id, candidate.created_by_id
    assert_equal "+77011234567", candidate.contacts.find_by!(kind: "phone").normalized_value

    [ "+7 701 123 45 67", "aigul@example.com", "айгуль" ].each do |query|
      get "/api/v1/candidates", params: { q: query }, headers: auth(@recruiter)
      assert_response :success
      assert_equal [ candidate.id ], response.parsed_body.pluck("id")
    end

    assert_no_difference [ "Candidate.count", "CandidateContact.count", "CandidateSource.count" ] do
      post "/api/v1/candidates", params: { candidate: attributes.merge(full_name: "Второй профиль") },
        headers: auth(@recruiter), as: :json
    end
    assert_response :unprocessable_entity
  end

  test "shared normalized phone creates pending duplicate without merging and name alone is not a duplicate" do
    first = create_candidate("Кандидат один", phone: "+7 777 111 22 33")
    same_name = create_candidate("Кандидат один")
    assert_difference "CandidateDuplicate.count", 1 do
      create_candidate("Кандидат два", phone: "+7 (777) 111-22-33")
    end
    duplicate = CandidateDuplicate.order(:id).last
    assert_equal "pending", duplicate.status
    assert_equal [ first.id, Candidate.order(:id).last.id ].sort, [ duplicate.candidate_id, duplicate.other_candidate_id ]
    assert_equal 2, Candidate.where(full_name: "Кандидат один").count
    assert_equal 0, CandidateDuplicate.where(candidate_id: same_name.id).or(CandidateDuplicate.where(other_candidate_id: same_name.id)).count
  end

  test "multiple shared contacts make one duplicate and repeated detection preserves resolution" do
    first = post_candidate("Pair A", contacts: [
      { kind: "phone", value: "+7 (700) 111-22-33" }, { kind: "email", value: "pair@example.com" }
    ])
    second = post_candidate("Pair B", contacts: [
      { kind: "phone", value: "+77001112233" }, { kind: "email", value: "PAIR@example.com" }
    ])
    assert_equal 1, CandidateDuplicate.count
    duplicate = CandidateDuplicate.first
    assert_equal [ first.id, second.id ].sort, [ duplicate.candidate_id, duplicate.other_candidate_id ]

    post "/api/v1/candidate_duplicates/#{duplicate.id}/resolve",
      params: { candidate_duplicate: { status: "distinct" } }, headers: auth(@recruiter), as: :json
    assert_response :success
    assert_equal "distinct", duplicate.reload.status

    patch "/api/v1/candidates/#{second.id}", params: { candidate: {
      contacts: [ { kind: "phone", value: "+7 700 111 22 33" }, { kind: "email", value: "pair@example.com" } ]
    } }, headers: auth(@recruiter), as: :json
    assert_response :success
    assert_equal 1, CandidateDuplicate.count
    assert_equal "distinct", duplicate.reload.status
  end

  test "invalid contact replacement rolls back candidate and associated records" do
    candidate = post_candidate("Stable candidate", contacts: [
      { kind: "phone", value: "+77009990001" }, { kind: "email", value: "stable@example.com" }
    ])
    candidate.sources.create!(provider: "manual", external_id: "stable-record")
    original_contacts = candidate.contacts.order(:id).pluck(:kind, :value, :normalized_value)
    original_candidate_count = Candidate.count
    original_source_count = CandidateSource.count
    original_duplicate_count = CandidateDuplicate.count

    patch "/api/v1/candidates/#{candidate.id}", params: { candidate: {
      full_name: "Must roll back", contacts: [ { kind: "phone", value: "12345" } ]
    } }, headers: auth(@recruiter), as: :json

    assert_response :unprocessable_entity
    assert_equal "Stable candidate", candidate.reload.full_name
    assert_equal original_contacts, candidate.contacts.order(:id).pluck(:kind, :value, :normalized_value)
    assert_equal original_candidate_count, Candidate.count
    assert_equal original_source_count, CandidateSource.count
    assert_equal original_duplicate_count, CandidateDuplicate.count
  end

  test "same owner recruiter can review duplicates while cross owner pair requires HR" do
    owned_a = create_candidate("Профиль А", phone: "+77001110001", owner: @recruiter)
    owned_b = create_candidate("Профиль Б", phone: "+77001110001", owner: @recruiter)
    same_owner_duplicate = CandidateDuplicate.order(:id).last
    start_application(owned_a, @requisition, @recruiter)
    original_application = CandidateApplication.last
    other_owner = create_candidate("Профиль В", phone: "+77002220002", owner: @other_recruiter)
    cross_owner = create_candidate("Профиль Г", phone: "+77002220002", owner: @recruiter)
    cross_owner_duplicate = CandidateDuplicate.order(:id).last

    get "/api/v1/candidate_duplicates", headers: auth(@recruiter)
    assert_response :success
    ids = response.parsed_body.pluck("id")
    assert_includes ids, same_owner_duplicate.id
    assert_not_includes ids, cross_owner_duplicate.id

    post "/api/v1/candidate_duplicates/#{same_owner_duplicate.id}/resolve",
      params: { candidate_duplicate: { status: "confirmed", resolution_note: "Проверено HR" } },
      headers: auth(@recruiter), as: :json
    assert_response :success
    assert_equal "confirmed", same_owner_duplicate.reload.status
    assert Candidate.exists?(owned_a.id)
    assert Candidate.exists?(owned_b.id)
    assert CandidateApplication.exists?(original_application.id)

    post "/api/v1/candidate_duplicates/#{cross_owner_duplicate.id}/resolve",
      params: { candidate_duplicate: { status: "distinct" } }, headers: auth(@recruiter), as: :json
    assert_response :not_found
    post "/api/v1/candidate_duplicates/#{cross_owner_duplicate.id}/resolve",
      params: { candidate_duplicate: { status: "distinct" } }, headers: auth(@hr), as: :json
    assert_response :success
    assert_equal "distinct", cross_owner_duplicate.reload.status
    assert response.parsed_body.key?("assignee_user_id")
    assert_nil response.parsed_body["assignee_user_id"]
    assert Candidate.exists?(other_owner.id)
    assert Candidate.exists?(cross_owner.id)
    assert CandidateContact.exists?(candidate_id: other_owner.id)
    assert CandidateContact.exists?(candidate_id: cross_owner.id)
  end

  test "interviewer sees candidate only while assigned interview permission remains" do
    candidate = create_candidate("Интервью кандидат", phone: "+77003330003")
    start_application(candidate, @requisition, @recruiter)
    application = CandidateApplication.last
    2.times { post "/api/v1/candidate_applications/#{application.id}/advance", headers: auth(@recruiter) }
    get "/api/v1/candidates/#{candidate.id}", headers: auth(@interviewer)
    assert_response :success
    get "/api/v1/candidate_applications/#{application.id}", headers: auth(@interviewer)
    assert_response :success

    @interviewer.role.update!(permissions: [ "read.candidate" ])
    get "/api/v1/candidates/#{candidate.id}", headers: auth(@interviewer)
    assert_response :not_found
    get "/api/v1/candidate_applications/#{application.id}", headers: auth(@interviewer)
    assert_response :not_found

    department_only = staff("registry_department_only", [ "read.candidate" ])
    get "/api/v1/candidates/#{candidate.id}", headers: auth(department_only)
    assert_response :not_found
  end

  test "foreign recruiter with global read access cannot update candidate" do
    candidate = create_candidate("Закрытый кандидат", phone: "+77004440004", owner: @recruiter)
    role = Role.create!(name: "registry_limited", permissions: %w[read.candidate read.all_candidates update.candidate])
    foreign = User.create!(login: "registry_limited", full_name: "Foreign", role: role,
      branch: @branch, departments: [ @department ], password: "long-test-password")
    get "/api/v1/candidates/#{candidate.id}", headers: auth(foreign)
    assert_response :success
    patch "/api/v1/candidates/#{candidate.id}", params: { candidate: { full_name: "Changed" } },
      headers: auth(foreign), as: :json
    assert_response :forbidden
    assert_equal "Закрытый кандидат", candidate.reload.full_name
  end

  test "scalar resource payloads return bad request without creating records" do
    candidate_a = create_candidate("Payload A", phone: "+77007770007")
    candidate_b = create_candidate("Payload B", phone: "+77007770007")
    duplicate = CandidateDuplicate.order(:id).last

    assert_no_difference "Candidate.count" do
      post "/api/v1/candidates", params: { candidate: "invalid" }, headers: auth(@recruiter), as: :json
    end
    assert_response :bad_request

    post "/api/v1/candidate_duplicates/#{duplicate.id}/resolve",
      params: { candidate_duplicate: "invalid" }, headers: auth(@hr), as: :json
    assert_response :bad_request
    assert_equal "pending", duplicate.reload.status

    assert_no_difference "RejectionReason.count" do
      post "/api/v1/rejection_reasons", params: { rejection_reason: "invalid" }, headers: auth(@hr), as: :json
    end
    assert_response :bad_request
    assert Candidate.exists?(candidate_a.id)
    assert Candidate.exists?(candidate_b.id)
  end

  test "cancelling active applications requires an explicit next application choice" do
    candidate = create_candidate("Отмена кандидат", phone: "+77005550005")
    start_application(candidate, @requisition, @recruiter)
    application = CandidateApplication.last
    before_stage = application.stage

    post "/api/v1/job_requisitions/#{@requisition.id}/cancel", headers: auth(@recruiter)
    assert_response :conflict
    post "/api/v1/job_requisitions/#{@requisition.id}/cancel",
      params: { job_requisition: { allow_next_application: "maybe" } }, headers: auth(@recruiter), as: :json
    assert_response :conflict
    assert_equal "recruiting", @requisition.reload.status
    assert_equal "active", application.reload.status
    assert_equal before_stage, application.stage

    post "/api/v1/job_requisitions/#{@requisition.id}/cancel",
      params: { job_requisition: { allow_next_application: false } }, headers: auth(@recruiter), as: :json
    assert_response :success
    assert_equal "cancelled", @requisition.reload.status
    assert_equal "completed", application.reload.status
    assert_equal "cancelled", application.outcome
    assert_equal before_stage, application.stage
    assert_equal false, application.allow_next_application
    assert_equal @recruiter.id, application.decided_by_id
    assert_not_nil application.ended_at

    second_requisition = create_requisition(@recruiter)
    second_candidate = create_candidate("Отмена с продолжением", phone: "+77006660006")
    start_application(second_candidate, second_requisition, @recruiter)
    second_application = CandidateApplication.order(:id).last
    post "/api/v1/job_requisitions/#{second_requisition.id}/cancel",
      params: { job_requisition: { allow_next_application: true } }, headers: auth(@recruiter), as: :json
    assert_response :success
    assert_equal "completed", second_application.reload.status
    assert_equal "cancelled", second_application.outcome
    assert_equal true, second_application.allow_next_application
    assert_equal "screening", second_application.stage
  end

  test "candidate query sanitizes wildcard and injection text, paginates and omits secrets" do
    create_candidate("Иван Иванов")
    create_candidate("Иван Петров")
    create_candidate("Игорь Иванов")
    headers = auth(@recruiter)

    get "/api/v1/candidates", params: { q: "Иван", limit: 1 }, headers: headers
    assert_response :success
    first = response.parsed_body.first
    assert_equal [ "Иван Иванов" ], [ first.fetch("full_name") ]
    refute first.key?("password")
    refute first.key?("password_digest")
    cursor = response.headers.fetch("X-Next-Cursor")
    get "/api/v1/candidates", params: { q: "Иван", limit: 1, cursor: cursor }, headers: headers
    assert_response :success
    assert_equal [ "Иван Петров" ], response.parsed_body.pluck("full_name")
    assert_nil response.headers["X-Next-Cursor"]

    get "/api/v1/candidates", params: { q: "%" }, headers: headers
    assert_response :success
    assert_empty response.parsed_body
    get "/api/v1/candidates", params: { q: "' OR 1=1 --" }, headers: headers
    assert_response :success
    assert_empty response.parsed_body
    get "/api/v1/candidates", params: { limit: 201 }, headers: headers
    assert_response :bad_request
  end

  test "listing candidates does not add one query per record" do
    create_candidate("Query candidate one", phone: "+77008880001")
    headers = auth(@recruiter)
    small_count = sql_count { get "/api/v1/candidates", headers: headers }
    5.times { |index| create_candidate("Query candidate #{index + 2}", phone: "+7700888#{format('%04d', index + 2)}") }
    large_count = sql_count { get "/api/v1/candidates", headers: headers }
    assert_response :success
    assert_equal 6, response.parsed_body.size
    assert_equal small_count, large_count
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

  def create_template
    planning = Recruitment::Planning.new(@hr)
    template = planning.create_template({ "title" => "Врач", "duties" => "Приём",
      "recruiter_id" => @recruiter.id, "internship_required" => false, "internship_criteria" => [] })
    planning.approve_template(template.id)
    template
  end

  def create_requisition(recruiter)
    # The approved template is assigned to this recruiter by the planning workflow.
    @template.update!(recruiter: recruiter) if @template.recruiter_id != recruiter.id
    planning = Recruitment::Planning.new(@hr)
    requisition = planning.create_requisition({ "department_id" => @department.id,
      "vacancy_template_id" => @template.id, "positions_count" => 3, "salary_amount" => "500000",
      "salary_currency" => "KZT", "work_schedule" => "5/2", "desired_start_on" => "2026-12-01",
      "interviewer_id" => @interviewer.id, "interview_format" => "onsite" })
    Recruitment::Planning.new(recruiter).launch_campaign(requisition.recruitment_campaign_id, search_query: "Врач")
    requisition
  end

  def create_candidate(name, phone: nil, owner: @recruiter)
    contacts = phone ? [ { kind: "phone", value: phone } ] : []
    post_candidate(name, contacts: contacts, owner: owner)
  end

  def post_candidate(name, contacts:, owner: @recruiter)
    post "/api/v1/candidates", params: { candidate: { full_name: name, contacts: contacts } },
      headers: auth(owner), as: :json
    assert_response :created
    Candidate.find(response.parsed_body.fetch("id"))
  end

  def sql_count
    count = 0
    callback = ->(_name, _start, _finish, _id, payload) do
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def start_application(candidate, requisition, recruiter)
    post "/api/v1/candidate_applications", params: { candidate_application: {
      candidate_id: candidate.id, job_requisition_id: requisition.id
    } }, headers: auth(recruiter), as: :json
    assert_response :created
  end
end
