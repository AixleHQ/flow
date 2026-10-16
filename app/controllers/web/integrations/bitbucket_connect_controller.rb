# frozen_string_literal: true

# Where a signed-in user confirms the Connect a Bitbucket workspace
# administrator started on the Aixle Flow settings page
# (docs/design/bitbucket-integration.md §5.5). The link carries the pairing in
# its fragment, so the page reads it and sends it here in request bodies.
class Web::Integrations::BitbucketConnectController < Web::ApplicationController
  # Set by Web::Company::Projects::BitbucketInstallationsController when a
  # project's Connect needs the app installed first.
  PROJECT_SESSION_KEY = :bitbucket_connect_project_id
  UNKNOWN = "This link is unknown, already used or expired. Start again from Workspace settings → Aixle Flow in Bitbucket."

  layout "inertia"

  before_action :require_auth, except: :show
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  rate_limit to: 30, within: 10.minutes, only: %i[preview create], by: -> { current_user.id }

  # A guest gets the page too: it keeps the pairing from the link's fragment in
  # the tab and sends them to sign in, and the sign-in comes back here. A
  # redirect would lose the pairing — the fragment does not survive sign-in.
  def show
    unless signed_in?
      remember_pending_bitbucket_connect
      return render inertia: "Integrations/BitbucketConnect",
                    props: { signed_in: false, login_url: login_path, projects: [], preselected_project_id: nil }
    end

    projects = connectable_projects
    remembered = session[PROJECT_SESSION_KEY].to_i
    render inertia: "Integrations/BitbucketConnect", props: {
      signed_in: true, login_url: login_path,
      projects: projects.map { |p| { id: p.id, name: p.name, company_name: p.company.name } },
      preselected_project_id: projects.any? { |p| p.id == remembered } ? remembered : nil
    }
  end

  def preview
    pairing = open_pairing
    return render(status: :not_found, json: { error: "not_found", message: UNKNOWN }) unless pairing

    installation = pairing.bitbucket_installation
    render json: {
      workspace: { slug: installation.workspace_slug, name: installation.workspace_name },
      expires_at: pairing.expires_at.iso8601,
      bound_elsewhere: installation.bound? && connectable_projects.none? { |p| p.company_id == installation.company_id }
    }
  end

  def create
    pairing = open_pairing
    return render(status: :not_found, json: { error: "not_found", message: UNKNOWN }) unless pairing

    project = connectable_projects.find { |p| p.id == params[:project_id].to_i }
    unless project
      return render(status: :unprocessable_content,
                    json: { error: "validation_failed", message: "Choose a project you can connect integrations in" })
    end

    integration = Bitbucket::Forge::Pairing.confirm!(pairing: pairing, user: current_user, project: project)
    session.delete(PROJECT_SESSION_KEY)
    flash[:notice] = "Bitbucket workspace #{integration.name} is connected to #{project.name}."
    render json: { redirect_url: company_project_integrations_path(project) }
  rescue Bitbucket::Forge::Pairing::Refused, Bitbucket::Error => e
    render status: :unprocessable_content, json: { error: e.code, message: e.message }
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def open_pairing = BitbucketPairing.open(params[:pairing_id], params[:pairing_secret])

  def connectable_projects
    @connectable_projects ||= Project.for_user(current_user).includes(:company).order(:name).select do |project|
      Web::Company::Projects::IntegrationsPolicy.new(ProjectContext.new(current_user, {}, project: project), project).create?
    end
  end
end
