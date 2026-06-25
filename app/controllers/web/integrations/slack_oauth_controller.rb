# frozen_string_literal: true

# Deployment-wide Slack OAuth callback. One redirect URI is registered on the
# Slack app; the project being connected is carried in a signed, single-use
# `state`, and we only ever bind the install to a project the current user can
# access. The state also pins the initiating user (anti-CSRF) and is consumed once.
class Web::Integrations::SlackOauthController < Web::ApplicationController
  before_action :require_auth
  # The OAuth return must land here even for super-admins (who are otherwise
  # bounced to the admin panel on every web request).
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  def callback
    state = Slack::Oauth.verify_state(params[:state])
    return redirect_to(root_path, alert: "Invalid or expired Slack authorization") if state.nil?
    return redirect_to(root_path, alert: "Slack authorization did not match your session") unless state["user_id"] == current_user.id

    project = resolve_project(state)
    return redirect_to(root_path, alert: "Invalid or expired Slack authorization") if project.nil?

    path = company_project_integrations_path(project)
    # On cancel, leave the nonce intact so the user can retry within the TTL.
    return redirect_to(path, alert: "Slack connection was cancelled") if params[:error].present?
    # Single use: reject a replayed/already-consumed authorization link.
    return redirect_to(path, alert: "This Slack authorization link was already used") unless Slack::Oauth.consume_state_nonce(state["nonce"])

    integration = Slack::IntegrationService.new(
      company: project.company, connected_by: current_user, project: project
    ).create_from_oauth(code: params[:code].to_s)

    if integration.active?
      redirect_to path, notice: "Slack connected to #{integration.name}"
    else
      redirect_to path, alert: integration.settings&.dig("error") || "Failed to connect Slack"
    end
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # Bind only to a project the signed state names AND the user can access.
  def resolve_project(state)
    return nil if state.blank?

    Project.for_user(current_user).find_by(id: state["project_id"])
  end
end
