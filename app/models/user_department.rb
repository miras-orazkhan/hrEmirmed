class UserDepartment < ApplicationRecord
  belongs_to :user
  belongs_to :department
  before_validation { self.branch_id = user.branch_id if user }
  validates :department_id, uniqueness: { scope: :user_id }
  validate :same_branch

  private

  def same_branch
    if user && department && user.branch_id != department.branch_id
      errors.add(:department, "must belong to the user's branch")
    end
  end
end
