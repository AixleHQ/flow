# frozen_string_literal: true

module InternalTools
  class MetaReorderBoardColumns < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      board = target_project&.board
      return error("Project has no board") unless board

      column_ids = params[:column_ids]
      return error("column_ids is required and must be an array") unless column_ids.is_a?(Array)

      ActiveRecord::Base.transaction do
        column_ids.each_with_index do |id, idx|
          col = board.board_columns.find(id)
          col.update_column(:position, idx + 1)
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
