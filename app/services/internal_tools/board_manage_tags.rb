# frozen_string_literal: true

module InternalTools
  class BoardManageTags < Base
    tool do
      display_name "Board Manage Tags"
      description "Add or remove a tag on a task or comment on the current board."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[action entity_type entity_id tag],
        properties: {
          tag: {
            type: "string",
            description: "Tag value"
          },
          action: {
            enum: %w[add remove],
            type: "string",
            description: "Whether to add or remove the tag"
          },
          entity_id: {
            type: "integer",
            description: "Target task or comment ID"
          },
          entity_type: {
            enum: %w[task comment],
            type: "string",
            description: "Entity type to modify"
          }
        }
      })
    end

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
