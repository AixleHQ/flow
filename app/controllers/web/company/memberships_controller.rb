# frozen_string_literal: true

# Self-removal ("Leave company"): a user revokes their OWN membership — in any
# of their companies, including the current one. The policy is self-only;
# removing OTHER members lives in Web::Company::MembersController#destroy.
class Web::Company::MembershipsController < Web::Company::ApplicationController
  def destroy
    # Revoke is legal from invited/active/suspended — a SUSPENDED member must
    # still be able to leave (`.active.find` would 404 them forever).
    membership = current_user.company_memberships.where.not(state: "revoked").find(params[:id])
    membership.aasm(:state).fire(:revoke) if membership.may_revoke?

    if membership.revoked? && membership.save
      reset_membership_memoization
      redirect_after_leave(membership)
    else
      # Last-admin guard (and any other validation) surfaces as a flash alert.
      redirect_to profile_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  # Leaving the current company is allowed: on the next request AuthConcern
  # falls back to another active membership and persists it as "last used".
  # With no memberships left (and no super-admin bit), the user is signed out.
  def redirect_after_leave(membership)
    notice = "You left #{membership.company.name}"

    if current_user.company_memberships.active.exists? || current_user.super_admin?
      redirect_to profile_path, notice: notice
    else
      sign_out
      redirect_to login_path, notice: "#{notice}. You no longer belong to any company."
    end
  end
end
