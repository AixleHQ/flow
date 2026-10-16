# frozen_string_literal: true

# A project's "Install the app" path (docs/design/bitbucket-integration.md §5.5).
# The user names the workspace; one this company has already bound connects at
# once. Anything else needs a workspace administrator in Bitbucket, and the
# answer is the same whether or not the workspace is bound elsewhere: the
# company's bound workspaces are never listed or confirmed to project members.
class Web::Company::Projects::BitbucketInstallationsController < Web::Company::Projects::ApplicationController
  def create
    return render(status: :not_found, json: { error: "unavailable", message: "Bitbucket app mode is not configured here" }) unless
      Bitbucket::AppConfig.app_mode_enabled?

    installation = bound_installation(params[:workspace].to_s)
    unless installation
      session[Web::Integrations::BitbucketConnectController::PROJECT_SESSION_KEY] = current_project.id
      return render json: { install_required: true, install_url: Bitbucket::AppConfig.forge_install_url }
    end

    integration = Bitbucket::Forge::Connection.connect!(installation: installation, project: current_project, user: current_user)
    render json: { connected: true, integration_id: integration.id, name: integration.name }
  rescue Bitbucket::Error => e
    render status: :unprocessable_content, json: { error: e.code, message: e.message }
  end

  private

  def bound_installation(workspace)
    slug = workspace.strip.delete_prefix("#{Bitbucket::AppConfig::WEB_HOST}/").split("/").first.to_s.downcase
    return if slug.blank?

    BitbucketInstallation.with_status(:active).bound_to(current_company).find_by("LOWER(workspace_slug) = ?", slug)
  end
end
