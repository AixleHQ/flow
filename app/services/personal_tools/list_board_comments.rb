# frozen_string_literal: true

module PersonalTools
  class ListBoardComments < Base
    tool do
      display_name "List Board Comments"
      description "List comments on a board task, newest first."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
    end

    LIMIT = 100

    def execute
      project = find_project!
      authorize!(project.board, :index?, policy: Web::Company::Projects::Board::Task::CommentsPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      rows = task.task_comments.includes(:author).order(created_at: :desc).limit(LIMIT).map do |c|
        { id: c.id, body: c.body, author: c.author&.name, author_type: c.author_type, tags: c.tags,
          created_at: c.created_at }
      end
      success(task_id: task.id, comments: rows)
    end
  end
end
