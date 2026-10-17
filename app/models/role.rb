class Role < ApplicationRecord
  PERMISSIONS = %w[read.organization manage.organization manage.users manage.roles read.audit
    read.vacancy_template manage.vacancy_template approve.vacancy_template
    read.job_requisition create.job_requisition update.job_requisition manage.job_requisition
    read.recruitment_campaign launch.recruitment_campaign read.all_recruitment
    conduct.interview supervise.internship read.candidate read.all_candidates create.candidate update.candidate
    import.candidate manage.candidate_application resolve.candidate_duplicate manage.all_candidate_duplicates
    manage.rejection_reason].freeze

  has_many :users, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 200 }, uniqueness: true
  validate :known_permissions
  validate :preserve_admin

  def admin?
    name == "admin"
  end

  def allows?(permission)
    admin? || permissions.include?(permission)
  end

  private

  def known_permissions
    unless permissions.is_a?(Array) && (permissions - PERMISSIONS).empty?
      errors.add(:permissions, "must contain only supported permissions")
    end
  end

  def preserve_admin
    if persisted? && name_in_database == "admin" && name_changed?
      errors.add(:name, "of the admin role cannot change")
    end
  end
end
