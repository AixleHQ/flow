# frozen_string_literal: true

module PersonalTools
  class DuplicateWorkflow < Base
    tool do
      display_name "Duplicate Workflow"
      description "Copy a workflow — steps, sub-steps and their wiring — into the same or another project. " \
                  "Returns the new workflow plus a needs_setup list: secrets, assets, repositories and " \
                  "integrations are never copied and must be set up manually in the target project."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id the source workflow lives in.", required: true
      param :workflow_id, type: :integer, description: "Workflow id to copy.", required: true
      param :name, type: :string,
            description: "Name for the copy; defaults to the source name with a numeric suffix."
      param :target_project_id, type: :integer,
            description: "Project to copy into; defaults to the source project."
    end

    def execute
      project = find_project!
      authorize!(project, :duplicate?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      target = target_project(project)
      # Copying into another project writes there, so it needs write access there too.
      authorize!(target, :duplicate?, policy: Web::Company::Projects::WorkflowsPolicy, project: target) unless target == project

      duplicator = WorkflowDuplicator.new(workflow, target_scope: target, name: params[:name].presence)
      copy = duplicator.duplicate!

      success(id: copy.id, name: copy.name, project_id: target.id,
              source_workflow_id: workflow.id, steps_count: copy.steps.not_deleted.count,
              needs_setup: duplicator.summary&.dig(:needs_setup) || [])
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to duplicate workflow: #{e.message}")
    end

    private

    def target_project(source)
      id = params[:target_project_id]
      return source if id.blank? || id.to_i == source.id

      find_project!(id)
    end
  end
end
