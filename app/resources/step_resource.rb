# frozen_string_literal: true

class StepResource < ApplicationResource
  attributes :id, :name, :description, :instructions, :position,
             :allow_non_interactive, :skip_policy, :on_failure, :max_retries,
             :mount_repositories, :bmad_enabled, :preferred_model,
             :depends_on_step_ids, :created_at, :updated_at

  attribute :input_asset_specs do |step|
    val = step.input_asset_specs
    val.is_a?(String) ? JSON.parse(val) : (val || [])
  end

  attribute :output_asset_specs do |step|
    val = step.output_asset_specs
    val.is_a?(String) ? JSON.parse(val) : (val || [])
  end

  attribute :agent_id do |step|
    step.agent_id
  end

  attribute :required_agent_runtime do |step|
    step.required_agent_runtime
  end

  attribute :tool_ids do |step|
    step.tool_ids || []
  end

  attribute :mcp_server_ids do |step|
    step.mcp_server_ids || []
  end

  attribute :skill_ids do |step|
    step.skill_ids || []
  end

  attribute :sub_steps do |step|
    step.sub_steps.select { |ss| ss.deleted_at.nil? }.map do |ss|
      SubStepResource.new(ss).to_h
    end
  end
end
