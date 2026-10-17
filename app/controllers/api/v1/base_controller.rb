module Api
  module V1
    class BaseController < ApplicationController
      before_action -> { response.set_header("Cache-Control", "no-store") }
      before_action :authenticate!

      rescue_from Recruitment::Planning::Forbidden do
        render json: { error: "forbidden" }, status: :forbidden
      end
      rescue_from Recruitment::Planning::InvalidTransition do |error|
        render json: { error: "invalid_transition", reason: error.message }, status: :conflict
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render json: { error: "validation_failed", details: error.record.errors.to_hash }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::RecordNotUnique do
        render json: { error: "conflict" }, status: :conflict
      end
      rescue_from ActiveRecord::InvalidForeignKey do
        render json: { error: "invalid_reference" }, status: :unprocessable_entity
      end
      rescue_from ActionController::ParameterMissing do |error|
        render json: { error: "invalid_parameters", parameter: error.param }, status: :bad_request
      end

      private

      attr_reader :current_session, :current_user

      # Keyset pagination avoids counting or scanning all earlier rows.
      def page_records(scope, descending: false)
        limit = params.fetch(:limit, 50).to_s
        cursor = params[:cursor].to_s
        unless limit.match?(/\A[0-9]{1,3}\z/) && limit.to_i.between?(1, 200) &&
            (cursor.empty? || (cursor.match?(/\A[0-9]{1,19}\z/) && cursor.to_i.between?(1, 9_223_372_036_854_775_807)))
          raise ActionController::ParameterMissing, :pagination
        end
        table = scope.klass.arel_table
        scope = scope.where(descending ? table[:id].lt(cursor.to_i) : table[:id].gt(cursor.to_i)) if cursor.present?
        records = scope.reorder(id: descending ? :desc : :asc).limit(limit.to_i + 1).to_a
        if records.size > limit.to_i
          records.pop
          response.set_header("X-Next-Cursor", records.last.id.to_s)
        end
        records
      end

      def authenticate!
        token = request.authorization.to_s.match(/\ABearer ([A-Za-z0-9_-]+)\z/)&.captures&.first
        @current_session = AuthSession.authenticate(token)
        @current_user = @current_session&.user
        unless current_user&.active?
          render json: { error: "unauthorized" }, status: :unauthorized
        end
      end

      def authorize!(permission)
        unless current_user.allows?(permission)
          render json: { error: "forbidden" }, status: :forbidden
        end
      end

      def user_json(user)
        user.as_json(only: %i[id login full_name active branch_id role_id]).merge("department_ids" => user.department_ids)
      end
    end
  end
end
