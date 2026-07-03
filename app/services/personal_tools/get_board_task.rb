# frozen_string_literal: true

module PersonalTools
  class GetBoardTask < Base
    tool do
      display_name "Get Board Task"
      description "Return full details for a board task including description, tags and comment count."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :show?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = find_task(project)
      return error("Task not found on this project's board") unless task

      success(BoardTaskResource.new(task).to_h)
    end

    private

    def find_task(project)
      project.board&.board_tasks&.find_by(id: params[:task_id])
    end
  end
end
