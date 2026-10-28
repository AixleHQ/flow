# frozen_string_literal: true

module PersonalTools
  class AddBoardComment < Base
    tool do
      display_name "Add Board Comment"
      description "Add a comment to a board task. Markdown is supported in the body."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
      param :body, type: :string, description: "Comment body (markdown supported).", required: true
      param :tags, type: :array, description: "Optional comment tags.", items: { type: "string" }
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::Task::CommentsPolicy, project: project)
      task = find_task(project.board&.board_tasks)
      return error(task_not_found) unless task

      comment = TaskService.add_comment(
        task: task, params: { body: params[:body], tags: params[:tags] || [] }, actor: user
      )
      return error("Failed to add comment: #{comment.errors.full_messages.to_sentence}") unless comment.persisted?

      success(id: comment.id, task_id: task.id, task_number: task.number, author: user.name)
    end
  end
end
