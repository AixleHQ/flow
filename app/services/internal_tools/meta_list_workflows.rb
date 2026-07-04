# frozen_string_literal: true

module InternalTools
  class MetaListWorkflows < Base
    tool do
      display_name "Meta List Workflows"
      description "List all workflows visible for the target project (project + company scope)."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {
          project_id: {
            type: "integer",
            description: "Project ID. Defaults to current project."
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      workflows = Workflow.visible_for_project(proj).map do |wf|
        {
          id: wf.id,
          name: wf.name,
          description: wf.description,
          scope_type: wf.scope_type,
          steps_count: wf.steps.not_deleted.count
        }
      end

      success({
        project_id: proj.id,
        project_name: proj.name,
        workflows_count: workflows.size,
        workflows: workflows
      }.to_json)
    end
  end
end
