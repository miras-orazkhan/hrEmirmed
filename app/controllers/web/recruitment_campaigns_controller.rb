module Web
  class RecruitmentCampaignsController < BaseController
    include WorkflowsHelper
    def index
      scope = planning.campaigns.includes(:recruiter, vacancy_template: :latest_version).order(id: :asc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      @campaigns = workflow_page(scope)
    end

    def show
      @campaign = planning.campaigns.includes(:recruiter, :approved_by, vacancy_template: :latest_version).find(params[:id])
      @requisitions = JobRequisition.where(recruitment_campaign_id: @campaign.id)
        .includes(:department, :vacancy_template_version).order(id: :asc).limit(50)
    end

    def launch
      payload = params.require(:recruitment_campaign).permit(:search_query)
      @campaign = planning.launch_campaign(params[:id], search_query: payload[:search_query])
      redirect_to recruitment_campaign_path(@campaign), status: :see_other, notice: "Кампания запущена."
    rescue ActiveRecord::RecordInvalid => error
      @campaign = planning.campaigns.includes(:recruiter, vacancy_template: :latest_version).find(params[:id])
      @requisitions = @campaign.job_requisitions.includes(:department, :vacancy_template_version).order(:id).limit(50)
      @errors = validation_messages(error.record)
      render :show, status: :unprocessable_entity
    end

    private

    def planning
      @planning ||= Recruitment::Planning.new(current_user)
    end
  end
end
