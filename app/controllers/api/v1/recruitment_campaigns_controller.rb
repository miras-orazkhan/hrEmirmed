module Api
  module V1
    class RecruitmentCampaignsController < BaseController
      def index
        scope = planning.campaigns
        scope = scope.where(status: params[:status]) if params[:status].present?
        render json: page_records(scope)
      end

      def show
        render json: planning.campaigns.find(params[:id])
      end

      def launch
        attributes = params.require(:recruitment_campaign).permit(:search_query)
        render json: planning.launch_campaign(params[:id], search_query: attributes[:search_query])
      end

      private

      def planning
        Recruitment::Planning.new(current_user)
      end
    end
  end
end
