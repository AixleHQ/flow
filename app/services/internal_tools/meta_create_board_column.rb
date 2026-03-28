# frozen_string_literal: true

module InternalTools
  class MetaCreateBoardColumn < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      board = target_project&.board
      return error("Project has no board") unless board

      column = board.board_columns.create!(
        name: params[:name],
        purpose: params[:purpose],
        position: params[:position] # auto-assigned if nil via model callback
      )

      broadcast_meta_activity(
        action: "created_board_column",
        entity_type: "BoardColumn",
        entity_name: column.name,
        entity_id: column.id,
        details: { position: column.position }
      )

      success({ id: column.id, name: column.name, position: column.position, purpose: column.purpose }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create board column: #{e.message}")
    end
  end
end
