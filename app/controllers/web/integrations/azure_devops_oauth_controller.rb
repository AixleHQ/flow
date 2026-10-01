# frozen_string_literal: true

# Where Microsoft returns an administrator who signed in to connect an Azure
# DevOps organization. The project and the organization come from the signed,
# single-use Oauth::State, which also pins the user; the delegated token is
# held server-side and the dialog resumes with a handle to it.
class Web::Integrations::AzureDevopsOauthController < Web::ApplicationController
  before_action :require_auth
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  def callback
    state = Oauth::State.decode(params[:state])
    unless state && state["provider"] == AzureDevops::AdminSignIn::PROVIDER && state["user_id"] == current_user.id
      return redirect_to(root_path, alert: "Invalid or expired Microsoft sign-in")
    end

    project = Project.for_user(current_user).find_by(id: state["owner_id"])
    return redirect_to(root_path, alert: "Invalid or expired Microsoft sign-in") if project.nil?

    path = company_project_integrations_path(project)
    return redirect_to(path, alert: denied_message) if params[:error].present?

    side = Oauth::State.consume(state["nonce"])
    return redirect_to(path, alert: "This Microsoft sign-in link was already used") if side.nil?
    unless Web::Company::Projects::IntegrationsPolicy.new(ProjectContext.new(current_user, {}, project: project), project).create?
      return redirect_to(path, alert: "You cannot connect integrations in this project")
    end

    context = state["context"].to_h
    credential = AzureDevops::AdminSignIn.exchange!(code: params[:code], tenant_id: context["tenant_id"],
                                                    code_verifier: side["code_verifier"])
    handle = AzureDevops::AdminSignIn.hold(credential, user: current_user, organization: context["organization"])
    redirect_to company_project_integrations_path(project, azure_setup: handle, azure_organization: context["organization"])
  rescue AzureDevops::Error => e
    redirect_to company_project_integrations_path(project), alert: "Microsoft sign-in failed: #{e.message}"
  end

  private

  # Entra sends an error back for a cancel, and for a directory that lets only
  # an administrator consent to applications.
  def denied_message
    if params[:error_description].to_s.include?("AADSTS65001") || params[:error].to_s == "consent_required"
      "Your Microsoft directory lets only an administrator approve Aixle. Ask a Cloud Application Administrator " \
        "to sign in, or connect with a personal access token instead."
    else
      "Microsoft sign-in was cancelled"
    end
  end

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
