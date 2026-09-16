# frozen_string_literal: true

module PersonalTools
  class ListWorkflowTriggers < Base
    include WorkflowTriggerSupport

    tool do
      display_name "List Workflow Triggers"
      description "List everything that can launch a workflow: board-column bindings plus " \
                  "Slack / schedule / webhook / custom-event triggers. Pass the returned id " \
                  "together with its kind to update_workflow_trigger or delete_workflow_trigger — " \
                  "the two kinds are separate records and their ids can collide. " \
                  "created_by is who added the trigger; the off-board kinds fire unattended as " \
                  "that user and are skipped entirely when it is null."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      triggers = column_bindings(project, workflow).includes(:board_column, :created_by).map { |t| serialize_column(t) } +
                 workflow.trigger_bindings.includes(:created_by).order(:created_at).map { |t| serialize_binding(t) }
      success(project_id: project.id, workflow_id: workflow.id, triggers: triggers)
    end
  end
end
