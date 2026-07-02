# frozen_string_literal: true

module InternalTools
  class MetaDeleteBoardColumn < Base
    tool do
      display_name "Meta Delete Board Column"
      description "Delete an empty board column. Fails if column has tasks."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[column_id],
        properties: {
          column_id: {
            type: "integer"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

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
