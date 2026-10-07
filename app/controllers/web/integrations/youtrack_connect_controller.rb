# frozen_string_literal: true

# Where a signed-in user approves a pairing that the Aixle Flow app started in
# YouTrack, by typing the code the app shows — the device-authorization pattern,
# so a link someone else sends cannot attach their YouTrack to your project.
# The app sees the approval when it next reads the pairing, and finishes there.
class Web::Integrations::YoutrackConnectController < Web::ApplicationController
  layout "inertia"

  before_action :require_auth
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { current_user.id }

  def show
    render inertia: "Integrations/YoutrackConnect", props: {
      projects: connectable_projects.map { |p| { id: p.id, name: p.name, company_name: p.company.name } }
    }
  end

  def create
    pairing = YoutrackPairing.awaiting_code(params[:code])
    return redirect_to(youtrack_connect_path, alert: "That code is unknown or has expired — start again in YouTrack") unless pairing

    project = connectable_projects.find { |p| p.id == params[:project_id].to_i }
    return redirect_to(youtrack_connect_path, alert: "Choose a project you can connect integrations in") unless project

    pairing.approve!(project: project, user: current_user)
    redirect_to youtrack_connect_path,
                notice: "Approved: #{pairing.instance_url} connects to #{project.name}. Go back to YouTrack to finish."
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def connectable_projects
    @connectable_projects ||= Project.for_user(current_user).includes(:company).order(:name).select do |project|
      Web::Company::Projects::IntegrationsPolicy.new(ProjectContext.new(current_user, {}, project: project), project).create?
    end
  end
end
