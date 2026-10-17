class AuthSession < ApplicationRecord
  belongs_to :user
  validates :token_digest, :expires_at, presence: true

  def self.issue!(user)
    token = SecureRandom.urlsafe_base64(32)
    session = create!(user: user, token_digest: Digest::SHA256.hexdigest(token), expires_at: 12.hours.from_now)
    [ session, token ]
  end

  def self.authenticate(token)
    return unless token.to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)
    includes(user: :role).where(expires_at: Time.current..).find_by(token_digest: Digest::SHA256.hexdigest(token))
  end
end
