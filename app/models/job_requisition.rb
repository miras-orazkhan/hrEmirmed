class JobRequisition < ApplicationRecord
  belongs_to :department
  belongs_to :vacancy_template
  belongs_to :vacancy_template_version
  belongs_to :recruitment_campaign
  belongs_to :recruiter, class_name: "User"
  belongs_to :created_by, class_name: "User"
  has_many :versions, class_name: "JobRequisitionVersion", dependent: :restrict_with_error
  has_one :latest_version, -> { select("DISTINCT ON (job_requisition_id) job_requisition_versions.*").order(:job_requisition_id, version_number: :desc) }, class_name: "JobRequisitionVersion"

  validates :status, inclusion: { in: %w[ready recruiting paused closed cancelled] }
  validates :positions_count, numericality: { only_integer: true, greater_than: 0 }
  validates :filled_positions_count, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: :positions_count }
end
