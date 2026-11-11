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
        required: [],
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
            description: TASK_ID_PARAM
          },
          task_number: {
            type: "integer",
            description: TASK_NUMBER_PARAM
          },
          priority: {
            type: "string",
            description: "Updated task priority"
          },
          unassign: {
            type: "boolean",
            description: "Clear the current assignee, person or team. Cannot be combined with assignee_id or assignee_team_id."
          },
          task_type: {
            type: "string",
            description: "Updated task type"
          },
          assignee_id: {
            type: "integer",
            description: "User ID to assign the task to — must be a project member (see board_list_members)"
          },
          assignee_team_id: {
            type: "integer",
            description: "Team ID to assign the task to (see board_list_members): each run of the task goes to the " \
                         "member the team's strategy picks. Replaces a person assignee."
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

      task = find_task(board.board_tasks)
      return error(task_not_found) unless task

      updates = params.slice(*UPDATABLE_FIELDS).reject { |_, v| v.nil? }
      return error("Pass one of assignee_id, assignee_team_id or unassign") if [ assign?, assign_team?, unassign? ].count(true) > 1

      if unassign?
        updates.merge!("assignee_id" => nil, "assignee_team_id" => nil)
      elsif assign?
        updates["assignee_id"] = params[:assignee_id]
      elsif assign_team?
        updates["assignee_team_id"] = params[:assignee_team_id]
      end
      return error("No valid fields to update") if updates.empty?

      task.update!(updates)

      success({
        id: task.id,
        number: task.number,
        title: task.title,
        assignee_id: task.assignee_id,
        assignee_team_id: task.assignee_team_id,
        updated_fields: updates.keys
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      # An assignee who can't reach the project is the realistic case here, and
      # the step should read the reason rather than die on the exception.
      error(e.record.errors.full_messages.to_sentence.presence || e.message)
    end

    private

    def assign? = params[:assignee_id].present?
    def assign_team? = params[:assignee_team_id].present?
    def unassign? = ActiveModel::Type::Boolean.new.cast(params[:unassign]).present?
  end
end
