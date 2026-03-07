# frozen_string_literal: true

module InternalTools
  class BoardUpdateTask < Base
    UPDATABLE_FIELDS = %w[title description priority tags task_type].freeze

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found on this board") unless task

      updates = params.slice(*UPDATABLE_FIELDS).reject { |_, v| v.nil? }
      return error("No valid fields to update") if updates.empty?

      task.update!(updates)

      success({
        id: task.id,
        title: task.title,
        updated_fields: updates.keys
      }.to_json)
    end
  end
end
