# frozen_string_literal: true

# The unified "Sessions & Runs" list.
#
# Standalone agent sessions and workflow runs used to live on two pages with two
# controllers, two filter sets and two orderings, and there was no way to see
# "what did this project run yesterday" in one place. This builds one feed of
# both, newest first, with workflow-step sessions folded UNDER their run instead
# of competing with it for a top-level row.
#
# Ordering has to happen in SQL across both tables (you cannot paginate a feed
# you sorted in Ruby), so the spine is a UNION ALL of (id, kind, created_at).
# The page of ids that comes back is then hydrated with the associations each
# kind needs, and re-ordered to match.
class SessionsRunsFeed
  # Standalone sessions only — a workflow_step session appears nested under its
  # run, and auth/tool setup sessions are plumbing the user never asked for.
  TOP_LEVEL_SESSION_TYPES = %w[agent_session].freeze

  # One status vocabulary over two state machines. A session is "finished" where
  # a run is "completed"; asking a user to know that is asking them to know our
  # schema.
  # A run whose step is waiting for a session slot is itself `running` — queueing
  # is a property of the child, not of the run — so this side cannot be a state
  # list like the others. QUEUED_STEP asks the question the state cannot.
  QUEUED_STEP = :queued_step

  STATUS_FILTERS = {
    "queued" => { sessions: %w[queued], runs: QUEUED_STEP },
    "running" => { sessions: %w[running ready finishing], runs: %w[running] },
    "completed" => { sessions: %w[finished], runs: %w[completed] },
    "failed" => { sessions: %w[failed], runs: %w[failed] },
    "cancelled" => { sessions: %w[cancelled], runs: %w[cancelled] },
    "pending" => { sessions: %w[not_started], runs: %w[pending paused] }
  }.freeze

  TYPES = %w[all run solo].freeze

  Page = Struct.new(:pagy, :entries, keyword_init: true)

  # One row of the feed. `record` is a TerminalSession or a WorkflowRun.
  Entry = Struct.new(:kind, :record, keyword_init: true)

  def initialize(project:, viewer:, filters: {}, type: "all")
    @project = project
    @viewer = viewer
    @filters = filters.to_h.symbolize_keys
    @type = TYPES.include?(type.to_s) ? type.to_s : "all"
  end

  attr_reader :project, :viewer, :filters, :type

  # Returns a Page whose `entries` are already hydrated and ordered.
  def page(page: 1, limit: 20)
    pagy = Pagy::Offset.new(count: spine.count(:all), page: page, limit: limit)
    rows = spine.offset(pagy.offset).limit(pagy.limit)

    Page.new(pagy: pagy, entries: hydrate(rows))
  end

  # Distinct users who own something in this project's feed — the User filter's
  # options. Members who never ran anything would only be noise.
  def user_options
    ids = TerminalSession.where(project: project, session_type: TOP_LEVEL_SESSION_TYPES).distinct.pluck(:user_id) |
      WorkflowRun.where(project: project).distinct.pluck(:user_id)
    User.where(id: ids.compact).order(:name).map { |u| { id: u.id, name: u.name.presence || u.email } }
  end

  private

  # The ordered (id, kind) spine, as a real relation so pagination is AR's job
  # and no SQL is assembled by string interpolation.
  #
  # TerminalSession is only the query carrier — `from` replaces its table
  # entirely, and the two selected aliases are the only attributes the returned
  # objects have. Nothing but `entry_id`/`entry_kind` may be read off them.
  def spine
    relation = TerminalSession.unscoped
                              .select("feed.entry_id", "feed.entry_kind")
                              .from(feed_alias)
    relation.order(Arel.sql("feed.entry_created_at DESC, feed.entry_id DESC"))
  end

  def feed_alias
    Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(union_node), Arel.sql("feed"))
  end

  def union_node
    return sessions_spine.arel if type == "solo"
    return runs_spine.arel if type == "run"

    Arel::Nodes::UnionAll.new(sessions_spine.arel, runs_spine.arel)
  end

  def sessions_spine
    filtered_sessions.reselect(
      "terminal_sessions.id AS entry_id",
      "'session' AS entry_kind",
      "terminal_sessions.created_at AS entry_created_at"
    )
  end

  def runs_spine
    filtered_runs.reselect(
      "workflow_runs.id AS entry_id",
      "'run' AS entry_kind",
      "workflow_runs.created_at AS entry_created_at"
    ).distinct
  end

  def filtered_sessions
    scope = TerminalSession.where(project: project, session_type: TOP_LEVEL_SESSION_TYPES)
    scope = scope.where(agent_type: filters[:agent_type]) if filters[:agent_type].present?
    scope = scope.where(user_id: filters[:user_id]) if filters[:user_id].present?
    if (states = status_states(:sessions))
      scope = states.empty? ? scope.none : scope.where(state: states)
    end
    if filters[:search].present?
      scope = scope.where("terminal_sessions.initial_prompt ILIKE :q", q: "%#{sanitize_like(filters[:search])}%")
                   .merge(viewer_visible_scope)
    end
    scope
  end

  # Search matches on `initial_prompt` — a field the row itself may not be
  # allowed to reveal (see TerminalSession#visible_to?). Without this, a
  # private session whose hidden prompt matches someone else's search term
  # would still surface in their results, leaking that the prompt matched.
  IN_FLIGHT_STATES = %w[not_started queued running ready finishing].freeze

  def viewer_visible_scope
    TerminalSession.joins(:user).where(user_id: viewer.id).or(
      TerminalSession.joins(:user).where(
        "(terminal_sessions.state IN (:in_flight) AND users.share_active_sessions = TRUE) " \
        "OR (terminal_sessions.state NOT IN (:in_flight) AND users.share_completed_sessions = TRUE)",
        in_flight: IN_FLIGHT_STATES
      )
    )
  end

  def filtered_runs
    scope = WorkflowRun.where(project: project)
    scope = scope.where(user_id: filters[:user_id]) if filters[:user_id].present?
    states = status_states(:runs)
    if states == QUEUED_STEP
      scope = scope.where(id: runs_with_queued_step)
    elsif states
      scope = states.empty? ? scope.none : scope.where(state: states)
    end
    if filters[:agent_type].present?
      scope = scope.joins(step_runs: :terminal_session)
                   .where(terminal_sessions: { agent_type: filters[:agent_type] })
    end
    if filters[:search].present?
      scope = scope.joins(:workflow).where("workflows.name ILIKE :q", q: "%#{sanitize_like(filters[:search])}%")
    end
    scope
  end

  def runs_with_queued_step
    WorkflowRun.joins(step_runs: :terminal_session)
               .where(terminal_sessions: { state: "queued" })
               .select(:id)
  end

  # nil means "no status filter"; [] means "this side of the union matches
  # nothing" (e.g. Cancelled, which sessions do not have).
  def status_states(side)
    return nil if filters[:status].blank?

    STATUS_FILTERS.dig(filters[:status].to_s, side) || []
  end

  def sanitize_like(value)
    value.to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end

  def hydrate(rows)
    rows = rows.to_a
    session_ids = rows.select { |r| r.entry_kind == "session" }.map(&:entry_id)
    run_ids = rows.select { |r| r.entry_kind == "run" }.map(&:entry_id)

    sessions = TerminalSession.where(id: session_ids).includes(:user, :project).index_by(&:id)
    runs = WorkflowRun.where(id: run_ids)
                      .includes(:user, :workflow, step_runs: [ :step, { terminal_session: :user } ])
                      .index_by(&:id)

    rows.filter_map do |row|
      record = row.entry_kind == "session" ? sessions[row.entry_id] : runs[row.entry_id]
      next if record.nil?

      Entry.new(kind: row.entry_kind, record: record)
    end
  end
end
