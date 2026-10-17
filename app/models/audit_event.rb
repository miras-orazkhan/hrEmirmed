class AuditEvent < ApplicationRecord
  SAFE_FIELDS = {
    "User" => %w[login full_name active branch_id role_id department_ids],
    "Branch" => %w[name address],
    "Department" => %w[name branch_id],
    "LegalEntity" => %w[name registration_number],
    "Role" => %w[name permissions],
    "AuthSession" => [],
    "VacancyTemplate" => %w[recruiter_id status version_number],
    "RecruitmentCampaign" => %w[status recruiter_id vacancy_template_id search_query approved_by_id approved_at],
    "JobRequisition" => %w[department_id vacancy_template_id vacancy_template_version_id recruitment_campaign_id
      recruiter_id status positions_count filled_positions_count version_number],
    "Candidate" => %w[responsible_recruiter_id],
    "CandidateApplication" => %w[candidate_id job_requisition_id job_requisition_version_id created_by_id stage status
      outcome ended_at decided_by_id rejection_reason_id allow_next_application],
    "CandidateDuplicate" => %w[status resolved_by_id resolved_at],
    "CandidateResume" => %w[candidate_id uploaded_by_id],
    "CandidateImport" => %w[created_by_id provider total_count imported_count skipped_count rejected_count],
    "RejectionReason" => %w[name active]
  }.freeze

  belongs_to :actor, class_name: "User", foreign_key: :actor_user_id, optional: true
  validates :action, :subject_type, :subject_id, presence: true

  def self.record!(actor:, action:, subject:, changeset: {})
    create!(actor: actor, action: action, subject_type: subject.class.name, subject_id: subject.id,
      changeset: changeset.stringify_keys.slice(*SAFE_FIELDS.fetch(subject.class.name, [])))
  end
end
