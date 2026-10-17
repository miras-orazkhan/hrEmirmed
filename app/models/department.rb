class Department < ApplicationRecord
  belongs_to :branch
  has_many :user_departments, dependent: :restrict_with_error
  has_many :users, through: :user_departments
  validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :branch_id }
  validate :branch_cannot_change_with_members

  private

  def branch_cannot_change_with_members
    if persisted? && branch_id_changed? && user_departments.exists?
      errors.add(:branch, "cannot change while users are assigned")
    end
  end
end
