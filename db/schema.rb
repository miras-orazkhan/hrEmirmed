# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_17_103000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_events", force: :cascade do |t|
    t.bigint "actor_user_id"
    t.string "action", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.jsonb "changeset", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_user_id"], name: "index_audit_events_on_actor_user_id"
    t.index ["subject_type", "subject_id", "created_at"], name: "idx_on_subject_type_subject_id_created_at_314bc2a748"
    t.check_constraint "jsonb_typeof(changeset) = 'object'::text", name: "audit_events_changeset_object"
  end

  create_table "auth_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_auth_sessions_on_expires_at"
    t.index ["token_digest"], name: "index_auth_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_auth_sessions_on_user_id"
    t.check_constraint "token_digest::text ~ '^[0-9a-f]{64}$'::text", name: "auth_sessions_sha256_digest"
  end

  create_table "branches", force: :cascade do |t|
    t.string "name", null: false
    t.string "address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_branches_on_name", unique: true
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 200", name: "branches_name_length"
  end

  create_table "candidate_applications", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "job_requisition_id", null: false
    t.bigint "job_requisition_version_id", null: false
    t.bigint "created_by_id", null: false
    t.string "stage", default: "screening", null: false
    t.string "status", default: "active", null: false
    t.string "outcome"
    t.datetime "ended_at"
    t.bigint "decided_by_id"
    t.bigint "rejection_reason_id"
    t.text "decision_comment"
    t.boolean "allow_next_application"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "id"], name: "index_candidate_applications_on_candidate_id_and_id"
    t.index ["candidate_id"], name: "idx_one_active_application_per_candidate", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["created_by_id"], name: "index_candidate_applications_on_created_by_id"
    t.index ["decided_by_id"], name: "index_candidate_applications_on_decided_by_id"
    t.index ["job_requisition_id", "status", "id"], name: "idx_applications_requisition_status"
    t.index ["job_requisition_version_id"], name: "index_candidate_applications_on_job_requisition_version_id"
    t.index ["rejection_reason_id"], name: "index_candidate_applications_on_rejection_reason_id"
    t.check_constraint "(NOT outcome::text IS DISTINCT FROM 'rejected'::text) = (rejection_reason_id IS NOT NULL)", name: "candidate_rejection_reason_required"
    t.check_constraint "stage::text = ANY (ARRAY['screening'::character varying::text, 'test_review'::character varying::text, 'interview'::character varying::text, 'internship'::character varying::text, 'offer'::character varying::text])", name: "candidate_applications_stage"
    t.check_constraint "status::text = 'active'::text AND outcome IS NULL AND ended_at IS NULL AND decided_by_id IS NULL AND allow_next_application IS NULL OR status::text = 'completed'::text AND outcome IS NOT NULL AND (outcome::text = ANY (ARRAY['rejected'::character varying::text, 'withdrawn'::character varying::text, 'cancelled'::character varying::text])) AND ended_at IS NOT NULL AND decided_by_id IS NOT NULL AND allow_next_application IS NOT NULL", name: "candidate_applications_completion"
  end

  create_table "candidate_contacts", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.string "kind", null: false
    t.string "value", null: false
    t.string "normalized_value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "kind", "normalized_value"], name: "idx_candidate_contacts_identity", unique: true
    t.index ["kind", "normalized_value", "candidate_id"], name: "idx_candidate_contacts_matching"
    t.check_constraint "(kind::text = ANY (ARRAY['phone'::character varying::text, 'email'::character varying::text])) AND char_length(value::text) >= 1 AND char_length(value::text) <= 254 AND char_length(normalized_value::text) >= 1 AND char_length(normalized_value::text) <= 254", name: "candidate_contacts_format"
  end

  create_table "candidate_duplicates", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "other_candidate_id", null: false
    t.string "status", default: "pending", null: false
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.text "resolution_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "other_candidate_id"], name: "idx_candidate_duplicate_pair", unique: true
    t.index ["other_candidate_id"], name: "index_candidate_duplicates_on_other_candidate_id"
    t.index ["resolved_by_id"], name: "index_candidate_duplicates_on_resolved_by_id"
    t.index ["status", "id"], name: "index_candidate_duplicates_on_status_and_id"
    t.check_constraint "candidate_id < other_candidate_id", name: "candidate_duplicate_order"
    t.check_constraint "status::text = 'pending'::text AND resolved_by_id IS NULL AND resolved_at IS NULL OR (status::text = ANY (ARRAY['distinct'::character varying::text, 'confirmed'::character varying::text])) AND resolved_by_id IS NOT NULL AND resolved_at IS NOT NULL", name: "candidate_duplicate_resolution"
  end

  create_table "candidate_imports", force: :cascade do |t|
    t.bigint "created_by_id", null: false
    t.string "provider", default: "prototype", null: false
    t.integer "total_count", null: false
    t.integer "imported_count", null: false
    t.integer "skipped_count", null: false
    t.integer "rejected_count", null: false
    t.jsonb "row_results", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["created_by_id", "id"], name: "index_candidate_imports_on_created_by_id_and_id"
    t.check_constraint "jsonb_typeof(row_results) = 'array'::text AND jsonb_array_length(row_results) = total_count", name: "candidate_imports_results"
    t.check_constraint "provider::text = 'prototype'::text", name: "candidate_imports_provider"
    t.check_constraint "total_count >= 1 AND total_count <= 1000 AND imported_count >= 0 AND skipped_count >= 0 AND rejected_count >= 0 AND total_count = (imported_count + skipped_count + rejected_count)", name: "candidate_imports_counts"
  end

  create_table "candidate_resumes", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "uploaded_by_id", null: false
    t.string "sha256", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "id"], name: "index_candidate_resumes_on_candidate_id_and_id"
    t.index ["candidate_id", "sha256"], name: "index_candidate_resumes_on_candidate_id_and_sha256", unique: true
    t.index ["uploaded_by_id"], name: "index_candidate_resumes_on_uploaded_by_id"
    t.check_constraint "sha256::text ~ '^[0-9a-f]{64}$'::text", name: "candidate_resumes_sha256_format"
  end

  create_table "candidate_sources", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_candidate_sources_on_candidate_id"
    t.index ["provider", "external_id"], name: "index_candidate_sources_on_provider_and_external_id", unique: true
    t.check_constraint "char_length(btrim(provider::text)) >= 1 AND char_length(btrim(provider::text)) <= 50 AND char_length(btrim(external_id::text)) >= 1 AND char_length(btrim(external_id::text)) <= 200", name: "candidate_sources_identity"
  end

  create_table "candidates", force: :cascade do |t|
    t.string "full_name", null: false
    t.string "preferred_language", limit: 16
    t.string "city", limit: 200
    t.text "summary"
    t.bigint "responsible_recruiter_id", null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((full_name)::text) text_pattern_ops", name: "idx_candidates_name_prefix"
    t.index ["created_by_id"], name: "index_candidates_on_created_by_id"
    t.index ["responsible_recruiter_id", "id"], name: "index_candidates_on_responsible_recruiter_id_and_id"
    t.check_constraint "char_length(btrim(full_name::text)) >= 1 AND char_length(btrim(full_name::text)) <= 200", name: "candidates_full_name_length"
  end

  create_table "departments", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "id"], name: "index_departments_on_branch_id_and_id"
    t.index ["branch_id", "name"], name: "index_departments_on_branch_id_and_name", unique: true
    t.index ["id", "branch_id"], name: "index_departments_on_id_and_branch_id", unique: true
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 200", name: "departments_name_length"
  end

  create_table "job_requisition_versions", force: :cascade do |t|
    t.bigint "job_requisition_id", null: false
    t.integer "version_number", null: false
    t.text "work_schedule", null: false
    t.decimal "salary_amount", precision: 14, scale: 2, null: false
    t.string "salary_currency", limit: 3, null: false
    t.date "desired_start_on", null: false
    t.bigint "interviewer_id", null: false
    t.string "interview_format", null: false
    t.bigint "internship_supervisor_id"
    t.string "internship_duration"
    t.jsonb "additional_questions", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["id", "job_requisition_id"], name: "idx_requisition_versions_owner", unique: true
    t.index ["internship_supervisor_id"], name: "index_job_requisition_versions_on_internship_supervisor_id"
    t.index ["interviewer_id"], name: "index_job_requisition_versions_on_interviewer_id"
    t.index ["job_requisition_id", "version_number"], name: "idx_requisition_versions_number", unique: true
    t.check_constraint "interview_format::text = ANY (ARRAY['onsite'::character varying::text, 'online'::character varying::text])", name: "requisition_versions_interview_format"
    t.check_constraint "jsonb_typeof(additional_questions) = 'array'::text", name: "requisition_versions_questions_array"
    t.check_constraint "version_number > 0 AND char_length(btrim(work_schedule)) > 0 AND salary_amount >= 0::numeric AND salary_currency::text ~ '^[A-Z]{3}$'::text", name: "requisition_versions_conditions"
  end

  create_table "job_requisitions", force: :cascade do |t|
    t.bigint "department_id", null: false
    t.bigint "vacancy_template_id", null: false
    t.bigint "vacancy_template_version_id", null: false
    t.bigint "recruitment_campaign_id", null: false
    t.bigint "recruiter_id", null: false
    t.bigint "created_by_id", null: false
    t.string "status", default: "ready", null: false
    t.integer "positions_count", null: false
    t.integer "filled_positions_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_job_requisitions_on_created_by_id"
    t.index ["department_id", "id"], name: "index_job_requisitions_on_department_id_and_id"
    t.index ["recruiter_id", "id"], name: "index_job_requisitions_on_recruiter_id_and_id"
    t.index ["recruitment_campaign_id", "status", "id"], name: "idx_requisitions_campaign_status"
    t.index ["vacancy_template_id"], name: "index_job_requisitions_on_vacancy_template_id"
    t.index ["vacancy_template_version_id"], name: "index_job_requisitions_on_vacancy_template_version_id"
    t.check_constraint "positions_count > 0 AND filled_positions_count >= 0 AND filled_positions_count <= positions_count", name: "job_requisitions_positions"
    t.check_constraint "status::text <> 'closed'::text OR filled_positions_count = positions_count", name: "closed_requisition_has_filled_positions"
    t.check_constraint "status::text = ANY (ARRAY['ready'::character varying::text, 'recruiting'::character varying::text, 'paused'::character varying::text, 'closed'::character varying::text, 'cancelled'::character varying::text])", name: "job_requisitions_status"
  end

  create_table "legal_entities", force: :cascade do |t|
    t.string "name", null: false
    t.string "registration_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_legal_entities_on_name", unique: true
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 200", name: "legal_entities_name_length"
  end

  create_table "recruitment_campaigns", force: :cascade do |t|
    t.bigint "vacancy_template_id", null: false
    t.bigint "recruiter_id", null: false
    t.string "status", default: "pending_approval", null: false
    t.text "search_query"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_recruitment_campaigns_on_approved_by_id"
    t.index ["id", "recruiter_id"], name: "idx_campaigns_recruiter_owner", unique: true
    t.index ["id", "vacancy_template_id"], name: "idx_campaigns_template_owner", unique: true
    t.index ["recruiter_id", "id"], name: "index_recruitment_campaigns_on_recruiter_id_and_id"
    t.index ["vacancy_template_id"], name: "index_recruitment_campaigns_on_vacancy_template_id", unique: true
    t.check_constraint "status::text <> 'active'::text OR approved_by_id IS NOT NULL AND approved_at IS NOT NULL AND char_length(btrim(search_query)) > 0 AND search_query IS NOT NULL", name: "campaign_active_requires_approval"
    t.check_constraint "status::text = ANY (ARRAY['pending_approval'::character varying::text, 'active'::character varying::text, 'paused'::character varying::text])", name: "recruitment_campaigns_status"
  end

  create_table "rejection_reasons", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_rejection_reasons_on_name", unique: true
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 200", name: "rejection_reasons_name"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "permissions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 200", name: "roles_name_length"
    t.check_constraint "jsonb_typeof(permissions) = 'array'::text AND permissions <@ '[\"read.organization\", \"manage.organization\", \"manage.users\", \"manage.roles\", \"read.audit\", \"read.vacancy_template\", \"manage.vacancy_template\", \"approve.vacancy_template\", \"read.job_requisition\", \"create.job_requisition\", \"update.job_requisition\", \"manage.job_requisition\", \"read.recruitment_campaign\", \"launch.recruitment_campaign\", \"read.all_recruitment\", \"conduct.interview\", \"supervise.internship\", \"read.candidate\", \"read.all_candidates\", \"create.candidate\", \"update.candidate\", \"import.candidate\", \"manage.candidate_application\", \"resolve.candidate_duplicate\", \"manage.all_candidate_duplicates\", \"manage.rejection_reason\"]'::jsonb", name: "roles_supported_permissions"
  end

  create_table "user_departments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "department_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "branch_id", null: false
    t.index ["department_id"], name: "index_user_departments_on_department_id"
    t.index ["user_id", "department_id"], name: "index_user_departments_on_user_id_and_department_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.bigint "role_id", null: false
    t.string "login", null: false
    t.string "full_name", null: false
    t.string "password_digest", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "id"], name: "index_users_on_branch_id_and_id"
    t.index ["id", "branch_id"], name: "index_users_on_id_and_branch_id", unique: true
    t.index ["login"], name: "index_users_on_login", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
    t.check_constraint "char_length(btrim(full_name::text)) >= 1 AND char_length(btrim(full_name::text)) <= 200", name: "users_full_name_length"
    t.check_constraint "login::text = lower(btrim(login::text)) AND login::text ~ '^[a-z0-9_.@-]+$'::text AND char_length(login::text) <= 100", name: "users_normalized_login"
  end

  create_table "vacancy_template_versions", force: :cascade do |t|
    t.bigint "vacancy_template_id", null: false
    t.integer "version_number", null: false
    t.string "title", null: false
    t.text "duties", null: false
    t.jsonb "professional_skills", default: [], null: false
    t.jsonb "mandatory_requirements", default: [], null: false
    t.jsonb "preferred_requirements", default: [], null: false
    t.jsonb "screening_questions", default: [], null: false
    t.boolean "internship_required", default: false, null: false
    t.jsonb "internship_criteria", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["id", "vacancy_template_id"], name: "idx_template_versions_owner", unique: true
    t.index ["vacancy_template_id", "version_number"], name: "idx_template_versions_number", unique: true
    t.check_constraint "NOT internship_required OR jsonb_array_length(internship_criteria) > 0", name: "template_internship_criteria_required"
    t.check_constraint "jsonb_typeof(internship_criteria) = 'array'::text", name: "template_internship_criteria_array"
    t.check_constraint "jsonb_typeof(mandatory_requirements) = 'array'::text", name: "template_required_requirements_array"
    t.check_constraint "jsonb_typeof(preferred_requirements) = 'array'::text", name: "template_preferred_requirements_array"
    t.check_constraint "jsonb_typeof(professional_skills) = 'array'::text", name: "template_professional_skills_array"
    t.check_constraint "jsonb_typeof(screening_questions) = 'array'::text", name: "template_screening_questions_array"
    t.check_constraint "version_number > 0 AND char_length(btrim(title::text)) >= 1 AND char_length(btrim(title::text)) <= 200 AND char_length(btrim(duties)) > 0", name: "template_versions_required_fields"
  end

  create_table "vacancy_templates", force: :cascade do |t|
    t.bigint "recruiter_id", null: false
    t.bigint "created_by_id", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_vacancy_templates_on_created_by_id"
    t.index ["id", "recruiter_id"], name: "idx_templates_recruiter_owner", unique: true
    t.index ["recruiter_id"], name: "index_vacancy_templates_on_recruiter_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'approved'::character varying::text])", name: "vacancy_templates_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_events", "users", column: "actor_user_id"
  add_foreign_key "auth_sessions", "users"
  add_foreign_key "candidate_applications", "candidates"
  add_foreign_key "candidate_applications", "job_requisition_versions", column: ["job_requisition_version_id", "job_requisition_id"], primary_key: ["id", "job_requisition_id"], name: "fk_application_conditions_owner"
  add_foreign_key "candidate_applications", "job_requisitions"
  add_foreign_key "candidate_applications", "rejection_reasons"
  add_foreign_key "candidate_applications", "users", column: "created_by_id"
  add_foreign_key "candidate_applications", "users", column: "decided_by_id"
  add_foreign_key "candidate_contacts", "candidates"
  add_foreign_key "candidate_duplicates", "candidates"
  add_foreign_key "candidate_duplicates", "candidates", column: "other_candidate_id"
  add_foreign_key "candidate_duplicates", "users", column: "resolved_by_id"
  add_foreign_key "candidate_imports", "users", column: "created_by_id"
  add_foreign_key "candidate_resumes", "candidates"
  add_foreign_key "candidate_resumes", "users", column: "uploaded_by_id"
  add_foreign_key "candidate_sources", "candidates"
  add_foreign_key "candidates", "users", column: "created_by_id"
  add_foreign_key "candidates", "users", column: "responsible_recruiter_id"
  add_foreign_key "departments", "branches"
  add_foreign_key "job_requisition_versions", "job_requisitions"
  add_foreign_key "job_requisition_versions", "users", column: "internship_supervisor_id"
  add_foreign_key "job_requisition_versions", "users", column: "interviewer_id"
  add_foreign_key "job_requisitions", "departments"
  add_foreign_key "job_requisitions", "recruitment_campaigns", column: ["recruitment_campaign_id", "recruiter_id"], primary_key: ["id", "recruiter_id"], name: "fk_requisition_campaign_recruiter"
  add_foreign_key "job_requisitions", "recruitment_campaigns", column: ["recruitment_campaign_id", "vacancy_template_id"], primary_key: ["id", "vacancy_template_id"], name: "fk_requisition_campaign_template"
  add_foreign_key "job_requisitions", "users", column: "created_by_id"
  add_foreign_key "job_requisitions", "users", column: "recruiter_id"
  add_foreign_key "job_requisitions", "vacancy_template_versions", column: ["vacancy_template_version_id", "vacancy_template_id"], primary_key: ["id", "vacancy_template_id"], name: "fk_requisition_template_version"
  add_foreign_key "job_requisitions", "vacancy_templates"
  add_foreign_key "recruitment_campaigns", "users", column: "approved_by_id"
  add_foreign_key "recruitment_campaigns", "users", column: "recruiter_id"
  add_foreign_key "recruitment_campaigns", "vacancy_templates"
  add_foreign_key "recruitment_campaigns", "vacancy_templates", column: ["vacancy_template_id", "recruiter_id"], primary_key: ["id", "recruiter_id"], name: "fk_campaign_template_recruiter"
  add_foreign_key "user_departments", "departments", column: ["department_id", "branch_id"], primary_key: ["id", "branch_id"], name: "fk_user_departments_department_branch", deferrable: :deferred
  add_foreign_key "user_departments", "users", column: ["user_id", "branch_id"], primary_key: ["id", "branch_id"], name: "fk_user_departments_user_branch", deferrable: :deferred
  add_foreign_key "users", "branches"
  add_foreign_key "users", "roles"
  add_foreign_key "vacancy_template_versions", "vacancy_templates"
  add_foreign_key "vacancy_templates", "users", column: "created_by_id"
  add_foreign_key "vacancy_templates", "users", column: "recruiter_id"
end
