# frozen_string_literal: true

class BoardColumnResource < ApplicationResource
  attributes :id, :name, :position, :purpose, :created_at, :updated_at

  # Active tasks in the column. Served from the `with_tasks_count` GROUP BY when the
  # caller selected it (the board page, which needs a count per column and must not
  # pay an N+1 for it); a lone column falls back to counting itself.
  typelize :number
  attribute :tasks_count do |column|
    column.has_attribute?(:tasks_count) ? column[:tasks_count].to_i : column.board_tasks.active.count
  end

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
