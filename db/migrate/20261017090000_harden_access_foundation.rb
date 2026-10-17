class HardenAccessFoundation < ActiveRecord::Migration[8.1]
  def up
    rename_table :sessions, :auth_sessions
    rename_table :department_memberships, :user_departments
    rename_column :users, :name, :full_name
    rename_column :audit_events, :actor_id, :actor_user_id

    # Deliberate duplication: composite foreign keys enforce branch membership
    # even for imports and writes that bypass Active Record validations.
    add_column :user_departments, :branch_id, :bigint
    execute <<~SQL
      UPDATE user_departments SET branch_id = users.branch_id
      FROM users WHERE users.id = user_departments.user_id
    SQL
    change_column_null :user_departments, :branch_id, false
    add_index :users, [ :id, :branch_id ], unique: true
    add_index :departments, [ :id, :branch_id ], unique: true
    add_foreign_key :user_departments, :users, column: [ :user_id, :branch_id ],
      primary_key: [ :id, :branch_id ], deferrable: :deferred, name: "fk_user_departments_user_branch"
    add_foreign_key :user_departments, :departments, column: [ :department_id, :branch_id ],
      primary_key: [ :id, :branch_id ], deferrable: :deferred, name: "fk_user_departments_department_branch"
    remove_foreign_key :user_departments, :users, column: :user_id
    remove_foreign_key :user_departments, :departments, column: :department_id

    # The leading columns of these composite indexes cover the old single indexes.
    remove_index :user_departments, :user_id
    remove_index :departments, :branch_id
    remove_index :users, :branch_id
    add_index :users, [ :branch_id, :id ]
    add_index :departments, [ :branch_id, :id ]

    add_check_constraint :users,
      "login = lower(btrim(login)) AND login ~ '^[a-z0-9_.@-]+$' AND char_length(login) <= 100",
      name: "users_normalized_login"
    add_check_constraint :users, "char_length(btrim(full_name)) BETWEEN 1 AND 200", name: "users_full_name_length"
    add_check_constraint :auth_sessions, "token_digest ~ '^[0-9a-f]{64}$'", name: "auth_sessions_sha256_digest"
    add_check_constraint :roles,
      "jsonb_typeof(permissions) = 'array' AND permissions <@ '[\"read.organization\",\"manage.organization\",\"manage.users\",\"manage.roles\",\"read.audit\"]'::jsonb",
      name: "roles_supported_permissions"
    %i[branches departments legal_entities roles].each do |table|
      add_check_constraint table, "char_length(btrim(name)) BETWEEN 1 AND 200", name: "#{table}_name_length"
    end
    add_check_constraint :audit_events, "jsonb_typeof(changeset) = 'object'", name: "audit_events_changeset_object"
  end

  def down
    remove_check_constraint :audit_events, name: "audit_events_changeset_object"
    %i[branches departments legal_entities roles].each do |table|
      remove_check_constraint table, name: "#{table}_name_length"
    end
    remove_check_constraint :roles, name: "roles_supported_permissions"
    remove_check_constraint :auth_sessions, name: "auth_sessions_sha256_digest"
    remove_check_constraint :users, name: "users_full_name_length"
    remove_check_constraint :users, name: "users_normalized_login"
    remove_index :users, [ :branch_id, :id ]
    remove_index :departments, [ :branch_id, :id ]
    add_index :users, :branch_id
    add_index :departments, :branch_id
    add_index :user_departments, :user_id
    add_foreign_key :user_departments, :users
    add_foreign_key :user_departments, :departments
    remove_foreign_key :user_departments, name: "fk_user_departments_user_branch"
    remove_foreign_key :user_departments, name: "fk_user_departments_department_branch"
    remove_index :users, [ :id, :branch_id ]
    remove_index :departments, [ :id, :branch_id ]
    remove_column :user_departments, :branch_id
    rename_column :audit_events, :actor_user_id, :actor_id
    rename_column :users, :full_name, :name
    rename_table :user_departments, :department_memberships
    rename_table :auth_sessions, :sessions
  end
end
