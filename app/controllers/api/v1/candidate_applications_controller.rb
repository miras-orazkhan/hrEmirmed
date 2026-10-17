module Api
  module V1
    class CandidateApplicationsController < BaseController
      def index
        scope = access.visible_applications
        scope = scope.where(candidate_id: params[:candidate_id]) if params[:candidate_id].present?
        scope = scope.where(job_requisition_id: params[:job_requisition_id]) if params[:job_requisition_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        render json: page_records(scope)
      end

      def show
        render json: access.visible_applications.find(params[:id])
      end

      def create
        attributes = params.require(:candidate_application).permit(:candidate_id, :job_requisition_id)
        render json: workflow.start(candidate_id: attributes[:candidate_id], job_requisition_id: attributes[:job_requisition_id]), status: :created
      end

      def advance
        render json: workflow.advance(params[:id])
      end

      def finish
        attributes = params.require(:candidate_application).permit(:outcome, :rejection_reason_id,
          :decision_comment, :allow_next_application).to_h
        render json: workflow.finish(params[:id], attributes)
      end

      private

      def access
        @access ||= Candidates::Access.new(current_user)
      end

      def workflow
        @workflow ||= Candidates::Applications.new(current_user)
      end
    end
  end
end
