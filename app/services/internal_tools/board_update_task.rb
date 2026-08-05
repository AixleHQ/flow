# frozen_string_literal: true

module InternalTools
  class BoardUpdateTask < Base
    tool do
      display_name "Board Update Task"
      description "Update mutable task fields such as title, description, priority, tags, task type, or assignee."
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
          unassign: {
            type: "boolean",
            description: "Clear the current assignee. Cannot be combined with assignee_id."
          },
          task_type: {
            type: "string",
            description: "Updated task type"
          },
          assignee_id: {
            type: "integer",
            description: "User ID to assign the task to — must be a project member (see board_list_members)"
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
      if assign? && unassign?
        return error("Pass either assignee_id or unassign, not both")
      elsif assign? || unassign?
        updates["assignee_id"] = unassign? ? nil : params[:assignee_id]
      end
      return error("No valid fields to update") if updates.empty?

      task.update!(updates)

      success({
        id: task.id,
        title: task.title,
        assignee_id: task.assignee_id,
        updated_fields: updates.keys
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      # An assignee who can't reach the project is the realistic case here, and
      # the step should read the reason rather than die on the exception.
      error(e.record.errors.full_messages.to_sentence.presence || e.message)
    end

    private

    def assign? = params[:assignee_id].present?
    def unassign? = ActiveModel::Type::Boolean.new.cast(params[:unassign]).present?
  end
end
