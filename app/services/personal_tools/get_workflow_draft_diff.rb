# frozen_string_literal: true

module PersonalTools
  class GetWorkflowDraftDiff < Base
    tool do
      display_name "Get Workflow Draft Diff"
      description "What applying a workflow's open draft would change on the live workflow: changed fields " \
                  "with before and after values, and steps and sub-steps added, removed or changed. Also " \
                  "says whether the live workflow changed after the draft was made — applying then replaces " \
                  "those changes too."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Id of the live workflow (or of its draft).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      draft = workflow.draft? ? workflow : workflow.open_draft
      return error("Workflow #{workflow.id} has no open draft") unless draft

      changes = WorkflowDrafts.changes(draft)
      success(draft_workflow_id: draft.id,
              live_version_number: changes[:live_version_number],
              based_on_version_number: changes[:base_version_number],
              live_changed_since_draft: changes[:live_version_number] != changes[:base_version_number],
              changes: WorkflowDrafts::ChangeSummary.call(changes[:live], changes[:draft]))
    rescue WorkflowDrafts::Error => e
      error(e.message)
    end
  end
end
