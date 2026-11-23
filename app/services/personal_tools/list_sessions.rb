# frozen_string_literal: true

module PersonalTools
  class ListSessions < Base
    include SessionListSupport

    STATE_FILTERS = {
      "active" => %w[not_started queued running ready finishing],
      "pending" => %w[not_started],
      "queued" => %w[queued],
      "running" => %w[running ready finishing],
      "finished" => %w[finished],
      "failed" => %w[failed],
      "cancelled" => %w[cancelled],
      "all" => nil
    }.freeze
    SESSION_TYPES = TerminalSession::WORK_SESSION_TYPES
    TOKEN_COLUMNS = %w[total_tokens input_tokens output_tokens cache_read_tokens cache_write_tokens cost_cents].freeze

    tool do
      display_name "List Sessions"
      description "List agent sessions you can see — your own, plus sessions in projects you can " \
                  "reach whose owner shares them — one page at a time, with the filters and sort " \
                  "of the Sessions & Runs list. Active sessions, newest first, unless you ask " \
                  "otherwise: for a period's sessions pass state `all` with created_from / " \
                  "created_until. The response carries `total`, `has_more` and `totals` — tokens " \
                  "and cost summed over every matching session, not just this page. Pair with " \
                  "get_session_log to find out what one of them is actually doing."
      audience :user
      tags :sessions
      read_only
      param :company_id, type: :integer, description: "Only sessions in this company (ids from list_companies)."
      param :project_id, type: :integer, description: "Only sessions in this project."
      param :state, type: :string,
                    description: "Which sessions to list (default active). `pending`, `queued`, `running`, " \
                                 "`finished` (Completed), `failed` and `cancelled` are the Sessions & Runs " \
                                 "status filter; `active` is the first three together.",
                    enum: STATE_FILTERS.keys
      param :session_type, type: :string,
                           description: "Only this kind: `agent_session` (started by a person) or " \
                                        "`workflow_step` (a step of a workflow run). Default: both.",
                           enum: SESSION_TYPES
      param :agent_type, type: :string, description: "Only sessions on this agent runtime, e.g. `claude_code`."
      param :user_id, type: :integer, description: "Only sessions this user owns (a row's `owner_id`)."
      param :workflow_id, type: :integer, description: "Only the step sessions of this workflow's runs."
      param :search, type: :string, description: "Words from the prompt the session was started with."
      SessionListSupport.declare_params(self, "sessions")
    end

    def execute
      state = (params[:state].presence || "active").to_s
      refusal = list_param_refusal(state: [ state, STATE_FILTERS.keys ],
                                   session_type: [ params[:session_type], SESSION_TYPES ])
      return error(refusal) if refusal
      if params[:company_id].present? && membership_company_ids.exclude?(params[:company_id].to_i)
        raise NotFoundError, "Company #{params[:company_id]} not found"
      end

      project = params[:project_id].present? ? find_project! : nil
      sessions = filtered(project, state)
      sort = requested_sort
      total, *sums = sessions.pick(Arel.sql("COUNT(*)"),
                                   *TOKEN_COLUMNS.map { |c| Arel.sql("COALESCE(SUM(terminal_sessions.#{c}), 0)") })
      page = sessions.includes(:user, :session_admission)
                     .order(sort.order(sort.column(TerminalSession)), created_at: :desc, id: :desc)
                     .limit(requested_limit).offset(requested_offset).to_a

      success(
        state: state,
        project_id: project&.id,
        **page_fields(total: total, rows: page, sort: sort),
        totals: TOKEN_COLUMNS.zip(sums.map(&:to_i)).to_h,
        sessions: page.map { |session| row(session) }
      )
    end

    private

    def filtered(project, state)
      scope = readable_sessions.visible_to(user)
                               .created_from(params[:created_from])
                               .created_until(params[:created_until])
      scope = scope.where(project_id: project.id) if project
      scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
      scope = scope.where(state: STATE_FILTERS.fetch(state)) if STATE_FILTERS.fetch(state)
      scope = scope.where(session_type: params[:session_type].presence || SESSION_TYPES)
      scope = scope.where(agent_type: params[:agent_type]) if params[:agent_type].present?
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
      if params[:workflow_id].present?
        steps = StepRun.joins(:workflow_run).where(workflow_runs: { workflow_id: params[:workflow_id] })
        scope = scope.where(id: steps.select(:terminal_session_id))
      end
      if params[:search].present?
        like = "%#{params[:search].to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
        scope = scope.where("terminal_sessions.initial_prompt ILIKE ?", like)
      end
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
        models: session.models,
        mode: session.mode,
        mine: session.user_id == user.id,
        owner_id: session.user_id,
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
        **TOKEN_COLUMNS.to_h { |column| [ column.to_sym, session[column] ] }
      }
    end
  end
end
