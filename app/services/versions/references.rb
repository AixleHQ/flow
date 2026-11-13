# frozen_string_literal: true

module Versions
  # Which live workflows use an entity — the reason archiving it is refused.
  # A workflow that inherits every project resource does not name the entity,
  # so it does not count: archiving simply drops the entity from what it gets.
  module References
    LINK_COLUMNS = { "Tool" => :tool_id, "Skill" => :skill_id, "MCPServer" => :mcp_server_id }.freeze

    module_function

    # [{ workflow: "Release", step: "Build" }, { workflow: "Nightly" }] — empty
    # when nothing live names the entity.
    def usages(record)
      case record
      when Agent then step_usages(live_steps.where(agent_id: record.id))
      when Tool, Skill, MCPServer
        column = LINK_COLUMNS.fetch(record.class.base_class.name)
        step_usages(live_steps.where(id: StepResourceLink.where(column => record.id).select(:step_id))) +
          workflow_usages(Workflow.active.where(id: WorkflowResourceLink.where(column => record.id).select(:workflow_id)))
      else []
      end
    end

    def live_steps
      Step.not_deleted.joins(:workflow).merge(Workflow.active).includes(:workflow).reorder("workflows.name", "steps.position")
    end

    def step_usages(steps)
      steps.map { |step| { workflow: step.workflow.name, step: step.name } }
    end

    def workflow_usages(workflows)
      workflows.order(:name).map { |workflow| { workflow: workflow.name } }
    end
  end
end
