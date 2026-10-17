require "test_helper"

class AccessFoundationTest < ActionDispatch::IntegrationTest
  setup do
    Api::V1::SessionsController::LOGIN_LIMIT_STORE.clear
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "HR")
    @other_branch = Branch.create!(name: "Астана")
    @other_department = @other_branch.departments.create!(name: "Клиника")
    @admin_role = Role.create!(name: "admin")
    @reader_role = Role.create!(name: "reader", permissions: [ "read.organization" ])
    @admin = create_user("admin", @admin_role)
    @reader = create_user("reader", @reader_role)
  end

  test "login issues a token whose digest alone is stored and logout revokes it" do
    post "/api/v1/session", params: { session: { login: " ADMIN ", password: "a-long-test-password" } }, as: :json
    assert_response :created
    token = response.parsed_body.fetch("token")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_not_includes response.body, "password_digest"
    assert_equal Digest::SHA256.hexdigest(token), AuthSession.last.token_digest
    assert_not_equal token, AuthSession.last.token_digest
    headers = { "Authorization" => "Bearer #{token}" }
    get "/api/v1/me", headers: headers
    assert_response :success
    assert_equal "admin", response.parsed_body["role"]
    delete "/api/v1/session", headers: headers
    assert_response :no_content
    get "/api/v1/me", headers: headers
    assert_response :unauthorized
  end

  test "wrong credentials and disabled accounts cannot sign in" do
    post "/api/v1/session", params: { session: { login: "reader", password: "wrong" } }, as: :json
    assert_response :unauthorized
    @reader.update!(active: false)
    post "/api/v1/session", params: { session: { login: "reader", password: "a-long-test-password" } }, as: :json
    assert_response :unauthorized
    assert_equal 0, AuthSession.count
  end

  test "missing and expired credentials are rejected" do
    get "/api/v1/branches"
    assert_response :unauthorized
    session, token = AuthSession.issue!(@reader)
    session.update!(expires_at: 1.second.ago)
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "reader only sees assigned organization scope" do
    headers = auth(@reader)
    get "/api/v1/branches", headers: headers
    assert_response :success
    assert_equal [ @branch.id ], response.parsed_body.pluck("id")
    get "/api/v1/departments", headers: headers
    assert_equal [ @department.id ], response.parsed_body.pluck("id")
    get "/api/v1/branches/#{@other_branch.id}", headers: headers
    assert_response :not_found
    get "/api/v1/departments/#{@other_department.id}", headers: headers
    assert_response :not_found
  end

  test "reader cannot mutate structure or access users roles and audit" do
    headers = auth(@reader)
    assert_no_difference "Branch.count" do
      post "/api/v1/branches", params: { branch: { name: "Forbidden" } }, headers: headers, as: :json
    end
    assert_response :forbidden
    %w[users roles audit_events].each do |resource|
      get "/api/v1/#{resource}", headers: headers
      assert_response :forbidden
    end
  end

  test "admin creates organization and audit atomically" do
    headers = auth(@admin)
    assert_difference [ "LegalEntity.count", "AuditEvent.count" ], 1 do
      post "/api/v1/legal_entities", params: { legal_entity: { name: "ЭМИРМЕД", registration_number: "123" } }, headers: headers, as: :json
    end
    assert_response :created
    assert_equal @admin.id, AuditEvent.last.actor_user_id
    assert_equal "legal_entity.created", AuditEvent.last.action
    get "/api/v1/branches", headers: headers
    assert_equal 2, response.parsed_body.size
  end

  test "admin creates users without exposing secrets" do
    assert_difference "User.count", 1 do
      post "/api/v1/users", params: { user: {
        login: " New.User ", full_name: "Новый сотрудник", password: "a-long-test-password",
        branch_id: @branch.id, department_ids: [ @department.id ], role_id: @reader_role.id
      } }, headers: auth(@admin), as: :json
    end
    assert_response :created
    assert_equal "new.user", response.parsed_body["login"]
    assert_not_includes response.body, "password"
    assert_not_includes AuditEvent.last.changeset.keys, "password_digest"
    assert_not_includes AuditEvent.last.to_json, "a-long-test-password"
  end

  test "invalid cross branch update rolls back department assignments and audit" do
    headers = auth(@admin)
    assert_no_difference "AuditEvent.count" do
      patch "/api/v1/users/#{@reader.id}", params: { user: { department_ids: [ @other_department.id ] } }, headers: headers, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal [ @department.id ], @reader.reload.department_ids
  end

  test "user must have a department and invalid update keeps original membership" do
    patch "/api/v1/users/#{@reader.id}", params: { user: { department_ids: [] } }, headers: auth(@admin), as: :json
    assert_response :unprocessable_entity
    assert_equal [ @department.id ], @reader.reload.department_ids
  end

  test "password change and deactivation revoke existing sessions" do
    headers = auth(@reader)
    patch "/api/v1/users/#{@reader.id}", params: { user: { password: "another-long-password" } }, headers: auth(@admin), as: :json
    assert_response :success
    get "/api/v1/me", headers: headers
    assert_response :unauthorized
    headers = auth(@reader)
    @reader.update!(active: false)
    get "/api/v1/me", headers: headers
    assert_response :unauthorized
  end

  test "permission changes affect existing sessions immediately" do
    headers = auth(@reader)
    @reader_role.update!(permissions: [])
    get "/api/v1/branches", headers: headers
    assert_response :forbidden
  end

  test "user manager cannot create or modify admins" do
    manager_role = Role.create!(name: "user manager", permissions: [ "manage.users" ])
    manager = create_user("manager", manager_role)
    headers = auth(manager)
    patch "/api/v1/users/#{@reader.id}", params: { user: { role_id: @admin_role.id } }, headers: headers, as: :json
    assert_response :forbidden
    patch "/api/v1/users/#{@admin.id}", params: { user: { active: false } }, headers: headers, as: :json
    assert_response :forbidden
    assert @admin.reload.active?
  end

  test "unsupported permission and renaming built in admin are rejected" do
    headers = auth(@admin)
    post "/api/v1/roles", params: { role: { name: "bad", permissions: [ "anything" ] } }, headers: headers, as: :json
    assert_response :unprocessable_entity
    patch "/api/v1/roles/#{@admin_role.id}", params: { role: { name: "renamed" } }, headers: headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "admin", @admin_role.reload.name
  end

  test "department with users cannot move to a different branch" do
    patch "/api/v1/departments/#{@department.id}", params: { department: { branch_id: @other_branch.id } }, headers: auth(@admin), as: :json
    assert_response :unprocessable_entity
    assert_equal @branch.id, @department.reload.branch_id
  end

  test "duplicate login and short password are rejected" do
    assert_no_difference "User.count" do
      post "/api/v1/users", params: { user: {
        login: " READER ", full_name: "Duplicate", password: "short",
        branch_id: @branch.id, department_ids: [ @department.id ], role_id: @reader_role.id
      } }, headers: auth(@admin), as: :json
    end
    assert_response :unprocessable_entity
  end

  test "missing parameters return structured error" do
    post "/api/v1/users", params: {}, headers: auth(@admin), as: :json
    assert_response :bad_request
    assert_equal "invalid_parameters", response.parsed_body["error"]
  end

  test "pagination traverses all users without duplicates and rejects invalid limits" do
    headers = auth(@admin)
    get "/api/v1/users", params: { limit: 1 }, headers: headers
    assert_response :success
    first_id = response.parsed_body.first.fetch("id")
    cursor = response.headers.fetch("X-Next-Cursor")
    get "/api/v1/users", params: { limit: 1, cursor: cursor }, headers: headers
    assert_response :success
    assert_not_equal first_id, response.parsed_body.first.fetch("id")
    assert_nil response.headers["X-Next-Cursor"]
    get "/api/v1/users", params: { limit: 201 }, headers: headers
    assert_response :bad_request
    get "/api/v1/users", params: { cursor: "1 OR 1=1" }, headers: headers
    assert_response :bad_request
  end

  test "audit pagination proceeds from newest to oldest" do
    3.times { AuditEvent.record!(actor: @admin, action: "test", subject: @reader) }
    headers = auth(@admin)
    get "/api/v1/audit_events", params: { limit: 2 }, headers: headers
    first_page = response.parsed_body.pluck("id")
    assert_equal first_page.sort.reverse, first_page
    get "/api/v1/audit_events", params: { limit: 2, cursor: response.headers.fetch("X-Next-Cursor") }, headers: headers
    assert_equal 1, response.parsed_body.size
    assert_operator response.parsed_body.first["id"], :<, first_page.last
  end

  test "listing more users does not add one query per user" do
    headers = auth(@admin)
    get "/api/v1/users", headers: headers
    small_count = sql_count { get "/api/v1/users", headers: headers }
    5.times { |i| create_user("reader#{i}", @reader_role) }
    large_count = sql_count { get "/api/v1/users", headers: headers }
    assert_response :success
    assert_equal 7, response.parsed_body.size
    assert_equal small_count, large_count
  end

  test "login rate limit applies to repeated failures" do
    10.times do
      post "/api/v1/session", params: { session: { login: "absent", password: "wrong" } }, as: :json
      assert_response :unauthorized
    end
    post "/api/v1/session", params: { session: { login: "absent", password: "wrong" } }, as: :json
    assert_response :too_many_requests
  end

  test "user can move branch together with department in one transaction" do
    patch "/api/v1/users/#{@reader.id}", params: { user: {
      branch_id: @other_branch.id, department_ids: [ @other_department.id ]
    } }, headers: auth(@admin), as: :json
    assert_response :success
    assert_equal @other_branch.id, @reader.reload.branch_id
    assert_equal [ @other_department.id ], @reader.department_ids
    ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  end

  private

  def sql_count
    count = 0
    callback = ->(_name, _start, _finish, _id, payload) do
      count += 1 if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def create_user(login, role)
    User.create!(login: login, full_name: login, password: "a-long-test-password", role: role,
      branch: @branch, departments: [ @department ])
  end

  def auth(user)
    _, token = AuthSession.issue!(user)
    { "Authorization" => "Bearer #{token}" }
  end
end
