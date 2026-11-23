# frozen_string_literal: true

module PersonalTools
  class ApplyWorkflowDraft < Base
    tool do
      display_name "Apply Workflow Draft"
      description "Make a workflow's open draft live: the draft is written onto the workflow as one new " \
                  "version, its triggers and board columns run it from then on, and the draft is closed. " \
                  "Refused when the live workflow changed after the draft was made, unless overwrite is true. " \
                  "Show the user get_workflow_draft_diff and ask before applying."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Id of the live workflow (or of its draft).", required: true
      param :overwrite, type: :boolean,
            description: "Apply even though the live workflow changed after the draft was made, replacing " \
                         "those changes. Only with the user's say-so."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      draft = workflow.draft? ? workflow : workflow.open_draft
      return error("Workflow #{workflow.id} has no open draft") unless draft

      workflow = draft.draft_of

      version = WorkflowDrafts.apply!(draft, actor: version_actor, overwrite: params[:overwrite] == true)
      success(workflow_id: workflow.id, current_version_number: workflow.reload.current_version_number,
              version_created: version.present?, closed_draft_workflow_id: draft.id)
    rescue WorkflowDrafts::Error, WorkflowAggregateSave::Invalid => e
      error(e.message)
    end
  end
end
