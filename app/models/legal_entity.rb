class LegalEntity < ApplicationRecord
  validates :name, presence: true, length: { maximum: 200 }, uniqueness: true
end
