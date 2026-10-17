class VacancyTemplate < ApplicationRecord
  belongs_to :recruiter, class_name: "User"
  belongs_to :created_by, class_name: "User"
  has_many :versions, class_name: "VacancyTemplateVersion", dependent: :restrict_with_error
  has_one :latest_version, -> { select("DISTINCT ON (vacancy_template_id) vacancy_template_versions.*").order(:vacancy_template_id, version_number: :desc) }, class_name: "VacancyTemplateVersion"
  has_one :recruitment_campaign, dependent: :restrict_with_error
  validates :status, inclusion: { in: %w[draft approved] }
  validate :recruiter_can_run_campaign

  private

  def recruiter_can_run_campaign
    errors.add(:recruiter, "must be active and allowed to launch campaigns") unless recruiter&.allows?("launch.recruitment_campaign")
  end
end
