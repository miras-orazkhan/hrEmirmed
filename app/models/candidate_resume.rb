class CandidateResume < ApplicationRecord
  belongs_to :candidate
  belongs_to :uploaded_by, class_name: "User"
  has_one_attached :original

  validates :sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :original, presence: true
end
