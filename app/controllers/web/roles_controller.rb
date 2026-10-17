module Web
  class RolesController < BaseController
    before_action :require_manage_permission
    before_action :load_role, only: %i[edit update]

    PERMISSION_LABELS = {
      "read.organization" => "Просмотр структуры организации",
      "manage.organization" => "Управление структурой организации",
      "manage.users" => "Управление сотрудниками",
      "manage.roles" => "Управление ролями",
      "read.audit" => "Просмотр журнала действий",
      "read.vacancy_template" => "Просмотр шаблонов вакансий",
      "manage.vacancy_template" => "Управление шаблонами вакансий",
      "approve.vacancy_template" => "Утверждение шаблонов вакансий",
      "read.job_requisition" => "Просмотр заявок на подбор",
      "create.job_requisition" => "Создание заявок на подбор",
      "update.job_requisition" => "Изменение заявок своего подразделения",
      "manage.job_requisition" => "Управление всеми заявками",
      "read.recruitment_campaign" => "Просмотр кампаний подбора",
      "launch.recruitment_campaign" => "Запуск кампаний подбора",
      "read.all_recruitment" => "Просмотр общего подбора",
      "conduct.interview" => "Проведение собеседований",
      "supervise.internship" => "Сопровождение стажировок",
      "read.candidate" => "Просмотр доступных кандидатов",
      "read.all_candidates" => "Просмотр всех кандидатов",
      "create.candidate" => "Создание кандидатов",
      "update.candidate" => "Изменение доступных кандидатов",
      "import.candidate" => "Импорт кандидатов",
      "manage.candidate_application" => "Ведение рассмотрений кандидатов",
      "resolve.candidate_duplicate" => "Решение по дублям кандидатов",
      "manage.all_candidate_duplicates" => "Управление всеми дублями кандидатов",
      "manage.rejection_reason" => "Управление причинами отказа"
    }.freeze

    def index
      @roles = workflow_page(Role.order(id: :asc))
    end

    def new
      @role = Role.new(permissions: [])
    end

    def create
      @role = Administration::Roles.new(current_user).save!(Role.new, role_attributes)
      redirect_to roles_path, status: :see_other, notice: "Роль создана."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    end

    def edit; end

    def update
      @role = Administration::Roles.new(current_user).save!(@role, role_attributes)
      redirect_to roles_path, status: :see_other, notice: "Изменения сохранены."
    rescue ActiveRecord::RecordInvalid => error
      @role = error.record
      invalid_form(error.record, :edit)
    end

    private

    def require_manage_permission
      raise Recruitment::Planning::Forbidden unless current_user.allows?("manage.roles")
    end

    def load_role
      @role = Role.find(params[:id])
    end

    def role_attributes
      attributes = params.require(:role).permit(:name, permissions: []).to_h
      attributes["permissions"] ||= []
      attributes
    end

    def invalid_form(record, action)
      @role = record
      @errors = validation_messages(record)
      render action, status: :unprocessable_entity
    end
  end
end
