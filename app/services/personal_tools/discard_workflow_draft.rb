# frozen_string_literal: true

module PersonalTools
  class DiscardWorkflowDraft < Base
    tool do
      display_name "Discard Workflow Draft"
      description "Close a workflow's open draft without applying it. The live workflow stays as it is; " \
                  "the draft's test runs are kept."
      audience :user
      tags :workflows
      destructive
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Id of the live workflow (or of its draft).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      draft = workflow.draft? ? workflow : workflow.open_draft
      return error("Workflow #{workflow.id} has no open draft") unless draft

      workflow = draft.draft_of

      WorkflowDrafts.discard!(draft, actor: version_actor)
      success(workflow_id: workflow.id, discarded_draft_workflow_id: draft.id)
    end
  end
end
