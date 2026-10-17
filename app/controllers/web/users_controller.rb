module Web
  class UsersController < BaseController
    before_action :require_manage_permission
    before_action :load_user, only: %i[show edit update]
    before_action :prepare_form, only: %i[new create edit update]

    def index
      @query = params[:q].to_s
      scope = User.includes(:role, :branch, :departments).order(id: :asc)
      if @query.present?
        raise ActionController::ParameterMissing, :q if @query.length > 200
        prefix = "#{Candidate.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("lower(users.full_name) LIKE :prefix OR lower(users.login) LIKE :prefix", prefix: prefix)
      end
      @users = workflow_page(scope)
    end

    def new
      @user = User.new(active: true)
    end

    def show; end

    def create
      @user = Administration::Users.new(current_user).save!(User.new, user_attributes)
      redirect_to users_path, status: :see_other, notice: "Сотрудник создан."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    end

    def edit; end

    def update
      @user = Administration::Users.new(current_user).save!(@user, user_attributes)
      redirect_to users_path, status: :see_other, notice: "Изменения сохранены."
    rescue ActiveRecord::RecordInvalid => error
      @user = error.record
      invalid_form(error.record, :edit)
    end

    private

    def require_manage_permission
      raise Recruitment::Planning::Forbidden unless current_user.allows?("manage.users")
    end

    def load_user
      @user = User.includes(:departments).find(params[:id])
    end

    def prepare_form
      @roles = Role.order(:name).to_a
      @branches = Branch.order(:name).to_a
      @departments_by_branch = Department.includes(:branch).order(:name).group_by(&:branch_id)
    end

    def user_attributes
      raw = params.require(:user)
      attributes = raw.permit(:login, :full_name, :role_id, :branch_id, :active,
        :password, :password_confirmation, department_ids: []).to_h
      if raw.key?(:department_ids) || raw.key?("department_ids")
        attributes["department_ids"] = Array(attributes["department_ids"]).reject(&:blank?)
      else
        attributes.delete("department_ids")
      end
      attributes
    end

    def invalid_form(record, action)
      @user = record
      @errors = validation_messages(record)
      prepare_form
      render action, status: :unprocessable_entity
    end
  end
end
