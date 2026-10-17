class CreateCandidateRegistry < ActiveRecord::Migration[8.1]
  OLD_PERMISSIONS = %w[read.organization manage.organization manage.users manage.roles read.audit
    read.vacancy_template manage.vacancy_template approve.vacancy_template
    read.job_requisition create.job_requisition update.job_requisition manage.job_requisition
    read.recruitment_campaign launch.recruitment_campaign read.all_recruitment
    conduct.interview supervise.internship].freeze
  NEW_PERMISSIONS = (OLD_PERMISSIONS + %w[read.candidate read.all_candidates create.candidate update.candidate
    import.candidate manage.candidate_application resolve.candidate_duplicate manage.all_candidate_duplicates
    manage.rejection_reason]).freeze

  def change
    remove_check_constraint :roles, name: "roles_supported_permissions",
      expression: "jsonb_typeof(permissions) = 'array' AND permissions <@ '#{OLD_PERMISSIONS.to_json}'::jsonb"
    add_check_constraint :roles, "jsonb_typeof(permissions) = 'array' AND permissions <@ '#{NEW_PERMISSIONS.to_json}'::jsonb",
      name: "roles_supported_permissions"

    create_table :candidates do |t|
      t.string :full_name, null: false
      t.string :preferred_language, limit: 16
      t.string :city, limit: 200
      t.text :summary
      t.references :responsible_recruiter, null: false, foreign_key: { to_table: :users }, index: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :candidates, [ :responsible_recruiter_id, :id ]
    add_index :candidates, "lower(full_name) text_pattern_ops", name: "idx_candidates_name_prefix"
    add_check_constraint :candidates, "char_length(btrim(full_name)) BETWEEN 1 AND 200", name: "candidates_full_name_length"

    create_table :candidate_contacts do |t|
      t.references :candidate, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.string :value, null: false
      t.string :normalized_value, null: false
      t.timestamps
    end
    add_index :candidate_contacts, [ :candidate_id, :kind, :normalized_value ], unique: true, name: "idx_candidate_contacts_identity"
    add_index :candidate_contacts, [ :kind, :normalized_value, :candidate_id ], name: "idx_candidate_contacts_matching"
    add_check_constraint :candidate_contacts, "kind IN ('phone','email') AND char_length(value) BETWEEN 1 AND 254 AND char_length(normalized_value) BETWEEN 1 AND 254", name: "candidate_contacts_format"

    create_table :candidate_sources do |t|
      t.references :candidate, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :external_id, null: false
      t.timestamps
    end
    add_index :candidate_sources, [ :provider, :external_id ], unique: true
    add_check_constraint :candidate_sources, "char_length(btrim(provider)) BETWEEN 1 AND 50 AND char_length(btrim(external_id)) BETWEEN 1 AND 200", name: "candidate_sources_identity"

    create_table :rejection_reasons do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :rejection_reasons, :name, unique: true
    add_check_constraint :rejection_reasons, "char_length(btrim(name)) BETWEEN 1 AND 200", name: "rejection_reasons_name"

    add_index :job_requisition_versions, [ :id, :job_requisition_id ], unique: true, name: "idx_requisition_versions_owner"
    create_table :candidate_applications do |t|
      t.references :candidate, null: false, foreign_key: true, index: false
      t.references :job_requisition, null: false, foreign_key: true, index: false
      t.references :job_requisition_version, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :stage, null: false, default: "screening"
      t.string :status, null: false, default: "active"
      t.string :outcome
      t.datetime :ended_at
      t.references :decided_by, foreign_key: { to_table: :users }
      t.references :rejection_reason, foreign_key: true
      t.text :decision_comment
      t.boolean :allow_next_application
      t.timestamps
    end
    add_index :candidate_applications, [ :candidate_id, :id ]
    add_index :candidate_applications, :candidate_id, unique: true, where: "status = 'active'", name: "idx_one_active_application_per_candidate"
    add_index :candidate_applications, [ :job_requisition_id, :status, :id ], name: "idx_applications_requisition_status"
    add_foreign_key :candidate_applications, :job_requisition_versions,
      column: [ :job_requisition_version_id, :job_requisition_id ], primary_key: [ :id, :job_requisition_id ], name: "fk_application_conditions_owner"
    add_check_constraint :candidate_applications, "stage IN ('screening','test_review','interview','internship','offer')", name: "candidate_applications_stage"
    add_check_constraint :candidate_applications,
      "(status = 'active' AND outcome IS NULL AND ended_at IS NULL AND decided_by_id IS NULL AND allow_next_application IS NULL) OR " \
      "(status = 'completed' AND outcome IS NOT NULL AND outcome IN ('rejected','withdrawn','cancelled') AND ended_at IS NOT NULL AND decided_by_id IS NOT NULL AND allow_next_application IS NOT NULL)", name: "candidate_applications_completion"
    add_check_constraint :candidate_applications,
      "(outcome = 'rejected' AND rejection_reason_id IS NOT NULL) OR " \
      "(outcome IS DISTINCT FROM 'rejected' AND rejection_reason_id IS NULL)", name: "candidate_rejection_reason_required"

    create_table :candidate_duplicates do |t|
      t.references :candidate, null: false, foreign_key: true, index: false
      t.references :other_candidate, null: false, foreign_key: { to_table: :candidates }
      t.string :status, null: false, default: "pending"
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end
    add_index :candidate_duplicates, [ :candidate_id, :other_candidate_id ], unique: true, name: "idx_candidate_duplicate_pair"
    add_index :candidate_duplicates, [ :status, :id ]
    add_check_constraint :candidate_duplicates, "candidate_id < other_candidate_id", name: "candidate_duplicate_order"
    add_check_constraint :candidate_duplicates,
      "(status = 'pending' AND resolved_by_id IS NULL AND resolved_at IS NULL) OR " \
      "(status IN ('distinct','confirmed') AND resolved_by_id IS NOT NULL AND resolved_at IS NOT NULL)", name: "candidate_duplicate_resolution"
  end
end
