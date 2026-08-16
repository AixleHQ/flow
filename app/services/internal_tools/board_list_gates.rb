# frozen_string_literal: true

module InternalTools
  class BoardListGates < Base
    tool do
      display_name "Board List Gates"
      description "List the Gates on a board task — the read side of board_create_gate, and what " \
                  "a task reporting `pending_gates` is actually waiting on. Each row carries the " \
                  "CI verdict so far (`ci_status`: pending / succeeded / failed / stale), the run " \
                  "or check it is bound to, when it expires, and — for a Gate the sweep could not " \
                  "resolve — its diagnostic_reason and reconciliation_log. Gates are created and " \
                  "resolved by CI webhooks, so there is no tool to resolve or delete one from a " \
                  "session: a Gate stuck `stale` is cleared by a person from the board UI."
      tags :board
      inject_when :workflow_step_session
      read_only
      input_schema({
        type: "object",
        required: [],
        properties: {
          task_id: {
            type: "integer",
            description: "Board task ID. Optional when the workflow run is already attached to a board task."
          },
          status: {
            type: "string",
            enum: %w[pending resolved stale all],
            description: "Filter by gate status. Defaults to all."
          }
        }
      })
    end

    STATUSES = %w[pending resolved stale].freeze

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      task_id = params[:task_id] || workflow_run&.board_task_id
      return error("task_id is required") unless task_id

      task = board.board_tasks.find_by(id: task_id)
      return error("Task not found on this board") unless task

      status = (params[:status].presence || "all").to_s
      return error("Unknown status '#{status}' — use one of: #{STATUSES.join(', ')}, all") unless valid_status?(status)

      success({ task_id: task.id, status: status, gates: rows(task, status) }.to_json)
    end

    private

    def valid_status?(status)
      status == "all" || STATUSES.include?(status)
    end

    def rows(task, status)
      scope = task.gates.includes(:creator).order(:created_at)
      scope = scope.where(status: status) unless status == "all"
      scope.map { |gate| Gates::ToolRow.call(gate) }
    end
  end
end
