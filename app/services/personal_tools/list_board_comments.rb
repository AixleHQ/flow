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
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
    end

    LIMIT = 100

    def execute
      project = find_project!
      authorize!(project.board, :index?, policy: Web::Company::Projects::Board::Task::CommentsPolicy, project: project)
      task = find_task(project.board&.board_tasks)
      return error(task_not_found) unless task

      rows = task.task_comments.includes(:author).order(created_at: :desc).limit(LIMIT).map do |c|
        { id: c.id, body: c.body, author: c.author&.name, author_type: c.author_type, tags: c.tags,
          created_at: c.created_at }
      end
      success(task_id: task.id, task_number: task.number, comments: rows)
    end
  end
end
