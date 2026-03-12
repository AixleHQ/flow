# frozen_string_literal: true

module InternalTools
  class BoardManageTags < Base
    ALLOWED_ACTIONS = %w[add remove].freeze
    ALLOWED_ENTITY_TYPES = %w[task comment].freeze

    def execute
      require_workflow_context!

      return error("action must be 'add' or 'remove'") unless params[:action].in?(ALLOWED_ACTIONS)
      return error("entity_type must be 'task' or 'comment'") unless params[:entity_type].in?(ALLOWED_ENTITY_TYPES)
      return error("tag is required") if params[:tag].blank?

      entity = find_entity
      return entity if entity.is_a?(Hash)

      current_tags = entity.tags || []
      new_tags = if params[:action] == "add"
                   (current_tags + [ params[:tag] ]).uniq
      else
                   current_tags - [ params[:tag] ]
      end

      entity.update!(tags: new_tags)

      success({ entity_type: params[:entity_type], entity_id: entity.id, tags: entity.tags }.to_json)
    end

    private

    def find_entity
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      case params[:entity_type]
      when "task"
        task = board.board_tasks.find_by(id: params[:entity_id])
        task || error("Task not found on this board")
      when "comment"
        comment = TaskComment.joins(board_task: :board).where(boards: { id: board.id }).find_by(id: params[:entity_id])
        comment || error("Comment not found on this board")
      end
    end
  end
end
