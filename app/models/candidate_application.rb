class CandidateApplication < ApplicationRecord
  STAGES = %w[screening test_review interview internship offer].freeze
  OUTCOMES = %w[rejected withdrawn cancelled].freeze

  belongs_to :candidate
  belongs_to :job_requisition
  belongs_to :job_requisition_version
  belongs_to :created_by, class_name: "User"
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :rejection_reason, optional: true

  validates :stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: %w[active completed] }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :decision_comment, length: { maximum: 10_000 }
  validate :consistent_completion

  private

  def consistent_completion
    if status == "active"
      errors.add(:status, "cannot have a decision while active") if outcome || ended_at || decided_by_id || rejection_reason_id || !allow_next_application.nil?
    else
      errors.add(:outcome, "is required") if outcome.blank?
      errors.add(:ended_at, "is required") if ended_at.nil?
      errors.add(:decided_by, "is required") if decided_by_id.nil?
      errors.add(:allow_next_application, "must be explicitly chosen") unless [ true, false ].include?(allow_next_application)
      errors.add(:rejection_reason, "is required") if outcome == "rejected" && rejection_reason_id.nil?
      errors.add(:rejection_reason, "must be blank") if outcome != "rejected" && rejection_reason_id.present?
    end
  end
end
