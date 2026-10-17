module Api
  module V1
    class UsersController < BaseController
      before_action -> { authorize!("manage.users") }

      def index
        users = User.select(:id, :login, :full_name, :active, :branch_id, :role_id).preload(:departments)
        users = users.where(branch_id: params[:branch_id]) if params[:branch_id].present?
        render json: page_records(users).map { |user| user_json(user) }
      end

      def show
        render json: user_json(User.find(params[:id]))
      end

      def create
        persist!(User.new, :created)
      end

      def update
        persist!(User.find(params[:id]), :ok)
      end

      private

      def persist!(user, status)
        attributes = params.require(:user).permit(:login, :full_name, :password, :password_confirmation,
          :active, :branch_id, :role_id, department_ids: [])
        user = Administration::Users.new(current_user).save!(user, attributes)
        render json: user_json(user), status: status
      end
    end
  end
end
