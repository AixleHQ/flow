# frozen_string_literal: true

# Disconnects one app connected to the personal MCP through OAuth.
class Web::Profile::MCPAppsController < Web::ApplicationController
  before_action :require_auth

  def destroy
    grant = current_user.mcp_auth_grants.active.find(params[:id])
    return redirect_to(mcp_profile_path, alert: "Apps cannot be disconnected while impersonating.") if impersonated?

    grant.revoke!
    redirect_to mcp_profile_path, notice: "#{grant.client_name} disconnected"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
