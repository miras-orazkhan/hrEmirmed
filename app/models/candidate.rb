class Candidate < ApplicationRecord
  belongs_to :responsible_recruiter, class_name: "User"
  belongs_to :created_by, class_name: "User"
  has_many :contacts, class_name: "CandidateContact", dependent: :restrict_with_error
  has_many :sources, class_name: "CandidateSource", dependent: :restrict_with_error
  has_many :applications, class_name: "CandidateApplication", dependent: :restrict_with_error
  has_many :resumes, class_name: "CandidateResume", dependent: :restrict_with_error
  has_one :active_application, -> { where(status: "active") }, class_name: "CandidateApplication"

  normalizes :full_name, with: ->(value) { value.strip }
  validates :full_name, presence: true, length: { maximum: 200 }
  validates :city, length: { maximum: 200 }
  validates :preferred_language, length: { maximum: 16 }
  validates :summary, length: { maximum: 20_000 }
  validate do
    errors.add(:responsible_recruiter, "must be active") unless responsible_recruiter&.active?
  end
end
