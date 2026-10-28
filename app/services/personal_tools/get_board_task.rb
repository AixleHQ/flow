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
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
    end

    def execute
      project = find_project!
      authorize!(project.board, :show?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = find_task(project.board&.board_tasks&.includes(:workflow_runs, :gates))
      return error(task_not_found) unless task

      success(BoardTaskResource.new(task, params: { snake_keys: true }).to_h.merge(assets: attached_files(task)))
    end

    private

    def attached_files(task)
      task.task_assets.order(created_at: :desc).map do |asset|
        { id: asset.id, name: asset.name, size: asset.file&.size, content_type: asset.file&.mime_type,
          tags: asset.tags, author_type: asset.author_type, created_at: asset.created_at }
      end
    end
  end
end
