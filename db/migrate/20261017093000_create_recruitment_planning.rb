class CreateRecruitmentPlanning < ActiveRecord::Migration[8.1]
  PERMISSIONS = %w[read.organization manage.organization manage.users manage.roles read.audit
    read.vacancy_template manage.vacancy_template approve.vacancy_template
    read.job_requisition create.job_requisition update.job_requisition manage.job_requisition
    read.recruitment_campaign launch.recruitment_campaign read.all_recruitment
    conduct.interview supervise.internship].freeze

  def change
    remove_check_constraint :roles, name: "roles_supported_permissions",
      expression: "jsonb_typeof(permissions) = 'array' AND permissions <@ '[\"read.organization\",\"manage.organization\",\"manage.users\",\"manage.roles\",\"read.audit\"]'::jsonb"
    add_check_constraint :roles, "jsonb_typeof(permissions) = 'array' AND permissions <@ '#{PERMISSIONS.to_json}'::jsonb",
      name: "roles_supported_permissions"

    create_table :vacancy_templates do |t|
      t.references :recruiter, null: false, foreign_key: { to_table: :users }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_check_constraint :vacancy_templates, "status IN ('draft', 'approved')", name: "vacancy_templates_status"

    create_table :vacancy_template_versions do |t|
      t.references :vacancy_template, null: false, foreign_key: true, index: false
      t.integer :version_number, null: false
      t.string :title, null: false
      t.text :duties, null: false
      t.jsonb :professional_skills, null: false, default: []
      t.jsonb :required_requirements, null: false, default: []
      t.jsonb :preferred_requirements, null: false, default: []
      t.jsonb :screening_questions, null: false, default: []
      t.boolean :internship_required, null: false, default: false
      t.jsonb :internship_criteria, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :vacancy_template_versions, [ :vacancy_template_id, :version_number ], unique: true, name: "idx_template_versions_number"
    add_index :vacancy_template_versions, [ :id, :vacancy_template_id ], unique: true, name: "idx_template_versions_owner"
    add_check_constraint :vacancy_template_versions, "version_number > 0 AND char_length(btrim(title)) BETWEEN 1 AND 200 AND char_length(btrim(duties)) > 0", name: "template_versions_required_fields"
    %i[professional_skills required_requirements preferred_requirements screening_questions internship_criteria].each do |column|
      add_check_constraint :vacancy_template_versions, "jsonb_typeof(#{column}) = 'array'", name: "template_#{column}_array"
    end
    add_check_constraint :vacancy_template_versions, "NOT internship_required OR jsonb_array_length(internship_criteria) > 0", name: "template_internship_criteria_required"

    create_table :recruitment_campaigns do |t|
      t.references :vacancy_template, null: false, foreign_key: true, index: { unique: true }
      t.references :recruiter, null: false, foreign_key: { to_table: :users }, index: false
      t.string :status, null: false, default: "pending_approval"
      t.text :search_query
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.timestamps
    end
    add_index :recruitment_campaigns, [ :recruiter_id, :id ]
    add_index :recruitment_campaigns, [ :id, :vacancy_template_id ], unique: true, name: "idx_campaigns_template_owner"
    add_check_constraint :recruitment_campaigns, "status IN ('pending_approval', 'active', 'paused')", name: "recruitment_campaigns_status"
    add_check_constraint :recruitment_campaigns, "status <> 'active' OR (approved_by_id IS NOT NULL AND approved_at IS NOT NULL AND char_length(btrim(search_query)) > 0 AND search_query IS NOT NULL)", name: "campaign_active_requires_approval"

    create_table :job_requisitions do |t|
      t.references :department, null: false, foreign_key: true, index: false
      t.references :vacancy_template, null: false, foreign_key: true
      t.references :vacancy_template_version, null: false, index: true
      t.references :recruitment_campaign, null: false, index: false
      t.references :recruiter, null: false, foreign_key: { to_table: :users }, index: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "ready"
      t.integer :positions_count, null: false
      t.integer :filled_positions_count, null: false, default: 0
      t.timestamps
    end
    add_index :job_requisitions, [ :department_id, :id ]
    add_index :job_requisitions, [ :recruiter_id, :id ]
    add_index :job_requisitions, [ :recruitment_campaign_id, :status, :id ], name: "idx_requisitions_campaign_status"
    add_foreign_key :job_requisitions, :vacancy_template_versions,
      column: [ :vacancy_template_version_id, :vacancy_template_id ], primary_key: [ :id, :vacancy_template_id ], name: "fk_requisition_template_version"
    add_foreign_key :job_requisitions, :recruitment_campaigns,
      column: [ :recruitment_campaign_id, :vacancy_template_id ], primary_key: [ :id, :vacancy_template_id ], name: "fk_requisition_campaign_template"
    add_check_constraint :job_requisitions, "status IN ('ready', 'recruiting', 'paused', 'closed', 'cancelled')", name: "job_requisitions_status"
    add_check_constraint :job_requisitions, "positions_count > 0 AND filled_positions_count BETWEEN 0 AND positions_count", name: "job_requisitions_positions"

    create_table :job_requisition_versions do |t|
      t.references :job_requisition, null: false, foreign_key: true, index: false
      t.integer :version_number, null: false
      t.text :work_schedule, null: false
      t.decimal :salary_amount, precision: 14, scale: 2, null: false
      t.string :salary_currency, null: false, limit: 3
      t.date :desired_start_on, null: false
      t.references :interviewer, null: false, foreign_key: { to_table: :users }
      t.string :interview_format, null: false
      t.references :internship_supervisor, foreign_key: { to_table: :users }
      t.string :internship_duration
      t.jsonb :additional_questions, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :job_requisition_versions, [ :job_requisition_id, :version_number ], unique: true, name: "idx_requisition_versions_number"
    add_check_constraint :job_requisition_versions, "version_number > 0 AND char_length(btrim(work_schedule)) > 0 AND salary_amount >= 0 AND salary_currency ~ '^[A-Z]{3}$'", name: "requisition_versions_conditions"
    add_check_constraint :job_requisition_versions, "interview_format IN ('onsite', 'online')", name: "requisition_versions_interview_format"
    add_check_constraint :job_requisition_versions, "jsonb_typeof(additional_questions) = 'array'", name: "requisition_versions_questions_array"
  end
end
