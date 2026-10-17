module Api
  module V1
    class RolesController < BaseController
      before_action -> { authorize!("manage.roles") }

      def index
        render json: { roles: page_records(Role.all), available_permissions: Role::PERMISSIONS }
      end

      def create
        persist!(Role.new, :created)
      end

      def update
        persist!(Role.find(params[:id]), :ok)
      end

      private

      def persist!(role, status)
        attributes = params.require(:role).permit(:name, permissions: [])
        role = Administration::Roles.new(current_user).save!(role, attributes)
        render json: role, status: status
      end
    end
  end
end
