# frozen_string_literal: true

module PersonalTools
  class GetWorkflow < Base
    tool do
      display_name "Get Workflow"
      description "Return a workflow's full definition: steps, sub-steps, agents, dependencies."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = Workflow.visible_for_project(project).find_by(id: params[:workflow_id])
      return error("Workflow not found in this project") unless workflow

      steps = workflow.steps.not_deleted.includes(:agent).order(:position).map do |step|
        { id: step.id, name: step.name, position: step.position,
          instructions: step.instructions&.truncate(500),
          agent: step.agent && { id: step.agent.id, title: step.agent.title },
          tool_ids: step.tool_ids, skill_ids: step.skill_ids, mcp_server_ids: step.mcp_server_ids,
          depends_on_step_ids: step.depends_on_step_ids,
          sub_steps: step.sub_steps.active.order(:position).map { |ss|
            { id: ss.id, name: ss.name, position: ss.position, required: ss.required,
              instructions: ss.instructions&.truncate(500) }
          } }
      end
      success(id: workflow.id, name: workflow.name, description: workflow.description,
              steps_count: steps.size, steps: steps)
    end
  end
end
