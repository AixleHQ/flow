# frozen_string_literal: true

module PersonalTools
  class GetStepRun < Base
    tool do
      display_name "Get Step Run"
      description "Return one step run in full: state, timings, retry count, error " \
                  "category/message/history, skip reason and note, plus its terminal session's " \
                  "state, error and context metadata (where the BMAD install status lands). " \
                  "This is the tool for diagnosing a step that failed instead of just seeing " \
                  "that it did — get_workflow_run only reports states."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :step_run_id, type: :integer, description: "Step run id, from get_workflow_run.", required: true
    end

    # Diagnostics, not a log stream: a step's error text can carry a whole
    # container tail, and error_history grows one entry per retry.
    TEXT_LIMIT = 4_000
    HISTORY_LIMIT = 10

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      step_run = find_step_run(project)
      return error("Step run not found in this project") unless step_run

      success(step_run_payload(step_run).merge(terminal_session: session_payload(step_run.terminal_session)))
    end

    private

    # Scoped through the project's own workflow runs — never a global
    # StepRun.find, which would reach another company's run by id.
    def find_step_run(project)
      StepRun.where(workflow_run_id: WorkflowRun.where(project: project).select(:id))
             .includes(:step, :terminal_session)
             .find_by(id: params[:step_run_id])
    end

    def step_run_payload(step_run)
      history = Array(step_run.error_history)
      { id: step_run.id, workflow_run_id: step_run.workflow_run_id,
        step_id: step_run.step_id, step: step_run.step&.name, step_position: step_run.step&.position,
        state: step_run.state, started_at: step_run.started_at, completed_at: step_run.completed_at,
        retry_count: step_run.retry_count,
        error_category: step_run.error_category,
        error_message: truncate(step_run.error_message),
        error_history: history.last(HISTORY_LIMIT),
        error_history_omitted: [ history.size - HISTORY_LIMIT, 0 ].max,
        skip_reason: step_run.skip_reason,
        step_note: truncate(step_run.step_note) }
    end

    # The container's own side of the failure: a step run that dies in seconds
    # usually failed before it ran anything, and the reason sits here —
    # context_metadata carries bmad_install_status / bmad_install_error.
    def session_payload(session)
      return nil unless session

      { id: session.id, state: session.state, session_type: session.session_type,
        agent_type: session.agent_type, started_at: session.started_at, finished_at: session.finished_at,
        error_message: truncate(session.error_message), context_metadata: session.context_metadata }
    end

    def truncate(text)
      return text if text.blank? || text.length <= TEXT_LIMIT

      "#{text[0, TEXT_LIMIT]}... [truncated, #{text.length} chars total]"
    end
  end
end
