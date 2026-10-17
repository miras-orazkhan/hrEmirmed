module Api
  module V1
    class MeController < BaseController
      def show
        render json: user_json(current_user).merge(
          role: current_user.role.name,
          permissions: current_user.admin? ? Role::PERMISSIONS : current_user.role.permissions
        )
      end
    end
  end
end
