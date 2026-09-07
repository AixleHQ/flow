# frozen_string_literal: true

module InternalTools
  class SessionList < Base
    include Concerns::SessionScope

    tool do
      display_name "Session List"
      description "List the other agent sessions running in this project — what else is working " \
                  "right now, which workflow run and step each one belongs to, and what it has " \
                  "cost so far. Newest first, active ones by default. Pair with session_log to " \
                  "find out whether one of them is working or wedged. Scoped to this session's " \
                  "own project; sessions their owner keeps private are not listed."
      tags :session_supervision
      read_only
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

    # `visible_to?` is filtered in Ruby (see Concerns::SessionScope), so read a
    # bounded candidate window rather than the whole project's history, and say
    # so when the window is what ended the listing.
    MAX_CANDIDATES = 500

    def execute
      state = (params[:state].presence || "active").to_s
      unless state == "all" || STATE_FILTERS.key?(state)
        return error("Unknown state '#{state}' — use one of: active, finished, failed, all")
      end

      limit = requested_limit
      candidates = scope(state).limit(MAX_CANDIDATES).to_a
      visible = supervision_visible(candidates).first(limit)

      success({
        state: state,
        project_id: session.project_id,
        count: visible.size,
        candidates_capped: candidates.size == MAX_CANDIDATES,
        sessions: visible.map { |record| row(record) }
      }.to_json)
    end

    private

    def requested_limit
      requested = params[:limit].present? ? params[:limit].to_i : DEFAULT_LIMIT
      requested.clamp(1, MAX_LIMIT)
    end

    def scope(state)
      scope = supervision_scope.includes(:user).order(created_at: :desc)
      scope = scope.where(state: STATE_FILTERS.fetch(state)) unless state == "all"
      scope
    end

    # `metadata` is deliberately not returned wholesale — it carries prompts and
    # context blobs. Only the workflow linkage is useful for finding a run.
    def row(record)
      metadata = record.metadata || {}
      {
        id: record.id,
        state: record.state,
        queued_at: record.queued_at,
        wait_reason: record.session_admission&.wait_reason,
        session_type: record.session_type,
        agent_type: record.agent_type,
        mode: record.mode,
        self: record.id == session.id,
        owner: record.user&.email,
        workflow_run_id: metadata["workflow_run_id"],
        step_run_id: metadata["step_run_id"],
        step_name: metadata["step_name"],
        created_at: record.created_at,
        started_at: record.started_at,
        ready_at: record.ready_at,
        finished_at: record.finished_at,
        error_message: record.error_message,
        total_tokens: record.total_tokens,
        cost_cents: record.cost_cents
      }
    end
  end
end
