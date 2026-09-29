# frozen_string_literal: true

module PersonalTools
  class DeleteSubStep < Base
    tool do
      display_name "Delete Sub-Step"
      description "Delete a sub-step (checklist item) from a workflow step. A sub-step that already has " \
                  "runs is soft-deleted so past run history stays readable."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
      param :sub_step_id, type: :integer, description: "Sub-step id (from get_workflow_step).", required: true
      param :base_version, type: :integer, description: "The workflow version you read (current_version_number). A newer one means someone else saved since, and the change is refused."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      step = find_step!(workflow)
      sub_step = find_sub_step!(step)

      name = sub_step.name
      Versions.save!(workflow, actor: version_actor, base_version: base_version) { sub_step.destroy }
      success(deleted_sub_step_id: sub_step.id, name: name, step_id: step.id,
              soft_deleted: sub_step.deleted?)
    end
  end
end
