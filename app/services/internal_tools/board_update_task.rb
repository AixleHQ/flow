# frozen_string_literal: true

module InternalTools
  class BoardUpdateTask < Base
    tool do
      display_name "Board Update Task"
      description "Update mutable task fields such as title, description, priority, tags, or task type."
      tags :board
      inject_when :workflow_step_session
      input_schema({
        type: "object",
        required: %w[task_id],
        properties: {
          tags: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Replacement tag list"
          },
          title: {
            type: "string",
            description: "Updated task title"
          },
          task_id: {
            type: "integer",
            description: "Board task ID"
          },
          priority: {
            type: "string",
            description: "Updated task priority"
          },
          task_type: {
            type: "string",
            description: "Updated task type"
          },
          description: {
            type: "string",
            description: "Updated task description"
          }
        }
      })
    end

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
