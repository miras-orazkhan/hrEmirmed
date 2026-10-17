require "test_helper"

class DatabaseIntegrityTest < ActiveSupport::TestCase
  setup do
    @branch = Branch.create!(name: "Branch")
    @department = @branch.departments.create!(name: "HR")
    @role = Role.create!(name: "reader", permissions: [ "read.organization" ])
    @user = User.create!(login: "reader", full_name: "Reader", password: "long-test-password",
      branch: @branch, departments: [ @department ], role: @role)
  end

  test "database rejects non-normalized login bypassing model validations" do
    assert_database_rejects(ActiveRecord::StatementInvalid) do
      ApplicationRecord.connection.execute("UPDATE users SET login = ' READER ' WHERE id = #{@user.id.to_i}")
    end
  end

  test "database enforces login uniqueness for concurrent writers" do
    attributes = @user.attributes.except("id", "created_at", "updated_at")
    assert_database_rejects(ActiveRecord::RecordNotUnique) { User.insert_all!([ attributes ]) }
  end

  test "database rejects cross branch membership bypassing validation" do
    other = Branch.create!(name: "Other").departments.create!(name: "Other HR")
    assert_database_rejects(ActiveRecord::InvalidForeignKey) do
      UserDepartment.insert_all!([ { user_id: @user.id, department_id: other.id, branch_id: @branch.id } ])
    end
  end

  test "database prevents moving a user while retaining old branch membership" do
    other = Branch.create!(name: "Other")
    assert_database_rejects(ActiveRecord::InvalidForeignKey) { @user.update_columns(branch_id: other.id) }
  end

  test "database rejects unsupported permissions and malformed session digests" do
    assert_database_rejects(ActiveRecord::StatementInvalid) { @role.update_columns(permissions: [ "unknown" ]) }
    assert_database_rejects(ActiveRecord::StatementInvalid) do
      AuthSession.insert_all!([ { user_id: @user.id, token_digest: "plaintext", expires_at: 1.hour.from_now } ])
    end
  end

  test "audit only retains explicitly allowed fields" do
    event = AuditEvent.record!(actor: @user, action: "user.saved", subject: @user,
      changeset: { "full_name" => [ "Before", "After" ], "password_digest" => "secret", "future_secret" => "secret" })
    assert_equal({ "full_name" => [ "Before", "After" ] }, event.changeset)
  end

  test "session pruning removes expired records and retains active sessions" do
    expired, = AuthSession.issue!(@user)
    expired.update!(expires_at: 1.minute.ago)
    active, = AuthSession.issue!(@user)
    PruneAuthSessionsJob.perform_now
    assert_not AuthSession.exists?(expired.id)
    assert AuthSession.exists?(active.id)
  end

  private

  def assert_database_rejects(error)
    assert_raises(error) do
      ApplicationRecord.transaction(requires_new: true) do
        yield
        ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    end
  end
end
