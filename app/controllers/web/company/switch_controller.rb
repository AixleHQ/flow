# frozen_string_literal: true

# POST /company/switch — the company switcher. The target company is validated
# against the user's ACTIVE memberships; a non-member company_id 404s and leaves
# the session untouched.
class Web::Company::SwitchController < Web::Company::ApplicationController
  allow_viewer_writes

  def create
    membership = current_user.company_memberships.active.find_by!(company_id: params[:company_id])
    session[:current_company_id] = membership.company_id
    reset_membership_memoization

    # Open sockets were identified under the previous company; drop them so
    # they re-authenticate (and re-subscribe) under the new one.
    disconnect_cables

    redirect_to company_projects_path(company_slug: membership.company.slug)
  end

  private

  def disconnect_cables
    ActionCable.server.remote_connections.where(current_user: current_user).disconnect
  rescue StandardError => e
    Rails.logger.warn("[CompanySwitch] Failed to disconnect cables for user #{current_user.id}: #{e.message}")
  end
end
