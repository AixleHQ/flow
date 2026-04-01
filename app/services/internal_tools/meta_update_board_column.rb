# frozen_string_literal: true

module InternalTools
  class MetaUpdateBoardColumn < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      column = BoardColumn.find(params[:column_id])

      attrs = {}
      attrs[:name] = params[:name] if params.key?(:name)
      attrs[:purpose] = params[:purpose] if params.key?(:purpose)
      attrs[:position] = params[:position] if params.key?(:position)

      column.update!(attrs)

      broadcast_meta_activity(
        action: "updated_board_column",
        entity_type: "BoardColumn",
        entity_name: column.name,
        entity_id: column.id,
        details: { updated_fields: attrs.keys.map(&:to_s) }
      )

      success({ id: column.id, name: column.name, position: column.position, purpose: column.purpose }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Column not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update column: #{e.message}")
    end
  end
end
