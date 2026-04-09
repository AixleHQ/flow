# frozen_string_literal: true

class BoardColumnResource < ApplicationResource
  attributes :id, :name, :position, :purpose, :created_at, :updated_at

  attribute :workflow_binding do |column|
    binding = column.column_workflow_binding
    if binding
      {
        id: binding.id,
        workflow_id: binding.workflow_id,
        workflow_name: binding.workflow&.name,
        trigger_mode: binding.trigger_mode,
        cooldown_seconds: binding.cooldown_seconds
      }
    end
  end
end
