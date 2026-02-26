class Web::HomeController < Web::ApplicationController
  def show
    if request.path == "/"
      render html: "", layout: "web/landing"
    elsif signed_in? && current_user.super_admin?
      redirect_to admin_users_path
    end
  end
end
