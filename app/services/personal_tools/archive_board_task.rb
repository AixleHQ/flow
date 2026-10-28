# frozen_string_literal: true

module PersonalTools
  class ArchiveBoardTask < Base
    tool do
      display_name "Archive Board Task"
      description "Archive a board task, or unarchive it by passing archived=false. " \
                  "The resulting state is reported as `archived` by get_board_task."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
      param :archived, type: :boolean,
            description: "true archives (the default); false unarchives.", default: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = find_task(project.board&.board_tasks)
      return error(task_not_found) unless task

      # Through TaskService, so the board activity feed records the change the
      # same way the UI's archive action does.
      archive? ? TaskService.archive(task: task, actor: user) : TaskService.unarchive(task: task, actor: user)
      return error("Failed to update task: #{task.errors.full_messages.to_sentence}") if task.errors.any?

      success(id: task.id, number: task.number, title: task.title, archived: task.archived?, archived_at: task.archived_at)
    end

    private

    # Omitting the param archives; only an explicit false unarchives.
    def archive?
      params[:archived].nil? || ActiveModel::Type::Boolean.new.cast(params[:archived]) != false
    end
  end
end
