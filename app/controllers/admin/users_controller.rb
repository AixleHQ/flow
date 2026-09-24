# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    def authorized_action?(resource, action)
      return false if action.to_sym == :destroy && resource.is_a?(User) && resource.deleted?

      super
    end

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
        # Soft delete instead of a hard destroy: board activities (and other
        # historical records) referencing this user must be preserved, and a real
        # DELETE would violate the FK on board_activities.actor_id.
        requested_resource.soft_delete!
        redirect_to(
          after_resource_destroyed_path(requested_resource),
          notice: "User was successfully deleted."
        )
      end
    end

    # Irreversible hard delete, distinct from the soft-delete #destroy above.
    # Guarded three ways: super-admin accounts are refused, the admin must type
    # the exact email to confirm, and the view adds a data-turbo-confirm prompt.
    def permanent_destroy
      user = requested_resource

      if user.super_admin?
        return redirect_to admin_users_path, alert: "Cannot permanently delete a super admin user"
      end

      if params[:confirm_email].to_s.strip.casecmp?(user.email)
        Users::PermanentDeletionService.call(user: user, actor: true_user)
        redirect_to admin_users_path, notice: "User was permanently deleted."
      else
        redirect_to admin_user_path(user),
                    alert: "Confirmation email did not match. User was not deleted."
      end
    rescue Users::PermanentDeletionService::Error => e
      redirect_to admin_user_path(user), alert: e.message
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to admin_user_path(user), alert: "User could not be deleted: #{e.message}"
    rescue ActiveRecord::InvalidForeignKey
      redirect_to admin_user_path(user), alert: "User could not be deleted: a database constraint prevented removal. Please contact engineering."
    end

    def restore
      user = requested_resource

      unless user.deleted?
        return redirect_to admin_user_path(user), alert: "User is not deleted."
      end

      user.restore!
      redirect_to admin_user_path(user), notice: "User was restored."
    end

    # Ends every browser sign-in of the user (a lost laptop, a leaked cookie).
    def sign_out_everywhere
      user = requested_resource
      ended = UserSession.revoke_all_for!(user)
      audit!(user, "sessions_revoked", "#{true_user.email} signed #{user.email} out everywhere (#{ended} session(s))")
      redirect_to admin_user_path(user), notice: "Signed #{user.email} out of #{ended} session(s)."
    end

    def impersonate
      audit!(requested_resource, "impersonate_start", "#{true_user.email} impersonating #{requested_resource.email}")
      impersonate_user(requested_resource)
      redirect_to root_path
    end

    def stop_impersonate
      impersonated = current_user
      audit!(impersonated, "impersonate_stop", "#{true_user.email} stopped impersonating #{impersonated.email}")
      stop_impersonating_user
      redirect_to admin_users_path
    end

    private

    def audit!(auditable, action, comment)
      Audit.create!(auditable:, action:, comment:, user: true_user, audited_changes: {},
                    remote_address: request.remote_ip, request_uuid: request.uuid)
    end
  end
end
