# frozen_string_literal: true

module PersonalTools
  class GetWorkflow < Base
    tool do
      display_name "Get Workflow"
      description "Return a workflow's full definition: base resources, steps, sub-steps, agents, " \
                  "dependencies. Step and sub-step instructions come back complete — use " \
                  "get_workflow_step for one step's remaining wiring (retries, failure and skip " \
                  "policy, preferred model, asset specs)."
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

      steps = workflow.steps.not_deleted.includes(:agent).order(:position).map { |step| step_view(step) }
      success(id: workflow.id, name: workflow.name, description: workflow.description,
              published_at: workflow.published_at,
              base_tool_ids: workflow.base_tool_ids, base_skill_ids: workflow.base_skill_ids,
              base_mcp_server_ids: workflow.base_mcp_server_ids,
              base_repository_ids: workflow.base_repository_ids,
              base_config_item_ids: workflow.base_config_item_ids,
              base_asset_ids: workflow.base_asset_ids,
              inherit_all_project_resources: workflow.inherit_all_project_resources,
              steps_count: steps.size, steps: steps)
    end

    private

    # Instructions are returned whole. They used to be cut at 500 characters,
    # which is shorter than almost every real step: a caller that read a
    # workflow and then wrote a step back silently dropped the tail it never
    # saw. Size is the caller's problem to manage (read one workflow at a
    # time), not a reason to hand back text that looks complete and isn't.
    def step_view(step)
      { id: step.id, name: step.name, position: step.position,
        instructions: step.instructions,
        agent: step.agent && { id: step.agent.id, title: step.agent.title },
        tool_ids: step.tool_ids, skill_ids: step.skill_ids, mcp_server_ids: step.mcp_server_ids,
        repository_ids: step.repository_ids,
        depends_on_step_ids: step.depends_on_step_ids,
        sub_steps: step.sub_steps.active.order(:position).map { |ss|
          { id: ss.id, name: ss.name, position: ss.position, required: ss.required,
            instructions: ss.instructions }
        } }
    end
  end
end
