module Api
  module V1
    class OrganizationController < BaseController
      before_action -> { authorize!(%w[index show].include?(action_name) ? "read.organization" : "manage.organization") }

      def index
        records = Administration::Organization.new(current_user, controller_name).records
        records = records.where(branch_id: params[:branch_id]) if resource_class == Department && params[:branch_id].present?
        render json: page_records(records)
      end

      def show
        render json: Administration::Organization.new(current_user, controller_name).records.find(params[:id])
      end

      def create
        record = Administration::Organization.new(current_user, controller_name).create(resource_params)
        render json: record, status: :created
      end

      def update
        record = Administration::Organization.new(current_user, controller_name).update(params[:id], resource_params)
        render json: record
      end

      private

      def resource_class
        { "branches" => Branch, "departments" => Department, "legal_entities" => LegalEntity }.fetch(controller_name)
      end

      def resource_params
        fields = case resource_class.name
        when "Branch" then %i[name address]
        when "Department" then %i[name branch_id]
        else %i[name registration_number]
        end
        params.require(resource_class.model_name.param_key).permit(*fields)
      end


    end
  end
end
