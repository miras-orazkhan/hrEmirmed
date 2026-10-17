class RejectionReason < ApplicationRecord
  normalizes :name, with: ->(value) { value.strip }
  validates :name, presence: true, uniqueness: true, length: { maximum: 200 }
  validates :active, inclusion: { in: [ true, false ] }
end
