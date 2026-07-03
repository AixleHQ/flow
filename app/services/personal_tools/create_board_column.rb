# frozen_string_literal: true

module PersonalTools
  class CreateBoardColumn < Base
    tool do
      display_name "Create Board Column"
      description "Add a column to a project's board. Requires project-admin (owner)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Column name.", required: true
      param :purpose, type: :string, description: "What the column represents."
      param :position, type: :integer, description: "Position; appended if omitted."
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::ColumnsPolicy, project: project)
      board = project.board
      return error("This project has no board") unless board

      position = params[:position] || (board.board_columns.maximum(:position).to_i + 1)
      column = board.board_columns.create!(name: params[:name], purpose: params[:purpose], position: position)
      success(id: column.id, name: column.name, position: column.position)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create column: #{e.message}")
    end
  end
end
