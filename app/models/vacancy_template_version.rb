class VacancyTemplateVersion < ApplicationRecord
  include ImmutableVersion
  include StringLists

  CONTENT_FIELDS = %w[title duties professional_skills mandatory_requirements preferred_requirements
    screening_questions internship_required internship_criteria].freeze

  belongs_to :vacancy_template
  validates :version_number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :vacancy_template_id }
  validates :title, presence: true, length: { maximum: 200 }
  validates :duties, presence: true, length: { maximum: 20_000 }
  validates :internship_required, inclusion: { in: [ true, false ] }
  validates_string_lists :professional_skills, :mandatory_requirements, :preferred_requirements, :screening_questions, :internship_criteria
  validate do
    errors.add(:internship_criteria, "are required for mandatory internship") if internship_required? && internship_criteria.blank?
  end
end
