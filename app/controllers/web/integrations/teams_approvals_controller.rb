# frozen_string_literal: true

# Where a Microsoft 365 administrator approves connecting their organization to
# an Aixle workspace (docs/design/teams-integration.md §6.2). Opening it needs no
# Aixle account: the approval link is the credential, and the decision is made by
# signing in with Microsoft as a directory administrator.
class Web::Integrations::TeamsApprovalsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_workspace
  skip_before_action :enforce_onboarding
  skip_before_action :enforce_company_auth_policy
  skip_before_action :redirect_super_admin_to_admin_panel

  def show
    integration = Teams::Connection.find_by_token(params[:token])
    return render inertia: "Integrations/TeamsApproval", props: { state: "expired" } if integration.nil?

    # The Microsoft sign-in comes back to one fixed callback; this is how it
    # finds the link it was started from.
    session[:teams_approval_token] = params[:token]
    settings = integration.settings.to_h
    render inertia: "Integrations/TeamsApproval", props: {
      state: integration.active? ? "connected" : "pending",
      workspace: integration.company.name,
      requested_by: { name: integration.connected_by&.name, email: integration.connected_by&.email },
      organization: settings["tenant_domain"].presence || settings["tenant_id"],
      approved_by: settings.dig("approved_by", "name"),
      file_access: settings["file_access"],
      # Published to the organization's Teams apps during the approval, or why not.
      published: settings["catalog_published_at"].present?,
      publish_error: settings["catalog_error"],
      sign_in_url: teams_approval_sign_in_path(params[:token]),
      file_access_url: teams_approval_file_access_path(params[:token]),
      package_url: teams_approval_package_path(params[:token])
    }
  end

  def sign_in
    integration = Teams::Connection.find_by_token(params[:token])
    return redirect_to(teams_approval_path(params[:token])) if integration.nil?

    # allow_other_host: Microsoft's authorize URL, built from configuration only.
    redirect_to Teams::Connection.authorize_url(integration, with_files: params[:files] != "0"), allow_other_host: true
  end

  def callback
    state = Oauth::State.decode(params[:state])
    return redirect_to(back, alert: "This Microsoft sign-in link is invalid or has expired") unless state&.dig("provider") == "teams"
    return redirect_to(back, alert: "Microsoft sign-in was cancelled") if params[:error].present?

    side = Oauth::State.consume(state["nonce"])
    return redirect_to(back, alert: "This Microsoft sign-in link was already used") if side.nil?

    integration = linked_integration(state)
    return redirect_to(back, alert: "Open the approval link again and sign in from there") if integration.nil?

    Teams::Connection.complete!(integration: integration, code: params[:code], code_verifier: side["code_verifier"],
                                with_files: state.dig("context", "files") == true)
    redirect_to back, notice: "Connected. Your organization's Teams can now start #{integration.company.name} workflows."
  rescue Teams::Connection::Refused, Teams::Error => e
    redirect_to back, alert: e.message
  end

  def file_access
    integration = Teams::Connection.find_by_token(params[:token])
    return redirect_to(teams_approval_path(params[:token])) unless integration&.active?

    redirect_to Teams::Connection.file_access_url(integration), allow_other_host: true
  end

  def file_access_callback
    state = Oauth::State.decode(params[:state])
    return redirect_to(back, alert: "This consent link is invalid or has expired") unless state&.dig("provider") == "teams_file_access"

    integration = linked_integration(state)
    return redirect_to(back, alert: "Open the approval link again and grant access from there") if integration.nil?
    return redirect_to(back, alert: "File access was not granted") if params[:error].present?

    if Teams::Connection.confirm_file_access!(integration)
      redirect_to back, notice: "File access granted"
    else
      redirect_to back, alert: "Microsoft has not granted file access to Aixle yet. Try again in a minute."
    end
  rescue Teams::Error => e
    redirect_to back, alert: e.message
  end

  def package
    integration = Teams::Connection.find_by_token(params[:token])
    return redirect_to(teams_approval_path(params[:token])) unless integration&.active?

    send_data Teams::AppPackage.zip, filename: Teams::AppPackage.filename, type: "application/zip"
  end

  private

  # A sign-in counts only for the connection whose approval link this browser
  # opened: the signed state names it, and the session holds that link.
  def linked_integration(state)
    integration = Teams::Connection.find_by_token(session[:teams_approval_token])
    integration if integration && state["owner_type"] == "Integration" && state["owner_id"] == integration.id
  end

  def back
    token = session[:teams_approval_token]
    token.present? ? teams_approval_path(token) : root_path
  end
end
