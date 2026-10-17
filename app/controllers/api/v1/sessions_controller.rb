module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate!, only: :create
      LOGIN_LIMIT_STORE = Rails.env.production? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new
      DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(SecureRandom.hex(32)).to_s.freeze

      rate_limit to: 10, within: 1.minute, only: :create, store: LOGIN_LIMIT_STORE,
        with: -> { render json: { error: "too_many_attempts" }, status: :too_many_requests }

      def create
        credentials = params.require(:session).permit(:login, :password)
        user = User.find_by(login: credentials[:login].to_s.strip.downcase)
        session = token = nil
        if user
          # Serializes login with password changes and account deactivation.
          user.with_lock do
            if user.authenticate(credentials[:password].to_s) && user.active?
              session, token = AuthSession.issue!(user)
              AuditEvent.record!(actor: user, action: "session.created", subject: session)
            end
          end
        else
          BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(credentials[:password].to_s)
        end
        if session
          render json: { token: token, expires_at: session.expires_at, user: user_json(user) }, status: :created
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end

      def destroy
        AuthSession.transaction do
          AuditEvent.record!(actor: current_user, action: "session.revoked", subject: current_session)
          current_session.destroy!
        end
        head :no_content
      end
    end
  end
end
