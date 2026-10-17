module Web
  class SessionsController < BaseController
    skip_before_action :authenticate_web_user!, only: %i[new create]
    before_action :redirect_authenticated_user, only: :new

    LOGIN_LIMIT_STORE = Rails.env.production? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new
    DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(SecureRandom.hex(32)).to_s.freeze

    rate_limit to: 10, within: 1.minute, only: :create, store: LOGIN_LIMIT_STORE,
      with: -> { render plain: "Слишком много попыток входа. Попробуйте позже.", status: :too_many_requests }

    def new
    end

    def create
      credentials = params.require(:session).permit(:login, :password)
      user = User.find_by(login: credentials[:login].to_s.strip.downcase)
      auth_session = token = nil

      if user
        user.with_lock do
          if user.authenticate(credentials[:password].to_s) && user.active?
            auth_session, token = AuthSession.issue!(user)
            AuditEvent.record!(actor: user, action: "session.created", subject: auth_session)
          end
        end
      else
        BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(credentials[:password].to_s)
      end

      unless auth_session
        @web_error_message = "Неверный логин или пароль."
        render :new, status: :unprocessable_entity
        return
      end

      reset_session
      cookies.encrypted[COOKIE_NAME] = {
        value: token,
        expires: auth_session.expires_at,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        path: "/"
      }
      redirect_to authenticated_home_path, status: :see_other, notice: "Вы вошли в систему."
    end

    def destroy
      if current_auth_session
        AuthSession.transaction do
          AuditEvent.record!(actor: current_user, action: "session.revoked", subject: current_auth_session)
          current_auth_session.destroy!
        end
      end

      reset_session
      cookies.delete(COOKIE_NAME, path: "/")
      redirect_to new_session_path, status: :see_other, notice: "Вы вышли из системы."
    end

    private

    def redirect_authenticated_user
      token = cookies.encrypted[COOKIE_NAME]
      session = AuthSession.authenticate(token)
      if session&.user&.active?
        @current_user = session.user
        redirect_to authenticated_home_path
      end
    end
  end
end
