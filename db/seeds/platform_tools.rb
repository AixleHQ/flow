# frozen_string_literal: true

module Seeds
  module PlatformTools
    def self.seed!
      puts "Creating platform tools..."

      # Cleanup deprecated tools
      Tool.where(name: "write_step_note", kind: :workflow).destroy_all

      # -- Workflow tools: auto-injected into workflow_step sessions --
      Tool.find_or_initialize_by(name: "list_sub_steps", kind: :workflow).update!(
        display_name: "List Sub-Steps",
        description: "List current step's sub-steps with their statuses. Only available during workflow execution.",
        input_schema: { type: "object", properties: {} },
        execution_mode: :app
      )

      Tool.find_or_initialize_by(name: "mark_sub_step", kind: :workflow).update!(
        display_name: "Mark Sub-Step",
        description: "Update sub-step status with optional note and structured data. Only available during workflow execution.",
        input_schema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "Sub-step run ID" },
            status: { type: "string", enum: %w[in_progress completed skipped], description: "New status" },
            note: { type: "string", description: "What was done, decisions made" },
            data: { type: "object", description: "Structured data — decisions, metrics, findings" }
          },
          required: %w[id status]
        },
        execution_mode: :app
      )

      # Cleanup renamed tools
      Tool.where(name: %w[finish_step fail_step]).destroy_all

      # -- Internal tools: invisible, auto-injected --
      Tool.find_or_initialize_by(name: "finish_session", kind: :internal).update!(
        display_name: "Finish Session",
        description: "Signal successful completion of a non-interactive session. " \
                     "This terminates the session. Call only after ALL work is done and output files are saved.",
        input_schema: {
          type: "object",
          properties: {
            note: { type: "string", description: "Optional final note (saved to step if in workflow context)" }
          },
          required: []
        },
        execution_mode: :app
      )

      Tool.find_or_initialize_by(name: "fail_session", kind: :internal).update!(
        display_name: "Fail Session",
        description: "Signal that a non-interactive session has failed. " \
                     "This terminates the session with an error. Use when the task cannot be completed.",
        input_schema: {
          type: "object",
          properties: {
            reason: { type: "string", description: "Why the session failed" },
            note: { type: "string", description: "Optional note with details (saved to step if in workflow context)" }
          },
          required: %w[reason]
        },
        execution_mode: :app
      )

      Tool.find_or_initialize_by(name: "read_tool_result", kind: :internal).update!(
        display_name: "Read Tool Result",
        description: "Retrieve status and download URLs for an async tool execution. " \
                     "Returns presigned URLs valid for 1 hour. " \
                     "Download files using curl: curl -o /tmp/result.json <url>",
        input_schema: {
          type: "object",
          properties: {
            tool_result_id: { type: "string", description: "Execution ID (e.g. tr-abc123...)" }
          },
          required: %w[tool_result_id]
        },
        execution_mode: :app
      )

      puts "  Platform tools: #{Tool.system_tools.count} system, #{Tool.internal_tools.count} internal, #{Tool.workflow_tools.count} workflow"
    end
  end
end
