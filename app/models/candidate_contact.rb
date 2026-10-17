class CandidateContact < ApplicationRecord
  belongs_to :candidate
  before_validation :normalize_value
  validates :kind, inclusion: { in: %w[phone email] }
  validates :value, :normalized_value, presence: true, length: { maximum: 254 }
  validates :normalized_value, uniqueness: { scope: [ :candidate_id, :kind ] }
  validate :valid_contact

  def self.normalize(kind, value)
    case kind
    when "phone" then value.to_s.gsub(/[\s().-]/, "")
    when "email" then value.to_s.strip.downcase
    else value.to_s.strip
    end
  end

  private

  def normalize_value
    self.normalized_value = self.class.normalize(kind, value)
  end

  def valid_contact
    case kind
    when "phone"
      errors.add(:value, "must be an international phone number beginning with +") unless normalized_value.to_s.match?(/\A\+[1-9][0-9]{7,14}\z/)
    when "email"
      errors.add(:value, "must be an email address") unless normalized_value.to_s.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
