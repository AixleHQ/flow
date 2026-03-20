# frozen_string_literal: true

class StepSerializer < ApplicationSerializer
  attributes :id, :workflow_id, :agent_id, :position, :name, :description,
             :instructions, :allow_non_interactive, :skip_policy, :on_failure,
             :max_retries, :input_asset_specs, :output_asset_specs,
             :tool_ids, :mcp_server_ids, :skill_ids,
             :mount_repositories, :depends_on_step_ids, :required_agent_runtime,
             :created_at, :updated_at

  has_many :sub_steps, serializer: SubStepSerializer

  def sub_steps
    object.sub_steps.active
  end
end
