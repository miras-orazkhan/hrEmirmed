module Web
  class JobRequisitionsController < BaseController
    include WorkflowsHelper

    before_action :require_create_permission, only: %i[new create]
    before_action :require_update_permission, only: %i[edit update]
    def index
      scope = planning.requisitions.includes(:department, :recruitment_campaign, :vacancy_template_version, :latest_version).order(id: :asc)
      @departments = visible_departments
      @query = params[:q].to_s
      if params[:department_id].present?
        scope = scope.where(department_id: @departments.where(id: params[:department_id]).select(:id))
      end
      if @query.present?
        raise ActionController::ParameterMissing, :q if @query.length > 200
        prefix = "#{Candidate.sanitize_sql_like(@query.downcase)}%"
        scope = scope.joins(:vacancy_template_version).where("lower(vacancy_template_versions.title) LIKE ?", prefix)
      end
      @requisitions = workflow_page(scope)
    end

    def show
      load_requisition
    end

    def new
      @requisition = JobRequisition.new
      @version = JobRequisitionVersion.new(salary_currency: "KZT", interview_format: "onsite")
      prepare_form
    end

    def create
      @requisition = planning.create_requisition(requisition_attributes)
      redirect_to job_requisition_path(@requisition), status: :see_other
    rescue Recruitment::Planning::InvalidTransition => error
      @errors = [ workflow_error_message(error) ]
      @requisition = JobRequisition.new
      @version = JobRequisitionVersion.new
      prepare_form
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    end

    def edit
      load_requisition
      prepare_form
    end

    def update
      @requisition = planning.revise_requisition(params[:id], requisition_attributes)
      redirect_to job_requisition_path(@requisition), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @requisition = planning.requisitions.includes(:latest_version).find(params[:id])
      invalid_form(error.record, :edit)
    end

    def pause
      transition("pause")
    end

    def resume
      transition("resume")
    end

    def cancel
      value = params.dig(:job_requisition, :allow_next_application)
      transition("cancel", allow_next_application: normalize_boolean(value))
    end

    private

    def require_create_permission
      head :forbidden unless current_user.allows?("create.job_requisition")
    end

    def require_update_permission
      head :forbidden unless current_user.allows?("update.job_requisition")
    end

    def planning
      @planning ||= Recruitment::Planning.new(current_user)
    end

    def load_requisition
      @requisition = planning.requisitions.includes(:latest_version, :department, :vacancy_template_version, :recruitment_campaign).find(params[:id])
      @version = @requisition.latest_version
      load_list_fields
    end

    def prepare_form
      @departments = visible_departments
      @templates = planning.templates.where(status: "approved").includes(:latest_version).order(id: :asc)
      @requisition.department_id ||= @departments.first&.id
      @users = User.where(active: true, branch_id: @departments.select(:branch_id))
        .includes(:role, :branch).order(:full_name).select do |user|
          user.allows?("launch.recruitment_campaign") || user.allows?("conduct.interview") || user.allows?("supervise.internship")
        end
    end

    def visible_departments
      current_user.admin? ? Department.includes(:branch).order(:name) :
        current_user.departments.includes(:branch).order(:name)
    end

    def requisition_attributes
      payload = params.require(:job_requisition).permit(:department_id, :vacancy_template_id, :positions_count,
        :work_schedule, :salary_amount, :salary_currency, :desired_start_on, :interviewer_id,
        :interview_format, :internship_duration, :internship_supervisor_id, :additional_questions_lines)
      attrs = payload.to_h.except("additional_questions_lines")
      attrs["additional_questions"] = lines_to_list(payload["additional_questions_lines"])
      attrs
    end

    def transition(action, allow_next_application: nil)
      @requisition = planning.transition_requisition(params[:id], action, allow_next_application: allow_next_application)
      redirect_to job_requisition_path(@requisition), status: :see_other, notice: "Изменения сохранены."
    end

    def normalize_boolean(value)
      return true if value == true || value == "true" || value == "1"
      return false if value == false || value == "false" || value == "0"
      value
    end

    def load_list_fields
      @version ||= @requisition.latest_version || JobRequisitionVersion.new
      @additional_questions_lines = Array(@version.additional_questions).join("\n")
    end

    def invalid_form(record, action)
      @requisition ||= record.is_a?(JobRequisition) ? record : JobRequisition.new
      @version = record.is_a?(JobRequisitionVersion) ? record : (@requisition.latest_version || JobRequisitionVersion.new)
      @additional_questions_lines = Array(@version.additional_questions).join("\n")
      @errors = validation_messages(record)
      prepare_form
      render action, status: :unprocessable_entity
    end
  end
end
