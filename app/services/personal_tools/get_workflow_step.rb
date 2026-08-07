# frozen_string_literal: true

module PersonalTools
  class GetWorkflowStep < Base
    tool do
      display_name "Get Workflow Step"
      description "Return one workflow step in full: the complete, untruncated instructions plus every " \
                  "wiring field (agent, tools, skills, MCP servers, dependencies, BMAD, retries, assets) " \
                  "and its sub-steps. Use this before editing a step — get_workflow truncates instructions."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      step = find_step!(workflow)

      success(id: step.id, workflow_id: workflow.id, name: step.name, position: step.position,
              instructions: step.instructions,
              agent: step.agent && { id: step.agent.id, title: step.agent.title },
              tool_ids: step.tool_ids, skill_ids: step.skill_ids, mcp_server_ids: step.mcp_server_ids,
              depends_on_step_ids: step.depends_on_step_ids,
              bmad_enabled: step.bmad_enabled, allow_non_interactive: step.allow_non_interactive,
              max_retries: step.max_retries, on_failure: step.on_failure.to_s,
              skip_policy: step.skip_policy.to_s, preferred_model: step.preferred_model,
              required_agent_runtime: step.required_agent_runtime,
              mount_repositories: step.mount_repositories,
              input_asset_specs: step.input_asset_specs, output_asset_specs: step.output_asset_specs,
              asset_ids: step.asset_ids,
              sub_steps: sub_steps(step))
    end

    private

    def sub_steps(step)
      step.sub_steps.active.order(:position).map do |ss|
        { id: ss.id, name: ss.name, position: ss.position, required: ss.required,
          instructions: ss.instructions }
      end
    end
  end
end
