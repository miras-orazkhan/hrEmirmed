class User < ApplicationRecord
  has_secure_password
  belongs_to :branch
  belongs_to :role
  has_many :user_departments, dependent: :destroy
  has_many :departments, through: :user_departments
  has_many :auth_sessions, dependent: :destroy

  normalizes :login, with: ->(value) { value.strip.downcase }
  validates :login, presence: true, uniqueness: true, length: { maximum: 100 }, format: { with: /\A[a-z0-9_.@-]+\z/ }
  validates :full_name, presence: true, length: { maximum: 200 }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }
  validate :departments_belong_to_branch
  after_update :revoke_sessions, if: -> { saved_change_to_password_digest? || saved_change_to_active? }

  def allows?(permission)
    active? && role.allows?(permission)
  end

  def admin?
    active? && role.admin?
  end

  private

  def departments_belong_to_branch
    errors.add(:departments, "must include at least one department") if departments.empty?
    if departments.any? { |department| department.branch_id != branch_id }
      errors.add(:departments, "must belong to the user's branch")
    end
  end

  def revoke_sessions
    auth_sessions.delete_all
  end
end
