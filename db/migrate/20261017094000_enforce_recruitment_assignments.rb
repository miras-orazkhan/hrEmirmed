class EnforceRecruitmentAssignments < ActiveRecord::Migration[8.1]
  def change
    rename_column :vacancy_template_versions, :required_requirements, :mandatory_requirements
    add_index :vacancy_templates, [ :id, :recruiter_id ], unique: true, name: "idx_templates_recruiter_owner"
    add_index :recruitment_campaigns, [ :id, :recruiter_id ], unique: true, name: "idx_campaigns_recruiter_owner"
    add_foreign_key :recruitment_campaigns, :vacancy_templates,
      column: [ :vacancy_template_id, :recruiter_id ], primary_key: [ :id, :recruiter_id ], name: "fk_campaign_template_recruiter"
    add_foreign_key :job_requisitions, :recruitment_campaigns,
      column: [ :recruitment_campaign_id, :recruiter_id ], primary_key: [ :id, :recruiter_id ], name: "fk_requisition_campaign_recruiter"
    add_check_constraint :job_requisitions, "status <> 'closed' OR filled_positions_count = positions_count", name: "closed_requisition_has_filled_positions"
  end
end
