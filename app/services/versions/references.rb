# frozen_string_literal: true

module Versions
  # Which live workflows use an entity — the reason archiving it is refused.
  # A workflow that inherits every project resource does not name the entity,
  # so it does not count: archiving simply drops the entity from what it gets.
  module References
    STEP_COLUMNS = { "Tool" => "tool_ids", "Skill" => "skill_ids", "MCPServer" => "mcp_server_ids" }.freeze
    CONFIG_KEYS = { "Tool" => "base_tool_ids", "Skill" => "base_skill_ids", "MCPServer" => "base_mcp_server_ids" }.freeze

    module_function

    # [{ workflow: "Release", step: "Build" }, { workflow: "Nightly" }] — empty
    # when nothing live names the entity.
    def usages(record)
      case record
      when Agent then step_usages(live_steps.where(agent_id: record.id))
      when Tool, Skill, MCPServer
        type = record.class.base_class.name
        step_usages(live_steps.where(contains_id(STEP_COLUMNS.fetch(type)), *id_forms(record.id))) +
          config_usages(record, CONFIG_KEYS.fetch(type))
      else []
      end
    end

    def live_steps
      Step.not_deleted.joins(:workflow).merge(Workflow.active).includes(:workflow).reorder("workflows.name", "steps.position")
    end

    def step_usages(steps)
      steps.map { |step| { workflow: step.workflow.name, step: step.name } }
    end

    def config_usages(record, key)
      as_number, as_string = id_forms(record.id)
      Workflow.active.where("config -> ? @> ?::jsonb OR config -> ? @> ?::jsonb", key, as_number, key, as_string)
              .order(:name).map { |workflow| { workflow: workflow.name } }
    end

    # Id lists hold integers, but older writes stored them as strings.
    def contains_id(column)
      "steps.#{column} @> ?::jsonb OR steps.#{column} @> ?::jsonb"
    end

    def id_forms(id)
      [ [ id ].to_json, [ id.to_s ].to_json ]
    end
  end
end
