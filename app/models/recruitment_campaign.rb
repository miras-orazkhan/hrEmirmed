class RecruitmentCampaign < ApplicationRecord
  belongs_to :vacancy_template
  belongs_to :recruiter, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :job_requisitions, dependent: :restrict_with_error
  validates :status, inclusion: { in: %w[pending_approval active paused] }
  validates :vacancy_template_id, uniqueness: true
  validates :search_query, length: { maximum: 20_000 }
  validates :search_query, :approved_at, :approved_by, presence: true, if: -> { status == "active" }
end
