class Branch < ApplicationRecord
  has_many :departments, dependent: :restrict_with_error
  has_many :users, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 200 }, uniqueness: true
end
