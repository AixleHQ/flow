# frozen_string_literal: true

module PersonalTools
  class ListSessions < Base
    tool do
      display_name "List Sessions"
      description "List agent sessions you can see — your own, plus sessions in projects you can " \
                  "reach whose owner shares them. Newest first, active ones by default. Pair with " \
                  "get_session_log to find out what one of them is actually doing."
      audience :user
      tags :sessions
      read_only
      param :project_id, type: :integer, description: "Only sessions in this project."
      param :state, type: :string, description: "Which sessions to list (default active).",
                    enum: %w[active finished failed all]
      param :limit, type: :integer, description: "Max rows (default 25, cap 100)."
    end

    STATE_FILTERS = {
      "active" => %w[not_started queued running ready finishing],
      "finished" => %w[finished],
      "failed" => %w[failed]
    }.freeze

    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100

    # `visible_to?` cannot be expressed in SQL (it depends on the owner's
    # preferences per lifecycle phase), so rows are filtered in Ruby. Read a
    # bounded candidate window rather than the whole table, and say so when the
    # window is what ended the listing.
    MAX_CANDIDATES = 500

    def execute
      project = params[:project_id].present? ? find_project! : nil
      state = (params[:state].presence || "active").to_s
      unless state == "all" || STATE_FILTERS.key?(state)
        return error("Unknown state '#{state}' — use one of: active, finished, failed, all")
      end

      limit = requested_limit
      candidates = scope(project, state).limit(MAX_CANDIDATES).to_a
      visible = candidates.select { |session| session.visible_to?(user) }

      success(
        state: state,
        project_id: project&.id,
        count: visible.first(limit).size,
        candidates_capped: candidates.size == MAX_CANDIDATES,
        sessions: visible.first(limit).map { |session| row(session) }
      )
    end

    private

    def requested_limit
      requested = params[:limit].present? ? params[:limit].to_i : DEFAULT_LIMIT
      requested.clamp(1, MAX_LIMIT)
    end

    def scope(project, state)
      scope = TerminalSession.readable_by(user).includes(:user).order(created_at: :desc)
      scope = scope.where(project_id: project.id) if project
      scope = scope.where(state: STATE_FILTERS.fetch(state)) unless state == "all"
      scope
    end

    # `metadata` is deliberately not returned wholesale — it carries prompts and
    # context blobs. Only the workflow linkage is useful for finding a run.
    def row(session)
      metadata = session.metadata || {}
      {
        id: session.id,
        state: session.state,
        queued_at: session.queued_at,
        wait_reason: session.session_admission&.wait_reason,
        session_type: session.session_type,
        agent_type: session.agent_type,
        mode: session.mode,
        mine: session.user_id == user.id,
        owner: session.user&.email,
        project_id: session.project_id,
        workflow_run_id: metadata["workflow_run_id"],
        step_run_id: metadata["step_run_id"],
        step_name: metadata["step_name"],
        created_at: session.created_at,
        started_at: session.started_at,
        ready_at: session.ready_at,
        finished_at: session.finished_at,
        error_message: session.error_message,
        total_tokens: session.total_tokens,
        cost_cents: session.cost_cents
      }
    end
  end
end
