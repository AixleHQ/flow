# frozen_string_literal: true

class Web::Company::SessionsController < Web::Company::ApplicationController
  # Company-wide "Sessions & Runs" list. Same name, filter bar and row visual
  # system as the project Sessions & Runs page, plus a Project column. Unlike
  # the project feed this stays session-level: a workflow step is its own row,
  # never folded under a parent run.
  LIST_SESSION_TYPES = %w[agent_session workflow_step].freeze

  # In-flight states, for the visibility-scoped search below.
  SEARCH_IN_FLIGHT_STATES = %w[not_started queued running ready finishing].freeze

  def index
    base = filtered_scope

    scope = base.with_cached_resource_counts
              .includes(:user, :project, :session_admission,
                        :tools, :skills, :mcp_servers, :config_items,
                        :input_assets, :repositories)
              .order(created_at: :desc)

    render inertia: "Company/Sessions/Index", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h }
      },
      filters: feed_filters.merge(type: list_type),
      total: base.count,
      user_options: user_options
    }
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
      user_id: params[:user_id].presence
    }.compact
  end

  def filtered_scope
    scope = company_sessions_scope.where(session_type: type_session_types)

    scope = scope.where(agent_type: params[:agent_type]) if params[:agent_type].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

    if params[:status].present?
      states = SessionsRunsFeed::STATUS_FILTERS.dig(params[:status].to_s, :sessions)
      scope = states.blank? ? scope.none : scope.where(state: states)
    end

    if params[:search].present?
      like = "%#{params[:search].to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
      scope = scope.where("terminal_sessions.initial_prompt ILIKE ?", like).merge(search_visible_scope)
    end

    scope
  end

  # "Workflow runs" on this page means workflow-step sessions — the page is not
  # a grouped runs feed.
  def type_session_types
    case list_type
    when "run" then %w[workflow_step]
    when "solo" then %w[agent_session]
    else LIST_SESSION_TYPES
    end
  end

  # Search matches on `initial_prompt`, a field the row itself may not be allowed
  # to reveal (TerminalSession#visible_to?). Without this a private session whose
  # hidden prompt matched someone's term would still surface, leaking the match.
  # Same shape as SessionsRunsFeed#viewer_visible_scope, company-wide.
  def search_visible_scope
    own = TerminalSession.joins(:user).where(terminal_sessions: { user_id: current_user.id })
    steps = TerminalSession.joins(:user).where(terminal_sessions: { session_type: "workflow_step" })
    shared = TerminalSession.joins(:user).where(
      "(terminal_sessions.state IN (:in_flight) AND users.share_active_sessions = TRUE) " \
      "OR (terminal_sessions.state NOT IN (:in_flight) AND users.share_completed_sessions = TRUE)",
      in_flight: SEARCH_IN_FLIGHT_STATES
    )
    own.or(steps).or(shared)
  end

  # Distinct users who own a session in this company's list — the User filter's
  # options. Members who never ran anything would only be noise.
  def user_options
    ids = company_sessions_scope.where(session_type: LIST_SESSION_TYPES).distinct.pluck(:user_id)
    User.where(id: ids.compact).order(:name).map { |u| { id: u.id, name: u.name.presence || u.email } }
  end
end
