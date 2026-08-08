# frozen_string_literal: true

module PersonalTools
  class DeleteBoardTask < Base
    tool do
      display_name "Delete Board Task"
      description "Permanently delete a board task with its comments, assets and gates. " \
                  "Irreversible — prefer archive_board_task unless the user asked to delete. " \
                  "Rejected while the task has active workflow runs."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :destroy?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task
      # A run outlives its task (workflow_runs are nullified, not destroyed), so
      # deleting mid-run would leave a live run with nothing to report back to.
      return error(active_runs_message(task)) if task.workflow_runs.active.exists?

      title = task.title
      # Through TaskService, so the board activity feed records the deletion the
      # same way the UI's delete action does.
      TaskService.destroy(task: task, actor: user)
      return error("Failed to delete task: #{task.errors.full_messages.to_sentence}") unless task.destroyed?

      success(deleted_task_id: params[:task_id].to_i, title: title)
    end

    private

    def active_runs_message(task)
      "Cannot delete '#{task.title}' — it has active workflow runs; cancel them first (cancel_workflow_run)"
    end
  end
end
