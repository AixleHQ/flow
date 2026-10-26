# frozen_string_literal: true

module PersonalTools
  class TriggerWorkflow < Base
    tool do
      display_name "Trigger Workflow"
      description "Start a run of a workflow in a project. Returns the run id and state."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :mode, type: :string, description: "Run mode: interactive or non_interactive.", enum: %w[interactive non_interactive]
      param :idempotency_key, type: :string,
            description: "Any string unique to this launch, such as a UUID you generate once. Calling again with the " \
                         "same key returns the run the first call started instead of starting another, so pass it " \
                         "when you retry after a timeout or an error. Up to 255 characters."
    end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      workflow = Workflow.visible_for_project(project).find_by(id: params[:workflow_id])
      return error("Workflow not found in this project") unless workflow

      key = params[:idempotency_key].presence
      earlier = key && WorkflowRun.find_by(user: user, idempotency_key: key)
      return replay(earlier, workflow, project) if earlier

      begin
        run = WorkflowService.start(
          workflow: workflow, project: project, user: user, source: :mcp, idempotency_key: key,
          mode: (params[:mode].presence || "interactive").to_sym
        )
      rescue ActiveRecord::RecordNotUnique
        raise unless key

        return replay(WorkflowRun.find_by!(user: user, idempotency_key: key), workflow, project)
      end
      return error("Could not start run: #{run.errors.full_messages.to_sentence}") unless run.persisted?

      success(run_id: run.id, workflow_id: workflow.id, state: run.state)
    end

    private

    def replay(run, workflow, project)
      unless run.workflow_id == workflow.id && run.project_id == project.id
        return error("idempotency_key already started run #{run.id} of another workflow or project; use a new key")
      end

      success(run_id: run.id, workflow_id: run.workflow_id, state: run.state, replayed: true)
    end
  end
end
