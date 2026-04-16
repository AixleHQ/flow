# frozen_string_literal: true

class Web::Company::Projects::SessionsController < Web::Company::Projects::ApplicationController
  def index
    scope = current_project.terminal_sessions
                           .includes(:user, :project, :output_assets)
                           .where.not(session_type: "auth_setup")
                           .ransack(q_params)
                           .result
                           .order(created_at: :desc)

    render inertia: "Projects/Sessions/SessionsPage", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s).to_h }
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
    assets = current_project.assets.active.includes(:versions)
    repositories = Repository.visible_for_project(current_project)

    render inertia: "Projects/Sessions/NewPage", props: {
      project: project_props,
      agents: agents.map { |a| { id: a.id, name: a.title.presence || a.name } },
      tools: tools.map { |t| { id: t.id, name: t.display_name.presence || t.name } },
      skills: skills.map { |s| { id: s.id, name: s.title.presence || s.name } },
      mcp_servers: mcp_servers.map { |m| { id: m.id, name: m.display_name.presence || m.name } },
      assets: assets.map { |a| { id: a.id, name: a.folder.present? ? "#{a.folder}/#{a.name}" : a.name } },
      repositories: repositories.map { |r| { id: r.id, name: r.full_name } },
      agent_models: current_user.agent_models_for_props
    }
  end

  def show
    session = current_project.terminal_sessions
                      .includes(:user, :output_assets)
                      .find(params[:id])

    render inertia: "Projects/Sessions/ShowPage", props: {
      project: project_props,
      session: TerminalSessionResource.new(session).to_h,
      cable_stream: inertia_cable_stream(session)
    }
  end
end
