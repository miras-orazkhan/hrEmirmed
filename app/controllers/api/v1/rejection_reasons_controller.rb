module Api
  module V1
    class RejectionReasonsController < BaseController
      before_action -> { authorize!("read.candidate") }, only: :index
      before_action -> { authorize!("manage.rejection_reason") }, only: %i[create update]

      def index
        render json: page_records(Administration::RejectionReasons.new(current_user).records).map { |reason| reason_json(reason) }
      end

      def create
        reason = Administration::RejectionReasons.new(current_user).create(reason_params.to_h)
        render json: reason_json(reason), status: :created
      end

      def update
        reason = Administration::RejectionReasons.new(current_user).update(params[:id], reason_params.to_h)
        render json: reason_json(reason)
      end

      private

      def reason_params
        payload = params[:rejection_reason]
        raise ActionController::ParameterMissing, :rejection_reason unless payload.is_a?(ActionController::Parameters)

        payload.permit(:name, :active)
      end

      def reason_json(reason)
        reason.as_json(only: %i[id name active created_at updated_at])
      end


    end
  end
end
