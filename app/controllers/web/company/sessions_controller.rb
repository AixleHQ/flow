# frozen_string_literal: true

class Web::Company::SessionsController < Web::Company::ApplicationController
  def index
    scope = company_sessions_scope
              .includes(:user, :project, :output_assets)
              .where.not(session_type: "auth_setup")
              .ransack(q_params)
              .result
              .order(created_at: :desc)

    render inertia: "Company/Sessions/Index", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s).to_h }
      },
      filters: q_params,
      per_page: per_page
    }
  end

  def new
    projects = current_company.projects.with_state(:active).order(:name)
    agents = Agent.belonging_to_company(current_company)
    tools = Tool.visible_for_company(current_company)
    skills = Skill.visible_for_company(current_company)
    mcp_servers = MCPServer.visible_for_company(current_company)
    assets = current_company.assets.active
    repositories = Repository.visible_for_company(current_company)

    render inertia: "Company/Sessions/New", props: {
      projects: projects.map { |p| { id: p.id, name: p.name } },
      pre_selected_project_id: params[:projectId]&.to_i,
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
    session = company_sessions_scope
                .includes(:user, :project, :output_assets)
                .find(params[:id])

    session_props = TerminalSessionResource.new(session).to_h

    render inertia: "Company/Sessions/Show", props: {
      session: session_props,
      cable_stream: inertia_cable_stream(session)
    }
  end
end
