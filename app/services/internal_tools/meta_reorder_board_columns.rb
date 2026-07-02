# frozen_string_literal: true

module InternalTools
  class MetaReorderBoardColumns < Base
    tool do
      display_name "Meta Reorder Board Columns"
      description "Reorder all board columns by providing ordered column IDs."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[column_ids],
        properties: {
          column_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Ordered column IDs"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      board = target_project&.board
      return error("Project has no board") unless board

      column_ids = params[:column_ids]
      return error("column_ids is required and must be an array") unless column_ids.is_a?(Array)

      ActiveRecord::Base.transaction do
        # Two-pass write: park positions past the current range first so the
        # unique (board_id, position) index can't collide mid-reorder, then set
        # final positions. Mirrors Api::V1::Projects::Board::ColumnsController#reorder.
        offset = board.board_columns.count + 1
        column_ids.each_with_index do |id, idx|
          board.board_columns.find(id).update_column(:position, offset + idx + 1)
        end
        column_ids.each_with_index do |id, idx|
          board.board_columns.find(id).update_column(:position, idx + 1)
        end
      end

      broadcast_meta_activity(
        action: "reordered_board_columns",
        entity_type: "Board",
        entity_name: board.name,
        entity_id: board.id,
        details: { new_order: column_ids }
      )

      success({ board_id: board.id, new_order: column_ids }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Column not found: #{e.message}")
    end
  end
end
