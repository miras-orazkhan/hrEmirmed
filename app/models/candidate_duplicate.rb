class CandidateDuplicate < ApplicationRecord
  belongs_to :candidate
  belongs_to :other_candidate, class_name: "Candidate"
  belongs_to :resolved_by, class_name: "User", optional: true
  validates :status, inclusion: { in: %w[pending distinct confirmed] }
  validates :resolution_note, length: { maximum: 5_000 }

  def requires_hr_review?
    candidate.responsible_recruiter_id != other_candidate.responsible_recruiter_id
  end
end
