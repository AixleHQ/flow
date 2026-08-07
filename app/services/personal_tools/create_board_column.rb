# frozen_string_literal: true

module PersonalTools
  class CreateBoardColumn < Base
    tool do
      display_name "Create Board Column"
      description "Add a column to a project's board. Requires project-admin (owner). " \
                  "A given position inserts there, pushing the columns at and after it one " \
                  "place right; omitting it appends."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Column name.", required: true
      param :purpose, type: :string, description: "What the column represents."
      param :position, type: :integer, description: "Insert position; appended if omitted."
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::ColumnsPolicy, project: project)
      board = project.board
      return error("This project has no board") unless board

      column = ActiveRecord::Base.transaction { insert_column(board) }
      success(id: column.id, name: column.name, position: column.position)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create column: #{e.message}")
    end

    private

    def insert_column(board)
      position = params[:position]&.to_i
      if position.nil?
        position = board.board_columns.maximum(:position).to_i + 1
      else
        shift_right_from(board, position)
      end

      board.board_columns.create!(name: params[:name], purpose: params[:purpose], position: position)
    end

    # Both the model's uniqueness validation and the (board_id, position)
    # unique index reject a collision, so the shift walks the tail backwards:
    # the highest position moves first, into a slot nothing occupies, and every
    # later step's target has already been vacated. No intermediate duplicate,
    # hence no need for the negative-position two-phase pass
    # reorder_board_columns does (that one permutes ids, not a single shift).
    # `reorder` because the association carries a default `order(:position)`
    # that a plain `order` would only append to — leaving the walk ascending.
    def shift_right_from(board, position)
      board.board_columns.where(position: position..).reorder(position: :desc).each do |column|
        column.update_column(:position, column.position + 1)
      end
    end
  end
end
