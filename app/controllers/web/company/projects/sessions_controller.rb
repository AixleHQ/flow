# frozen_string_literal: true

class Web::Company::Projects::SessionsController < Web::Company::Projects::ApplicationController
  def index
    scope = current_project.terminal_sessions
                           .with_cached_resource_counts
                           .includes(:user, :project,
                                     :tools, :skills, :mcp_servers,
                                     :input_assets, :repositories)
                           .where.not(session_type: "auth_setup")
                           .ransack(q_params)
                           .result
                           .order(created_at: :desc)

    render inertia: "Projects/Sessions/SessionsPage", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h }
      },
      filters: q_params,
      per_page: per_page
    }
  end

  def new
    agents = Agent.visible_for_project(current_project)
    tools = Tool.visible_for_project(current_project)
    skills = Skill.visible_for_project(current_project)
    mcp_servers = MCPServer.visible_for_project(current_project)
    assets = Asset.accessible_from_project(current_project).includes(:versions)
    repositories = Repository.visible_for_project(current_project)

    render inertia: "Projects/Sessions/NewPage", props: {
      project: project_props,
      agents: agents.map { |a| { id: a.id, name: a.title.presence || a.name } },
      tools: tools.map { |t| { id: t.id, name: t.display_name.presence || t.name } },
      skills: skills.map { |s| { id: s.id, name: s.title.presence || s.name } },
      mcp_servers: mcp_servers.map { |m| { id: m.id, name: m.name } },
      assets: assets.map { |a| { id: a.id, name: a.folder.present? ? "#{a.folder}/#{a.name}" : a.name } },
      repositories: repositories.map { |r| { id: r.id, name: r.full_name } },
      agent_models: current_project_membership&.agent_models_for_props || [],
      # Cost is shown on every screen AFTER a session runs and nowhere on the
      # screen where the spend is actually committed. These two numbers put the
      # decision in context: what a session on this runtime has typically cost,
      # and what has already been spent this month.
      cost_hint: session_cost_hint
    }
  end

  def show
    session = current_project.terminal_sessions
                      .includes(:user, :output_assets)
                      .find(params[:id])
    authorize_session_visibility!(session)

    render inertia: "Projects/Sessions/ShowPage", props: {
      project: project_props,
      session: TerminalSessionResource.new(session, params: { viewer: current_user }).to_h,
      cable_stream: inertia_cable_stream(session)
    }
  end
  private

  # Average cost per finished session, per agent runtime, over the last 30 days
  # in this project — plus this user's month-to-date spend across the company.
  def session_cost_hint
    finished = current_project.terminal_sessions
                              .where(state: "finished")
                              .where("terminal_sessions.created_at > ?", 30.days.ago)
                              .where("cost_cents > 0")

    averages = finished.group(:agent_type).average(:cost_cents).transform_values { |c| c.to_f.round }

    {
      avg_cost_cents_by_runtime: averages,
      month_to_date_cents: current_project.terminal_sessions
                                          .where(user_id: current_user.id)
                                          .where("terminal_sessions.created_at >= ?", Time.current.beginning_of_month)
                                          .sum(:cost_cents)
    }
  end
end
