# frozen_string_literal: true

module PersonalTools
  class ReorderBoardColumns < Base
    tool do
      display_name "Reorder Board Columns"
      description "Set board column order by passing column ids in the desired order. Requires project-admin (owner)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_ids, type: :array, description: "Column ids in new order.", required: true, items: { type: "integer" }
    end

    def execute
      project = find_project!
      authorize!(project.board, :reorder?, policy: Web::Company::Projects::Board::ColumnsPolicy, project: project)
      board = project.board
      return error("This project has no board") unless board

      ids = params[:column_ids]
      return error("column_ids must be a non-empty array") unless ids.is_a?(Array) && ids.any?

      by_id = board.board_columns.index_by(&:id)
      unknown = ids.map(&:to_i) - by_id.keys
      return error("Columns not on this board: #{unknown.join(', ')}") if unknown.any?

      # Two-phase to dodge the (board_id, position) unique index.
      ActiveRecord::Base.transaction do
        ids.each_with_index { |id, idx| by_id.fetch(id.to_i).update_column(:position, -(idx + 1)) }
        ids.each_with_index { |id, idx| by_id.fetch(id.to_i).update_column(:position, idx + 1) }
      end
      success(board_id: board.id, new_order: ids)
    end
  end
end
