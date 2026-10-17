class JobRequisitionVersion < ApplicationRecord
  include ImmutableVersion
  include StringLists

  CONTENT_FIELDS = %w[work_schedule salary_amount salary_currency desired_start_on interviewer_id
    interview_format internship_supervisor_id internship_duration additional_questions].freeze

  belongs_to :job_requisition
  belongs_to :interviewer, class_name: "User"
  belongs_to :internship_supervisor, class_name: "User", optional: true
  normalizes :salary_currency, with: ->(value) { value.strip.upcase }
  validates :version_number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :job_requisition_id }
  validates :work_schedule, presence: true, length: { maximum: 5_000 }
  validates :salary_amount, numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000_000_000 }
  validates :salary_currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :desired_start_on, presence: true
  validates :interview_format, inclusion: { in: %w[onsite online] }
  validates :internship_duration, length: { maximum: 200 }
  validates_string_lists :additional_questions
  validate :assigned_staff

  private

  def assigned_staff
    return unless job_requisition
    if interviewer
      allowed = interviewer.active? && (interviewer.id == job_requisition.recruiter_id ||
        (interviewer.allows?("conduct.interview") && interviewer.branch_id == job_requisition.department.branch_id))
      errors.add(:interviewer, "must be the recruiter or an authorized interviewer from this branch") unless allowed
    end
    if job_requisition.vacancy_template_version&.internship_required?
      errors.add(:internship_duration, "is required") if internship_duration.blank?
      unless internship_supervisor&.allows?("supervise.internship") && internship_supervisor.branch_id == job_requisition.department.branch_id
        errors.add(:internship_supervisor, "must be an active authorized supervisor from this branch")
      end
    end
  end
end
