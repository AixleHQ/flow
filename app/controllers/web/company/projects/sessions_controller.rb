# frozen_string_literal: true

class Web::Company::Projects::SessionsController < Web::Company::Projects::ApplicationController
  # The unified Sessions & Runs list. Standalone sessions and workflow runs are
  # one feed here; /workflow_runs redirects to this action.
  def index
    feed = SessionsRunsFeed.new(
      project: current_project,
      viewer: current_user,
      filters: feed_filters,
      type: list_type
    )
    result = feed.page(page: [ (params[:page] || 1).to_i, 1 ].max, limit: per_page)

    render inertia: "Projects/Sessions/SessionsRunsPage", props: {
      project: project_props,
      entries: InertiaRails.scroll(result.pagy) { result.entries.map { |entry| serialize_entry(entry) } },
      filters: feed_filters.merge(type: list_type),
      total: result.pagy.count,
      user_options: feed.user_options,
      # Both create flows are drawers on this page now, so their option lists
      # live here — but only a user who actually opens a drawer pays for them.
      create_options: InertiaRails.optional { create_options }
    }
  end

  def new
    render inertia: "Projects/Sessions/NewPage", props: {
      project: project_props,
      **create_options.except(:workflows)
    }
  end

  def show
    session = current_project.terminal_sessions
                      .includes(:user, :output_assets, step_run: [ :step, { workflow_run: :workflow } ])
                      .find(params[:id])
    authorize_session_visibility!(session)

    render inertia: "Projects/Sessions/ShowPage", props: {
      project: project_props,
      session: TerminalSessionResource.new(session, params: { viewer: current_user }).to_h,
      workflow_context: workflow_context_for(session),
      cable_stream: inertia_cable_stream(session)
    }
  end

  private

  # A workflow-step session shows the run it belongs to in its breadcrumb, and
  # says "Step 2 of 4" instead of "Standalone session". Nil for a standalone.
  def workflow_context_for(session)
    step_run = session.step_run
    return nil if step_run.nil?

    run = step_run.workflow_run
    {
      run_id: run.id,
      run_name: run.workflow&.name,
      run_path: company_project_workflow_run_path(current_project, run),
      step_name: step_run.step&.name,
      step_position: step_run.step&.position,
      steps_total: run.step_runs_count
    }
  end

  def serialize_entry(entry)
    if entry.kind == "session"
      SessionListEntryResource.new(entry.record, params: { viewer: current_user }).to_h
    else
      RunListEntryResource.new(entry.record).to_h
    end
  end

  def list_type
    SessionsRunsFeed::TYPES.include?(params[:type]) ? params[:type] : "all"
  end

  def feed_filters
    {
      search: params[:search].presence,
      agent_type: params[:agent_type].presence,
      status: params[:status].presence,
      user_id: params[:user_id].presence
    }.compact
  end

  def create_options
    agents = Agent.visible_for_project(current_project)
    tools = Tool.visible_for_project(current_project)
    skills = Skill.visible_for_project(current_project)
    mcp_servers = MCPServer.visible_for_project(current_project)
    assets = Asset.accessible_from_project(current_project).includes(:versions)
    repositories = Repository.visible_for_project(current_project)
    config_items = ConfigItem.visible_for_project(current_project)

    {
      agents: agents.map { |a| { id: a.id, name: a.title.presence || a.name } },
      tools: tools.map { |t| { id: t.id, name: t.display_name.presence || t.name } },
      skills: skills.map { |s| { id: s.id, name: s.title.presence || s.name } },
      mcp_servers: mcp_servers.map { |m| { id: m.id, name: m.name } },
      assets: assets.map { |a| { id: a.id, name: a.folder.present? ? "#{a.folder}/#{a.name}" : a.name } },
      repositories: repositories.map { |r| { id: r.id, name: r.full_name } },
      # Names and types only — a config item's value never reaches a prop.
      config_items: config_items.map { |c| ConfigItemPickerResource.new(c).to_h },
      agent_models: current_project_membership&.agent_models_for_props || [],
      configured_agents: current_project_membership&.configured_agents || [],
      default_agent_runtime: current_project_membership&.default_agent_runtime,
      workflows: runnable_workflows,
      # Cost is shown on every screen AFTER a session runs and nowhere on the
      # screen where the spend is actually committed. These two numbers put the
      # decision in context: what a session on this runtime has typically cost,
      # and what has already been spent this month.
      cost_hint: session_cost_hint
    }
  end

  # The Run Workflow drawer needs each workflow's steps to render the Custom
  # execution mode, so the list is shallow-serialized with them.
  def runnable_workflows
    Workflow.visible_for_project(current_project).includes(:steps).map do |workflow|
      WorkflowResource.new(workflow).to_h.merge(
        steps: workflow.steps.not_deleted.map { |s| StepResource.new(s).to_h }
      )
    end
  end

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
