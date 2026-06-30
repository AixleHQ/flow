# frozen_string_literal: true

class BoardColumnResource < ApplicationResource
  attributes :id, :name, :position, :purpose, :created_at, :updated_at

  typelize "{ id: number; workflow_id: number; workflow_name: string | null; trigger_mode: \"auto\" | \"manual\"; cooldown_seconds: number } | null"
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
