# frozen_string_literal: true

module InternalTools
  class MetaGetBoard < Base
    tool do
      display_name "Meta Get Board"
      description "Get the project board with columns, purposes, task counts, and workflow bindings."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {}
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      board = proj&.board
      return error("Project has no board") unless board

      columns = board.board_columns.order(:position).includes(:column_workflow_binding).map do |col|
        binding = col.column_workflow_binding
        {
          id: col.id,
          name: col.name,
          position: col.position,
          purpose: col.purpose,
          tasks_count: col.board_tasks.count,
          workflow_binding: binding ? {
            id: binding.id,
            workflow_id: binding.workflow_id,
            workflow_name: binding.workflow.name,
            trigger_mode: binding.trigger_mode,
            cooldown_seconds: binding.cooldown_seconds
          } : nil
        }
      end

      success({
        board_id: board.id,
        name: board.name,
        preset_origin: board.preset_origin,
        columns_count: columns.size,
        columns: columns
      }.to_json)
    end
  end
end
