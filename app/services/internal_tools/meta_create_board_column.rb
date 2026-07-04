# frozen_string_literal: true

module InternalTools
  class MetaCreateBoardColumn < Base
    tool do
      display_name "Meta Create Board Column"
      description "Create a new column on the project board."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[name],
        properties: {
          name: {
            type: "string",
            description: "Column name"
          },
          purpose: {
            type: "string",
            description: "What this column represents"
          },
          position: {
            type: "integer",
            description: "Position (auto-assigned if omitted)"
          }
        }
      })
    end

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
