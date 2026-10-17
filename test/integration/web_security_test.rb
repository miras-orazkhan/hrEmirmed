require "test_helper"

class WebSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @previous_csrf_setting = Web::BaseController.allow_forgery_protection
    Web::BaseController.allow_forgery_protection = true
    branch = Branch.create!(name: "Security branch")
    department = branch.departments.create!(name: "Security department")
    role = Role.create!(name: "web_security", permissions: %w[create.candidate read.candidate read.all_candidates])
    @user = User.create!(login: "web_security", full_name: "Web security", role: role,
      branch: branch, departments: [ department ], password: "long-test-password")
  end

  teardown do
    Web::BaseController.allow_forgery_protection = @previous_csrf_setting
  end

  test "web form rejects a post without CSRF token while API bearer authentication still works" do
    post "/session", params: { session: { login: @user.login, password: "long-test-password" } }
    assert_response :unprocessable_entity
    assert_equal 0, AuthSession.count

    _, token = AuthSession.issue!(@user)
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_equal @user.id, response.parsed_body["id"]
  end
end
