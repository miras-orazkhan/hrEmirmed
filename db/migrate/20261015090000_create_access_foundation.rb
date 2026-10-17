class CreateAccessFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :branches do |t|
      t.string :name, null: false
      t.string :address
      t.timestamps
    end
    add_index :branches, :name, unique: true

    create_table :departments do |t|
      t.references :branch, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :departments, [ :branch_id, :name ], unique: true

    create_table :legal_entities do |t|
      t.string :name, null: false
      t.string :registration_number
      t.timestamps
    end
    add_index :legal_entities, :name, unique: true

    create_table :roles do |t|
      t.string :name, null: false
      t.jsonb :permissions, null: false, default: []
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :users do |t|
      t.references :branch, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.string :login, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :users, :login, unique: true

    create_table :department_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :department, null: false, foreign_key: true
      t.timestamps
    end
    add_index :department_memberships, [ :user_id, :department_id ], unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true
    add_index :sessions, :expires_at

    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.jsonb :changeset, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_events, [ :subject_type, :subject_id, :created_at ]
  end
end
