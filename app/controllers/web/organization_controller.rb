module Web
  class OrganizationController < BaseController
    helper_method :resource_name

    before_action :require_manage_permission, only: %i[new create edit update]
    before_action :load_record, only: %i[edit update]

    def index
      scope = administration.records
      if resource_name == "departments" && params[:branch_id].present?
        scope = scope.where(branch_id: params[:branch_id])
      end
      @query = params[:q].to_s
      if @query.present?
        raise ActionController::ParameterMissing, :q if @query.length > 200
        prefix = "#{resource_class.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("lower(#{resource_class.table_name}.name) LIKE ?", prefix)
      end
      @records = workflow_page(scope.includes(index_includes))
      @branches = Branch.order(:name) if resource_name == "departments"
    end

    def new
      @record = resource_class.new
      prepare_form
    end

    def create
      @record = administration.create(resource_attributes)
      redirect_to index_path, status: :see_other, notice: "Запись создана."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    rescue ActionController::ParameterMissing
      @record ||= resource_class.new
      invalid_form(@record, :new)
    end

    def edit
      prepare_form
    end

    def update
      @record = administration.update(params[:id], resource_attributes)
      redirect_to index_path, status: :see_other, notice: "Изменения сохранены."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :edit)
    rescue ActionController::ParameterMissing
      invalid_form(@record, :edit)
    end

    private

    def resource_name
      self.class::RESOURCE_NAME
    end

    def resource_class
      Administration::Organization::RESOURCES.fetch(resource_name)
    end

    def administration
      @administration ||= Administration::Organization.new(current_user, resource_name)
    end

    def index_path
      public_send("#{resource_name}_path")
    end

    def load_record
      @record = resource_class.find(params[:id])
    end

    def index_includes
      resource_name == "departments" ? :branch : []
    end

    def prepare_form
      @branches = Branch.order(:name) if resource_name == "departments"
    end

    def require_manage_permission
      head :forbidden unless current_user.allows?("manage.organization")
    end

    def resource_attributes
      fields = case resource_name
      when "branches" then %i[name address]
      when "departments" then %i[name branch_id]
      when "legal_entities" then %i[name registration_number]
      end
      params.require(resource_class.model_name.param_key).permit(*fields)
    end

    def invalid_form(record, action)
      @record = record
      @errors = validation_messages(record)
      prepare_form
      render action, status: :unprocessable_entity
    end
  end
end
