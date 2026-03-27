# frozen_string_literal: true

module InternalTools
  class MetaSetupBoardFromPreset < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      proj = target_project
      return error("No target project available") unless proj

      preset_key = params[:preset]
      return error("Invalid preset: #{preset_key}. Use: simple_kanban, dev_team, full_sdlc") unless BoardPresets.valid?(preset_key)

      existing_board = proj.board
      if existing_board
        if existing_board.board_columns.joins(:board_tasks).distinct.any?
          return error("Board already has columns with tasks. Cannot reset from preset. " \
                       "Use meta_create_board_column to add columns individually.")
        end
        # Remove empty columns and recreate from preset
        existing_board.board_columns.destroy_all
        existing_board.destroy!
      end

      board = Board.create_from_preset(project: proj, preset_key: preset_key)

      broadcast_meta_activity(
        action: "setup_board_from_preset",
        entity_type: "Board",
        entity_name: board.name,
        entity_id: board.id,
        details: { preset: preset_key, columns_count: board.board_columns.count }
      )

      columns = board.board_columns.order(:position).map do |col|
        { id: col.id, name: col.name, position: col.position, purpose: col.purpose }
      end

      success({
        board_id: board.id,
        name: board.name,
        preset: preset_key,
        columns: columns
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to setup board: #{e.message}")
    end
  end
end
