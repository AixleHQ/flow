# frozen_string_literal: true

module PersonalTools
  class ListWorkflowRuns < Base
    include SessionListSupport

    STATES = (SessionsRunsFeed::STATUS_FILTERS.reject { |_, f| f[:runs] == [] }.keys + %w[all]).freeze

    tool do
      display_name "List Workflow Runs"
      description "List a project's workflow runs one page at a time, with the filters and sort of " \
                  "the Sessions & Runs list. Newest first unless you ask otherwise. Each row carries " \
                  "the run's tokens and cost, summed over its step sessions; list_sessions with " \
                  "workflow_id lists those sessions themselves."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Filter to one workflow id."
      param :state, type: :string,
                    description: "The Sessions & Runs status filter (default all). `queued` is a run " \
                                 "waiting for a session slot for one of its steps; `pending` takes paused runs too.",
                    enum: STATES
      param :user_id, type: :integer, description: "Only runs started by this user (a row's `user_id`)."
      param :agent_type, type: :string, description: "Only runs with a step on this agent runtime, e.g. `claude_code`."
      param :search, type: :string, description: "Words from the workflow's name."
      SessionListSupport.declare_params(self, "runs")
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      state = (params[:state].presence || "all").to_s
      refusal = list_param_refusal(state: [ state, STATES ])
      return error(refusal) if refusal

      feed = SessionsRunsFeed.new(project: project, viewer: user, type: "run", filters: filters(state),
                                  query: { s: requested_sort.to_s, created_from: params[:created_from],
                                           created_until: params[:created_until] }.compact_blank)
      total = feed.count
      runs = feed.entries(offset: requested_offset, limit: requested_limit).map(&:record)

      success(project_id: project.id, state: state, **page_fields(total: total, rows: runs, sort: feed.sort),
              runs: runs.map { |run| row(run) })
    end

    private

    def filters(state)
      { workflow_id: params[:workflow_id], user_id: params[:user_id], agent_type: params[:agent_type],
        search: params[:search], status: (state unless state == "all") }.compact_blank
    end

    def row(run)
      step_runs = RunListEntryResource.ordered_step_runs(run)
      sessions = step_runs.filter_map(&:terminal_session)
      { id: run.id, workflow_id: run.workflow_id, workflow_name: run.workflow&.name,
        state: run.displayed_state, source: run.source, mode: run.mode,
        user_id: run.user_id, user: run.user&.email, team: run.picked_from_team&.name,
        agent_type: sessions.first&.agent_type,
        steps_completed: step_runs.count(&:completed?), steps_total: run.step_runs_count,
        total_tokens: sessions.sum(&:total_tokens), cost_cents: sessions.sum(&:cost_cents),
        started_at: run.started_at, execution_started_at: run.execution_started_at,
        completed_at: run.completed_at, created_at: run.created_at }
    end
  end
end
