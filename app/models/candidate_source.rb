class CandidateSource < ApplicationRecord
  belongs_to :candidate
  normalizes :provider, :external_id, with: ->(value) { value.strip }
  validates :provider, presence: true, length: { maximum: 50 }, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :external_id, presence: true, length: { maximum: 200 }, uniqueness: { scope: :provider }
end
