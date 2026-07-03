# frozen_string_literal: true

module PersonalTools
  class DeleteBoardColumn < Base
    tool do
      display_name "Delete Board Column"
      description "Delete a board column. Requires project-admin (owner). Rejected if the column has tasks."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_id, type: :integer, description: "Column id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :destroy?, policy: Web::Company::Projects::Board::ColumnsPolicy, project: project)
      column = project.board&.board_columns&.find_by(id: params[:column_id])
      return error("Column not found on this board") unless column
      return error("Column '#{column.name}' still has tasks — move them first") if column.board_tasks.exists?

      name = column.name
      column.destroy
      success(deleted_column_id: params[:column_id].to_i, name: name)
    end
  end
end
