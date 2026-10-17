module Web
  class HomeController < BaseController
    def show
      destination = authenticated_home_path
      return redirect_to destination unless destination == root_path

      render plain: "У вашей учётной записи пока нет доступа к рабочим разделам.", status: :ok
    end
  end
end
