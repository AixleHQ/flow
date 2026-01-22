class Web::HomeController < Web::ApplicationController
  def show
    redirect_to admin_users_path if current_user && current_user.super_admin?
  end
end
