# frozen_string_literal: true

# Company-wide "Sessions & Runs" list. Same name, filter bar and row visual
# system as the project Sessions & Runs page, plus a Project column. Unlike the
# project feed this stays session-level: a workflow step is its own row, never
# folded under a parent run — TerminalSession.work_sessions.
class Web::Company::SessionsController < Web::Company::ApplicationController
  include SessionListQuery

  ROWS_LIMIT = 100

  def index
    base = filtered_scope
    sort = SessionListSort.new(list_query[:s])

    scope = base.with_cached_resource_counts
              .includes(:user, :project, :session_admission,
                        :tools, :skills, :mcp_servers, :config_items,
                        :input_assets, :repositories, :runner)
              .order(sort.order(sort.column(TerminalSession)), created_at: :desc, id: :desc)

    render inertia: "Company/Sessions/Index", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h }
      },
      filters: feed_filters.merge(type: list_type),
      query: list_query.merge(s: sort.to_s),
      total: base.count,
      user_options: user_options,
      project_options: project_options,
      cable_stream: inertia_cable_stream(current_company, :sessions)
    }
  end

  # The rows a live list asks back for after an update signal. Every member may
  # read these: the member pages already list each member's sessions to the
  # whole company, redacted per viewer exactly as here.
  def rows
    ids = Array(params[:ids]).map(&:to_i).uniq.first(ROWS_LIMIT)
    sessions = company_sessions_scope.work_sessions.where(id: ids)
                                     .with_cached_resource_counts
                                     .includes(:user, :project, :session_admission,
                                               :tools, :skills, :mcp_servers, :config_items,
                                               :input_assets, :repositories, :runner)

    render json: { sessions: sessions.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h } }
  end

  def show
    session = company_sessions_scope.with_cached_resource_counts
                .includes(:user, :project, :session_admission,
                          :tools, :skills, :mcp_servers, :config_items,
                          :input_assets, :repositories)
                .find(params[:id])
    authorize_session_visibility!(session)

    session_props = TerminalSessionResource.new(session, params: { viewer: current_user }).to_h

    render inertia: "Company/Sessions/Show", props: {
      session: session_props,
      cable_stream: inertia_cable_stream(session)
    }
  end

  private

  def list_type
    %w[all run solo].include?(params[:type]) ? params[:type] : "all"
  end

  def feed_filters
    {
      search: params[:search].presence,
      agent_type: params[:agent_type].presence,
      status: params[:status].presence,
      user_id: params[:user_id].presence,
      project_id: params[:project_id].presence
    }.compact
  end

  def filtered_scope
    scope = type_sessions_scope.ransack(list_query.except(:s)).result

    scope = scope.where(agent_type: params[:agent_type]) if params[:agent_type].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?

    if params[:status].present?
      states = SessionsRunsFeed::STATUS_FILTERS.dig(params[:status].to_s, :sessions)
      scope = states.blank? ? scope.none : scope.where(state: states)
    end

    if params[:search].present?
      like = "%#{params[:search].to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
      # The prompt may be one the row cannot reveal; matching it would leak the match.
      scope = scope.where("terminal_sessions.initial_prompt ILIKE ?", like).visible_to(current_user)
    end

    scope
  end

  # "Workflow runs" on this page means workflow-step sessions — the page is not
  # a grouped runs feed.
  def type_sessions_scope
    case list_type
    when "run" then company_sessions_scope.workflow_steps
    when "solo" then company_sessions_scope.agent_sessions
    else company_sessions_scope.work_sessions
    end
  end

  # Distinct users who own a session in this company's list — the User filter's
  # options. Members who never ran anything would only be noise.
  def user_options
    ids = company_sessions_scope.work_sessions
                                .distinct.pluck(:user_id)
    User.where(id: ids.compact).order(:name).map { |u| { id: u.id, name: u.name.presence || u.email } }
  end

  # Projects with a session in this company's list — the Project filter's
  # options, named as the rows already name them.
  def project_options
    ids = company_sessions_scope.work_sessions
                                .distinct.select(:project_id)
    Project.where(id: ids).order(:name).map { |p| { id: p.id, name: p.name } }
  end
end
