# frozen_string_literal: true

# Deployment-wide callback of Aixle's GitLab OAuth app (docs/design/gitlab-tracker.md
# §4). The project comes from the signed, single-use Oauth::State, which also
# pins the initiating user and holds the PKCE verifier; the connection is bound
# only to a project that user can reach. The person's token is kept only until
# they pick the group for the service account.
class Web::Integrations::GitlabOauthController < Web::ApplicationController
  before_action :require_auth
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  def callback
    state = Oauth::State.decode(params[:state])
    unless state && state["provider"] == Gitlab::Oauth::PROVIDER && state["user_id"] == current_user.id
      return redirect_to(root_path, alert: "Invalid or expired GitLab authorization")
    end

    project = Project.for_user(current_user).find_by(id: state["owner_id"])
    return redirect_to(root_path, alert: "Invalid or expired GitLab authorization") if project.nil?

    path = company_project_integrations_path(project)
    # A cancel leaves the nonce alone, so the person can try again.
    return redirect_to(path, alert: "GitLab connection was cancelled") if params[:error].present?

    side = Oauth::State.consume(state["nonce"])
    return redirect_to(path, alert: "This GitLab authorization link was already used") if side.nil?
    unless Web::Company::Projects::IntegrationsPolicy.new(ProjectContext.new(current_user, {}, project: project), project).create?
      return redirect_to(path, alert: "You cannot connect integrations in this project")
    end

    integration = Gitlab::IntegrationService.new(company: project.company, connected_by: current_user, project: project)
                                            .connect_oauth(code: params[:code].to_s, code_verifier: side["code_verifier"])
    redirect_to company_project_integrations_path(project, gitlab_setup: integration.id),
                notice: "Pick the GitLab group for Aixle's service account"
  rescue Gitlab::IntegrationService::ConnectionError => e
    redirect_to company_project_integrations_path(project), alert: "GitLab connection failed: #{e.message}"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
