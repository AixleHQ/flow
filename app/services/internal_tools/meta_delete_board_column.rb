# frozen_string_literal: true

module InternalTools
  class MetaDeleteBoardColumn < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      column = BoardColumn.find(params[:column_id])

      if column.board_tasks.any?
        return error("Cannot delete column '#{column.name}' — it has #{column.board_tasks.count} tasks. Move them first.")
      end

      name = column.name
      column.destroy!

      broadcast_meta_activity(
        action: "deleted_board_column",
        entity_type: "BoardColumn",
        entity_name: name,
        entity_id: params[:column_id]
      )

      success({ deleted: true, column_name: name }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Column not found: #{e.message}")
    end
  end
end
