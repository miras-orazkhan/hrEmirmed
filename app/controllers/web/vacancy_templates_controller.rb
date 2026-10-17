module Web
  class VacancyTemplatesController < BaseController
    include WorkflowsHelper

    before_action :require_manage_permission, only: %i[new create edit update]
    def index
      scope = planning.templates.includes(:latest_version).order(id: :asc)
      @query = params[:q].to_s
      if @query.present?
        raise ActionController::ParameterMissing, :q if @query.length > 200
        prefix = "#{Candidate.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where(id: VacancyTemplateVersion.where("lower(title) LIKE ?", prefix).where("version_number = (SELECT MAX(v.version_number) FROM vacancy_template_versions v WHERE v.vacancy_template_id = vacancy_template_versions.vacancy_template_id)").select(:vacancy_template_id))
      end
      @templates = workflow_page(scope)
    end

    def show
      load_template
    end

    before_action :prepare_recruiters, only: %i[new create edit update]

    def new
      @template = VacancyTemplate.new
      @version = VacancyTemplateVersion.new
      @template.recruiter_id = current_user.id
    end

    def create
      @template = planning.create_template(template_attributes)
      redirect_to vacancy_template_path(@template), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      invalid_form(error.record, :new)
    end

    def edit
      load_template
    end

    def update
      @template = planning.revise_template(params[:id], template_attributes)
      redirect_to vacancy_template_path(@template), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @template = planning.templates.includes(:latest_version).find(params[:id])
      invalid_form(error.record, :edit)
    end

    def approve
      @template = planning.approve_template(params[:id])
      redirect_to vacancy_template_path(@template), status: :see_other, notice: "Шаблон утверждён."
    end

    private

    def require_manage_permission
      head :forbidden unless current_user.allows?("manage.vacancy_template")
    end

    def prepare_recruiters
      @recruiters = User.where(active: true).includes(:role).order(:full_name).select { |user| user.allows?("launch.recruitment_campaign") }
    end

    def planning
      @planning ||= Recruitment::Planning.new(current_user)
    end

    def load_template
      @template = planning.templates.includes(:latest_version).find(params[:id])
      @version = @template.latest_version
      load_list_fields
    end

    def template_attributes
      payload = params.require(:vacancy_template).permit(:recruiter_id, :title, :duties, :internship_required,
        :professional_skills_lines, :mandatory_requirements_lines, :preferred_requirements_lines,
        :screening_questions_lines, :internship_criteria_lines)
      attrs = payload.to_h.except(*%w[professional_skills_lines mandatory_requirements_lines preferred_requirements_lines screening_questions_lines internship_criteria_lines])
      attrs["internship_required"] = form_boolean(payload["internship_required"])
      {
        **attrs,
        "professional_skills" => lines_to_list(payload["professional_skills_lines"]),
        "mandatory_requirements" => lines_to_list(payload["mandatory_requirements_lines"]),
        "preferred_requirements" => lines_to_list(payload["preferred_requirements_lines"]),
        "screening_questions" => lines_to_list(payload["screening_questions_lines"]),
        "internship_criteria" => lines_to_list(payload["internship_criteria_lines"])
      }
    end

    def load_list_fields
      @version ||= @template.latest_version
      @version ||= VacancyTemplateVersion.new
      %w[professional_skills mandatory_requirements preferred_requirements screening_questions internship_criteria].each do |field|
        instance_variable_set("@#{field}_lines", Array(@version.public_send(field)).join("\n"))
      end
    end

    def invalid_form(record, action)
      @template ||= record.is_a?(VacancyTemplate) ? record : VacancyTemplate.new
      @version = record.is_a?(VacancyTemplateVersion) ? record : (@template.latest_version || VacancyTemplateVersion.new)
      load_list_fields
      @errors = validation_messages(record)
      render action, status: :unprocessable_entity
    end
  end
end
