module Web
  class RejectionReasonsController < BaseController
    before_action :require_manage_permission, only: %i[new create edit update]
    before_action :load_reason, only: %i[edit update]

    def index
      scope = administration.records
      @query = params[:q].to_s
      if @query.present?
        raise ActionController::ParameterMissing, :q if @query.length > 200
        prefix = "#{RejectionReason.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("lower(rejection_reasons.name) LIKE ?", prefix)
      end
      @reasons = workflow_page(scope)
    end

    def new
      @reason = RejectionReason.new(active: true)
    end

    def create
      @reason = administration.create(reason_attributes)
      redirect_to rejection_reasons_path, status: :see_other, notice: "Причина отказа создана."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    rescue ActionController::ParameterMissing
      @reason ||= RejectionReason.new(active: true)
      invalid_form(@reason, :new)
    end

    def edit; end

    def update
      @reason = administration.update(params[:id], reason_attributes)
      redirect_to rejection_reasons_path, status: :see_other, notice: "Изменения сохранены."
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :edit)
    rescue ActionController::ParameterMissing
      invalid_form(@reason, :edit)
    end

    private

    def administration
      @administration ||= Administration::RejectionReasons.new(current_user)
    end

    def require_manage_permission
      head :forbidden unless current_user.allows?("manage.rejection_reason")
    end

    def load_reason
      @reason = RejectionReason.find(params[:id])
    end

    def reason_attributes
      params.require(:rejection_reason).permit(:name, :active).to_h.tap do |attributes|
        attributes["active"] = ActiveModel::Type::Boolean.new.cast(attributes["active"])
      end
    end

    def invalid_form(record, action)
      @reason = record
      @errors = validation_messages(record)
      render action, status: :unprocessable_entity
    end
  end
end
