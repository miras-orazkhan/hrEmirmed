module Web
  class BaseController < ActionController::Base
    layout "web"
    include WorkflowsHelper

    COOKIE_NAME = :hr_emirmed_auth_token

    protect_from_forgery with: :exception
    before_action :disable_caching
    before_action :authenticate_web_user!

    rescue_from Recruitment::Planning::Forbidden do
      render_error("Недостаточно прав для выполнения действия.", :forbidden)
    end

    rescue_from Recruitment::Planning::InvalidTransition do |error|
      render_error(workflow_error_message(error), :unprocessable_entity)
    end

    rescue_from ActiveRecord::RecordNotFound do
      render_error("Запись не найдена или недоступна.", :not_found)
    end

    rescue_from ActiveRecord::RecordInvalid, with: :render_invalid_record
    rescue_from ActiveRecord::RecordNotUnique do
      render_error("Такая запись уже существует.", :unprocessable_entity)
    end
    rescue_from ActiveRecord::InvalidForeignKey do
      render_error("Не удалось сохранить: связанная запись отсутствует.", :unprocessable_entity)
    end
    rescue_from ActionController::ParameterMissing do
      render_error("Проверьте заполнение формы.", :bad_request)
    end

    helper_method :current_user, :allowed?

    private

    attr_reader :current_user, :current_auth_session

    def disable_caching
      response.set_header("Cache-Control", "private, no-store")
    end

    def authenticate_web_user!
      token = cookies.encrypted[COOKIE_NAME]
      @current_auth_session = AuthSession.authenticate(token)
      @current_user = @current_auth_session&.user
      return if @current_user&.active?

      cookies.delete(COOKIE_NAME, path: "/")
      redirect_to new_session_path, status: :see_other, alert: "Войдите в систему, чтобы продолжить."
    end

    def allowed?(permission)
      current_user&.allows?(permission) || false
    end

    def authenticated_home_path
      return candidates_path if allowed?("read.candidate")
      return job_requisitions_path if allowed?("read.job_requisition")
      return vacancy_templates_path if allowed?("read.vacancy_template")
      return recruitment_campaigns_path if allowed?("read.recruitment_campaign")
      return users_path if allowed?("manage.users")
      return roles_path if allowed?("manage.roles")
      return branches_path if allowed?("read.organization")

      root_path
    end

    def render_error(message, status)
      @error_message = message
      render "web/shared/error", status: status
    end

    def render_invalid_record(error)
      render_error(validation_messages(error.record).join(" "), :unprocessable_entity)
    end
  end
end
