# frozen_string_literal: true

module PersonalTools
  class GetBoardTask < Base
    tool do
      display_name "Get Board Task"
      description "Return full details for a board task, by task_id or by task_number (the #N shown on the " \
                  "board), including description, tags, comment count and the files attached to it " \
                  "(read one with read_asset, source task)."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer,
                      description: "Internal board task id (the `id` field), not the #N shown on the board. " \
                                   "Give either this or task_number."
      param :task_number, type: :integer,
                          description: "The task's number on the project's board — what a person means by \"#12\"."
    end

    def execute
      project = find_project!
      authorize!(project.board, :show?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      return error("Pass exactly one of task_id or task_number") if params[:task_id].present? == params[:task_number].present?

      task = find_task(project)
      return error("Task not found on this project's board") unless task

      success(BoardTaskResource.new(task, params: { snake_keys: true }).to_h.merge(assets: attached_files(task)))
    end

    private

    def attached_files(task)
      task.task_assets.order(created_at: :desc).map do |asset|
        { id: asset.id, name: asset.name, size: asset.file&.size, content_type: asset.file&.mime_type,
          tags: asset.tags, author_type: asset.author_type, created_at: asset.created_at }
      end
    end

    def find_task(project)
      project.board&.board_tasks
             &.includes(:workflow_runs, :gates)
             &.find_by(params[:task_id].present? ? { id: params[:task_id] } : { number: params[:task_number] })
    end
  end
end
