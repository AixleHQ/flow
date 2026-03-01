# frozen_string_literal: true

class BoardColumnSerializer < ApplicationSerializer
  attributes :id, :name, :position, :purpose, :workflow_binding, :created_at, :updated_at

  def workflow_binding
    binding = object.column_workflow_binding
    return nil unless binding

    {
      workflow_id: binding.workflow_id,
      workflow_name: binding.workflow.name,
      trigger_mode: binding.trigger_mode,
      cooldown_seconds: binding.cooldown_seconds
    }
  end
end
