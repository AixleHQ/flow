# frozen_string_literal: true

module PersonalTools
  class CreateWorkflowDraft < Base
    tool do
      display_name "Create Workflow Draft"
      description "Open a draft of a workflow — a hidden copy you can edit and test-run while its triggers " \
                  "and board columns keep running the live version. Returns draft_workflow_id: pass it as " \
                  "workflow_id to get_workflow, update_workflow, the step and sub-step tools and " \
                  "trigger_workflow (a test run). Returns the open draft when the workflow already has one. " \
                  "When done, apply_workflow_draft makes it live; discard_workflow_draft drops it."
      audience :user
      tags :workflows
      idempotent
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Id of the live workflow.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      workflow = workflow.draft_of if workflow.draft?
      existing = workflow.open_draft

      draft = WorkflowDrafts.open!(workflow, actor: version_actor)
      success(draft_workflow_id: draft.id, workflow_id: workflow.id, created: existing.nil?,
              based_on_version_number: draft.draft_base_version,
              draft_steps: draft.steps.not_deleted.order(:position).map { |step|
                { id: step.id, name: step.name, live_step_id: step.origin_step_id }
              })
    rescue WorkflowDrafts::Error => e
      error(e.message)
    end
  end
end
