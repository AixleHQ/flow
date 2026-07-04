# frozen_string_literal: true

module PersonalTools
  class ListBoardColumns < Base
    tool do
      display_name "List Board Columns"
      description "List the columns of a project's board, with ids/positions to target when creating or moving tasks."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :index?, policy: board_columns_policy, project: project)
      board = project.board
      return error("This project has no board") unless board

      columns = board.board_columns.order(:position).map do |c|
        { id: c.id, name: c.name, position: c.position, purpose: c.purpose }
      end
      success(project_id: project.id, columns: columns)
    end

    private

    def board_columns_policy = Web::Company::Projects::Board::ColumnsPolicy
  end
end
