# frozen_string_literal: true

module Seeds
  module PlatformTools
    BOARD_WORKFLOW_TOOLS = [
      {
        name: "board_get_board_info",
        display_name: "Board Get Board Info",
        description: "Return the current board with its columns and related metadata for the active workflow task.",
        input_schema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      {
        name: "board_list_tasks",
        display_name: "Board List Tasks",
        description: "List tasks on the current board with optional filters for column, tag, task type, or assignee.",
        input_schema: {
          type: "object",
          properties: {
            column_name: { type: "string", description: "Filter tasks to a board column by name" },
            tag: { type: "string", description: "Filter tasks by tag" },
            task_type: { type: "string", description: "Filter tasks by task type" },
            assignee_id: { type: "integer", description: "Filter tasks by assignee user ID" }
          },
          required: []
        }
      },
      {
        name: "board_get_task",
        display_name: "Board Get Task",
        description: "Return full details for a board task. Defaults to the workflow's bound board task when task_id is omitted.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID. Optional when the workflow run is already attached to a board task." }
          },
          required: []
        }
      },
      {
        name: "board_get_comments",
        display_name: "Board Get Comments",
        description: "List comments for a task on the current board with optional tag or author-type filters.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            tag: { type: "string", description: "Optional tag filter" },
            author_type: { type: "string", enum: %w[user agent], description: "Optional author type filter" }
          },
          required: %w[task_id]
        }
      },
      {
        name: "board_get_task_assets",
        display_name: "Board Get Task Assets",
        description: "List files attached to a board task, optionally filtered by tag.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            tag: { type: "string", description: "Optional tag filter" }
          },
          required: %w[task_id]
        }
      },
      {
        name: "board_add_comment",
        display_name: "Board Add Comment",
        description: "Add an agent comment to a task on the current board.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            body: { type: "string", description: "Comment text" },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "Optional comment tags"
            }
          },
          required: %w[task_id body]
        }
      },
      {
        name: "board_update_task",
        display_name: "Board Update Task",
        description: "Update mutable task fields such as title, description, priority, tags, or task type.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            title: { type: "string", description: "Updated task title" },
            description: { type: "string", description: "Updated task description" },
            priority: { type: "string", description: "Updated task priority" },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "Replacement tag list"
            },
            task_type: { type: "string", description: "Updated task type" }
          },
          required: %w[task_id]
        }
      },
      {
        name: "board_create_task",
        display_name: "Board Create Task",
        description: "Create a new board task in the current board, optionally targeting a specific column.",
        input_schema: {
          type: "object",
          properties: {
            title: { type: "string", description: "Task title" },
            description: { type: "string", description: "Task description" },
            column_name: { type: "string", description: "Target column name. Defaults to the first column." },
            task_type: { type: "string", description: "Task type" },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "Optional task tags"
            }
          },
          required: %w[title]
        }
      },
      {
        name: "board_move_task",
        display_name: "Board Move Task",
        description: "Move a task to another board column by name.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            column_name: { type: "string", description: "Destination column name" }
          },
          required: %w[task_id column_name]
        }
      },
      {
        name: "board_attach_asset",
        display_name: "Board Attach Asset",
        description: "Attach a file to a board task by reading it from a path inside the running container.",
        input_schema: {
          type: "object",
          properties: {
            task_id: { type: "integer", description: "Board task ID" },
            name: { type: "string", description: "Attachment filename" },
            file_path: { type: "string", description: "Path inside the running container to upload" },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "Optional asset tags"
            }
          },
          required: %w[task_id name file_path]
        }
      },
      {
        name: "board_manage_tags",
        display_name: "Board Manage Tags",
        description: "Add or remove a tag on a task or comment on the current board.",
        input_schema: {
          type: "object",
          properties: {
            action: { type: "string", enum: %w[add remove], description: "Whether to add or remove the tag" },
            entity_type: { type: "string", enum: %w[task comment], description: "Entity type to modify" },
            entity_id: { type: "integer", description: "Target task or comment ID" },
            tag: { type: "string", description: "Tag value" }
          },
          required: %w[action entity_type entity_id tag]
        }
      },
      {
        name: "board_create_wait",
        display_name: "Board Create Wait",
        description: "Create a Wait on a board task. The auto-workflow for the task's column will not fire until all Waits are resolved.",
        input_schema: {
          type: "object",
          properties: {
            task_id:        { type: "integer", description: "Board task ID" },
            wait_type:      { type: "string",  description: "Wait type. Supported: github_checks_completed, github_workflow_completed" },
            repo_full_name: { type: "string",  description: "(github_checks_completed, github_workflow_completed) Full repo name, e.g. owner/repo" },
            pr_number:      { type: "integer", description: "(github_checks_completed) Pull request number" },
            run_id:         { type: "integer", description: "(github_workflow_completed) GitHub Actions workflow run ID" }
          },
          required: %w[task_id wait_type]
        }
      }
    ].freeze

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

      BOARD_WORKFLOW_TOOLS.each do |attrs|
        Tool.find_or_initialize_by(name: attrs[:name], kind: :workflow).update!(
          display_name: attrs[:display_name],
          description: attrs[:description],
          input_schema: attrs[:input_schema],
          execution_mode: :app
        )
      end

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
