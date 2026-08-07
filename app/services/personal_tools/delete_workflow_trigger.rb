# frozen_string_literal: true

module PersonalTools
  class DeleteWorkflowTrigger < Base
    include WorkflowTriggerSupport

    tool do
      display_name "Delete Workflow Trigger"
      description "Remove a trigger from a workflow — the workflow itself is untouched. Pass its " \
                  "kind together with trigger_id: column triggers and event triggers are separate " \
                  "records whose ids can collide. Deleting a schedule trigger also removes its " \
                  "Temporal schedule."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :trigger_id, type: :integer, description: "Trigger id (from list_workflow_triggers).", required: true
      param :kind, type: :string, enum: WorkflowTriggerSupport::KINDS, required: true,
                   description: "The trigger's kind, as reported by list_workflow_triggers."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      kind = params[:kind].to_s

      trigger =
        if kind == "column"
          find_column_trigger!(project, workflow, params[:trigger_id])
        else
          find_event_trigger!(workflow, params[:trigger_id])
        end

      trigger.destroy!
      success(deleted_trigger_id: trigger.id, kind: kind, workflow_id: workflow.id)
    end
  end
end
