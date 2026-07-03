# frozen_string_literal: true

module PersonalTools
  class AddBoardComment < Base
    tool do
      display_name "Add Board Comment"
      description "Add a comment to a board task. Markdown is supported in the body."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :body, type: :string, description: "Comment body (markdown supported).", required: true
      param :tags, type: :array, description: "Optional comment tags.", items: { type: "string" }
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::Board::Task::CommentsPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      comment = TaskService.add_comment(
        task: task, params: { body: params[:body], tags: params[:tags] || [] }, actor: user
      )
      return error("Failed to add comment: #{comment.errors.full_messages.to_sentence}") unless comment.persisted?

      success(id: comment.id, task_id: task.id, author: user.name)
    end
  end
end
