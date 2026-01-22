# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    # Override resource_params to handle empty password fields
    def resource_params
      params_hash = super
      if params_hash[:password].blank? && params_hash[:password_confirmation].blank?
        params_hash.delete(:password)
        params_hash.delete(:password_confirmation)
      end
      params_hash
    end

    def destroy
      if requested_resource.super_admin?
        redirect_to admin_users_path, alert: "Cannot delete super admin user"
      else
        super
      end
    end

    def impersonate
      impersonate_user(requested_resource)
      redirect_to root_path
    end

    def stop_impersonate
      stop_impersonating_user
      redirect_to admin_users_path
    end
  end
end
