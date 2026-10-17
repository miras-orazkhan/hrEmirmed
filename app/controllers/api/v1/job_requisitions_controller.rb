module Api
  module V1
    class JobRequisitionsController < BaseController
      def index
        scope = planning.requisitions.preload(:latest_version)
        scope = scope.where(department_id: params[:department_id]) if params[:department_id].present?
        scope = scope.where(recruitment_campaign_id: params[:recruitment_campaign_id]) if params[:recruitment_campaign_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        render json: page_records(scope).map { |record| requisition_json(record) }
      end

      def show
        render json: requisition_json(planning.requisitions.find(params[:id]))
      end

      def create
        render json: requisition_json(planning.create_requisition(requisition_params)), status: :created
      end

      def update
        render json: requisition_json(planning.revise_requisition(params[:id], requisition_params))
      end

      def pause
        transition("pause")
      end

      def resume
        transition("resume")
      end

      def cancel
        transition("cancel", allow_next_application: params.dig(:job_requisition, :allow_next_application))
      end

      def versions
        requisition = planning.requisitions.find(params[:id])
        render json: page_records(requisition.versions)
      end

      private

      def planning
        Recruitment::Planning.new(current_user)
      end

      def requisition_params
        params.require(:job_requisition).permit(:department_id, :vacancy_template_id, :positions_count,
          :work_schedule, :salary_amount, :salary_currency, :desired_start_on, :interviewer_id,
          :interview_format, :internship_supervisor_id, :internship_duration, additional_questions: []).to_h
      end

      def transition(action, allow_next_application: nil)
        render json: requisition_json(planning.transition_requisition(params[:id], action,
          allow_next_application: allow_next_application))
      end

      def requisition_json(record)
        record.as_json.merge("current_version" => record.latest_version.as_json,
          "remaining_positions_count" => record.positions_count - record.filled_positions_count)
      end
    end
  end
end
