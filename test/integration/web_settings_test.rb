require "test_helper"

class WebSettingsTest < ActionDispatch::IntegrationTest
  setup do
    Web::SessionsController::LOGIN_LIMIT_STORE.clear
    @branch = Branch.create!(name: "Алматы")
    @department = @branch.departments.create!(name: "Клиника")
    @other_branch = Branch.create!(name: "Астана")
    @other_department = @other_branch.departments.create!(name: "Офис")
    @admin_role = Role.create!(name: "admin")
    @reader_role = Role.create!(name: "reader", permissions: %w[read.organization])
    @admin = create_user("settings_admin", @admin_role, @branch, @department)
    @users_manager = create_user("users_manager", Role.create!(name: "users_manager", permissions: %w[manage.users]), @branch, @department)
    @roles_manager = create_user("roles_manager", Role.create!(name: "roles_manager", permissions: %w[manage.roles]), @branch, @department)
    @organization_manager = create_user("organization_manager", Role.create!(name: "organization_manager", permissions: %w[read.organization manage.organization]), @branch, @department)
    @organization_reader = create_user("organization_reader", @reader_role, @branch, @department)
    @reason_manager = create_user("reason_manager", Role.create!(name: "reason_manager", permissions: %w[read.candidate manage.rejection_reason]), @branch, @department)
    @reason_reader = create_user("reason_reader", Role.create!(name: "reason_reader", permissions: %w[read.candidate]), @branch, @department)
  end

  test "users HTML flow creates edits and rejects invalid cross branch assignments atomically" do
    login(@admin)
    assert_difference [ "User.count", "AuditEvent.count" ], 1 do
      post "/users", params: { user: { login: "new.staff", full_name: "Новый сотрудник", password: "a-long-test-password",
        branch_id: @branch.id, department_ids: [ @department.id ], role_id: @reader_role.id } }
    end
    assert_response :see_other
    user = User.find_by!(login: "new.staff")
    assert_not_includes response.body, "a-long-test-password"
    assert_not_includes AuditEvent.last.to_json, "a-long-test-password"
    assert_not_includes AuditEvent.last.changeset.keys, "password_digest"

    patch "/users/#{user.id}", params: { user: { full_name: "Обновлённое имя", password: "", active: "1" } }
    assert_response :see_other
    assert_equal "Обновлённое имя", user.reload.full_name
    assert_equal user.password_digest, user.reload.password_digest

    original_departments = user.department_ids
    original_name = user.full_name
    assert_no_difference "AuditEvent.count" do
      patch "/users/#{user.id}", params: { user: { full_name: "Не сохранить", branch_id: @branch.id,
        department_ids: [ @other_department.id ] } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Не сохранить"
    assert_equal original_name, user.reload.full_name
    assert_equal original_departments, user.department_ids
  end

  test "non admin user manager cannot grant admin or modify admin accounts" do
    login(@users_manager)
    assert_no_difference "User.count" do
      post "/users", params: { user: { login: "fake.admin", full_name: "Fake Admin", password: "a-long-test-password",
        branch_id: @branch.id, department_ids: [ @department.id ], role_id: @admin_role.id } }
    end
    assert_response :forbidden
    patch "/users/#{@admin.id}", params: { user: { active: "0" } }
    assert_response :forbidden
    assert @admin.reload.active?
  end

  test "disabling a user revokes existing web sessions" do
    login(@admin)
    session, = AuthSession.issue!(@organization_reader)
    patch "/users/#{@organization_reader.id}", params: { user: { active: "0" } }
    assert_response :see_other
    assert_not AuthSession.exists?(session.id)
  end

  test "roles HTML flow creates updates validates permission whitelist and protects built in admin" do
    login(@admin)
    assert_difference [ "Role.count", "AuditEvent.count" ], 1 do
      post "/roles", params: { role: { name: "Recruiter", permissions: %w[read.candidate create.candidate] } }
    end
    assert_response :see_other
    role = Role.find_by!(name: "Recruiter")
    patch "/roles/#{role.id}", params: { role: { name: "Senior Recruiter", permissions: %w[read.candidate update.candidate] } }
    assert_response :see_other
    assert_equal %w[read.candidate update.candidate], role.reload.permissions

    assert_no_difference "Role.count" do
      post "/roles", params: { role: { name: "Invalid", permissions: [ "root.everything" ] } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Invalid"
    patch "/roles/#{@admin_role.id}", params: { role: { name: "renamed" } }
    assert_response :unprocessable_entity
    assert_equal "admin", @admin_role.reload.name

    login(@roles_manager)
    patch "/roles/#{@admin_role.id}", params: { role: { name: "renamed" } }
    assert_response :forbidden
    assert_equal "admin", @admin_role.reload.name
  end

  test "settings home fallback recognizes a custom settings manager without candidate access" do
    login(@users_manager)
    get "/"
    assert_response :redirect
    assert_equal "/users", response.headers["Location"].delete_prefix("http://www.example.com")
  end

  test "organization settings HTML flow creates updates and validates branch department relationship" do
    login(@admin)
    assert_difference [ "Branch.count", "AuditEvent.count" ], 1 do
      post "/branches", params: { branch: { name: "Караганда", address: "Центр" } }
    end
    assert_response :see_other
    branch = Branch.find_by!(name: "Караганда")
    patch "/branches/#{branch.id}", params: { branch: { name: "Караганда 2", address: "Новый адрес" } }
    assert_response :see_other
    assert_equal "Новый адрес", branch.reload.address

    assert_difference "Department.count", 1 do
      post "/departments", params: { department: { name: "Диагностика", branch_id: @branch.id } }
    end
    assert_response :see_other
    department = Department.find_by!(name: "Диагностика")
    patch "/departments/#{department.id}", params: { department: { name: "Диагностика 2", branch_id: @branch.id } }
    assert_response :see_other
    assert_equal "Диагностика 2", department.reload.name
    assert_no_difference "AuditEvent.count" do
      post "/departments", params: { department: { name: "Ошибочное отделение", branch_id: "" } }
    end
    # A department form must reject a missing branch and retain its submitted name.
    assert_response :unprocessable_entity
    assert_includes response.body, "Ошибочное отделение"

    assert_difference "LegalEntity.count", 1 do
      post "/legal_entities", params: { legal_entity: { name: "ЭМИРМЕД", registration_number: "12345" } }
    end
    assert_response :see_other
    entity = LegalEntity.find_by!(name: "ЭМИРМЕД")
    patch "/legal_entities/#{entity.id}", params: { legal_entity: { name: "ЭМИРМЕД KZ", registration_number: "67890" } }
    assert_response :see_other
    assert_equal "67890", entity.reload.registration_number
  end

  test "organization reader can list scoped settings but cannot mutate" do
    login(@organization_reader)
    get "/branches"
    assert_response :success
    assert_includes response.body, @branch.name
    assert_not_includes response.body, @other_branch.name
    get "/departments"
    assert_response :success
    assert_includes response.body, @department.name
    assert_not_includes response.body, @other_department.name
    get "/legal_entities"
    assert_response :success
    post "/branches", params: { branch: { name: "Запрещено" } }
    assert_response :forbidden
  end

  test "rejection reason HTML flow creates edits and rejects invalid values" do
    login(@admin)
    assert_difference [ "RejectionReason.count", "AuditEvent.count" ], 1 do
      post "/rejection_reasons", params: { rejection_reason: { name: "Недостаточный опыт", active: "1" } }
    end
    assert_response :see_other
    reason = RejectionReason.find_by!(name: "Недостаточный опыт")
    patch "/rejection_reasons/#{reason.id}", params: { rejection_reason: { name: "Не хватает опыта", active: "0" } }
    assert_response :see_other
    assert_equal [ "Не хватает опыта", false ], [ reason.reload.name, reason.active ]
    assert_no_difference "RejectionReason.count" do
      post "/rejection_reasons", params: { rejection_reason: { name: "", active: "1" } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='rejection_reason[name]'][value='']"
  end

  test "rejection reason reader can list but cannot create or update reasons" do
    reason = RejectionReason.create!(name: "Причина")
    login(@reason_reader)
    get "/rejection_reasons"
    assert_response :success
    assert_includes response.body, reason.name
    post "/rejection_reasons", params: { rejection_reason: { name: "Новая причина" } }
    assert_response :forbidden
    patch "/rejection_reasons/#{reason.id}", params: { rejection_reason: { name: "Изменено" } }
    assert_response :forbidden
    assert_equal "Причина", reason.reload.name
  end

  test "settings indexes use workflow_list frames search and bounded pagination" do
    55.times { |index| LegalEntity.create!(name: format("Организация %02d", index)) }
    login(@admin)
    get "/legal_entities", params: { q: "Организация" }
    assert_response :success
    assert_select "turbo-frame#workflow_list"
    assert_includes response.body, "Организация 00"
    assert_not_includes response.body, "Организация 44"
    next_link = css_select("a[rel='next']").first
    assert next_link, "large settings lists should paginate"
    query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
    assert_equal "Организация", query["q"]
    get "/legal_entities", params: query, headers: { "Turbo-Frame" => "workflow_list" }
    assert_response :success
    assert_select "turbo-frame#workflow_list"
    assert_includes response.body, "Организация 44"
  end

  private

  def create_user(login, role, branch, department)
    User.create!(login: login, full_name: login, password: "long-test-password", role: role,
      branch: branch, departments: [ department ])
  end

  def login(user)
    post "/session", params: { session: { login: user.login, password: "long-test-password" } }
    assert_response :see_other
  end
end
