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

    META_WORKFLOW_TOOLS = [
      {
        name: "meta_create_workflow",
        display_name: "Meta Create Workflow",
        description: "Create a new workflow in the target project. Stores workflow_id in shared context for subsequent tools.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Workflow name" },
            description: { type: "string", description: "Workflow description" },
            project_id: { type: "integer", description: "Target project ID. Defaults to current project." },
            config: { type: "object", description: "Optional workflow config (base_tool_ids, etc.)" }
          },
          required: %w[name]
        }
      },
      {
        name: "meta_create_agent",
        display_name: "Meta Create Agent",
        description: "Create a new agent (LLM persona) in the target scope. Returns agent ID for use in steps.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Agent identifier (snake_case, auto-generated if omitted)" },
            title: { type: "string", description: "Display name (e.g. 'Product Manager')" },
            persona: { type: "string", description: "Core system prompt — defines who the agent IS" },
            communication_style: { type: "string", description: "HOW the agent communicates (tone, format)" },
            principles: { type: "string", description: "Guiding principles and constraints" },
            scope_type: { type: "string", enum: %w[Project Company], description: "Scope type. Default: Project" },
            scope_id: { type: "integer", description: "Scope ID. Default: current project or company" }
          },
          required: %w[title persona]
        }
      },
      {
        name: "meta_create_step",
        display_name: "Meta Create Step",
        description: "Add a step to the target workflow. Steps are added sequentially unless position is specified.",
        input_schema: {
          type: "object",
          properties: {
            workflow_id: { type: "integer", description: "Target workflow ID. Defaults to last created workflow." },
            name: { type: "string", description: "Step name" },
            position: { type: "integer", description: "Position in workflow (0-based). Auto-assigned if omitted." },
            instructions: { type: "string", description: "Detailed instructions for the agent (markdown)" },
            description: { type: "string", description: "Brief description for UI" },
            agent_id: { type: "integer", description: "Agent to run this step" },
            allow_non_interactive: { type: "boolean", description: "Can run without user interaction" },
            skip_policy: { type: "string", enum: %w[never if_outputs_exist manual], description: "When to skip" },
            on_failure: { type: "string", enum: %w[retry skip fail], description: "Failure behavior" },
            max_retries: { type: "integer", description: "Retry count on failure" },
            tool_ids: { type: "array", items: { type: "integer" }, description: "Tool IDs available in this step" },
            skill_ids: { type: "array", items: { type: "integer" }, description: "Skill IDs injected into context" },
            mcp_server_ids: { type: "array", items: { type: "integer" }, description: "MCP server IDs" },
            mount_repositories: { type: "boolean", description: "Mount Git repos in /workspace" },
            input_asset_specs: { type: "array", description: "Required input files" },
            output_asset_specs: { type: "array", description: "Expected output files" },
            depends_on_step_ids: { type: "array", items: { type: "integer" }, description: "Step IDs this step depends on (DAG)" }
          },
          required: %w[name]
        }
      },
      {
        name: "meta_create_sub_step",
        display_name: "Meta Create Sub-Step",
        description: "Add a trackable sub-step (progress milestone) to a step.",
        input_schema: {
          type: "object",
          properties: {
            step_id: { type: "integer", description: "Parent step ID" },
            name: { type: "string", description: "Sub-step name" },
            position: { type: "integer", description: "Position within step. Auto-assigned if omitted." },
            description: { type: "string", description: "What this unit of work involves" },
            instructions: { type: "string", description: "Additional guidance" },
            required: { type: "boolean", description: "Must be completed for step to finish. Default: true" }
          },
          required: %w[step_id name]
        }
      },
      {
        name: "meta_get_workflow",
        display_name: "Meta Get Workflow",
        description: "Get the full definition of a workflow including all steps and sub-steps.",
        input_schema: {
          type: "object",
          properties: {
            workflow_id: { type: "integer", description: "Workflow ID. Defaults to last created workflow." }
          },
          required: []
        }
      },
      {
        name: "meta_list_workflows",
        display_name: "Meta List Workflows",
        description: "List all workflows visible for the target project (project + company scope).",
        input_schema: {
          type: "object",
          properties: {
            project_id: { type: "integer", description: "Project ID. Defaults to current project." }
          },
          required: []
        }
      },
      {
        name: "meta_finalize_workflow",
        display_name: "Meta Finalize Workflow",
        description: "Validate and finalize a workflow. Checks: all steps have instructions, agent references are valid, dependency graph is acyclic, positions are sequential.",
        input_schema: {
          type: "object",
          properties: {
            workflow_id: { type: "integer", description: "Workflow ID. Defaults to last created workflow." }
          },
          required: []
        }
      },
      # --- Step mutation tools ---
      {
        name: "meta_update_step",
        display_name: "Meta Update Step",
        description: "Update an existing step's fields (name, instructions, agent_id, tool_ids, etc.).",
        input_schema: {
          type: "object",
          properties: {
            step_id: { type: "integer", description: "Step ID to update" },
            name: { type: "string" }, instructions: { type: "string" }, description: { type: "string" },
            agent_id: { type: "integer" }, allow_non_interactive: { type: "boolean" },
            skip_policy: { type: "string", enum: %w[never if_outputs_exist manual] },
            on_failure: { type: "string", enum: %w[retry skip fail] },
            max_retries: { type: "integer" },
            tool_ids: { type: "array", items: { type: "integer" } },
            skill_ids: { type: "array", items: { type: "integer" } },
            mcp_server_ids: { type: "array", items: { type: "integer" } },
            mount_repositories: { type: "boolean" },
            depends_on_step_ids: { type: "array", items: { type: "integer" } }
          },
          required: %w[step_id]
        }
      },
      {
        name: "meta_delete_step",
        display_name: "Meta Delete Step",
        description: "Delete a step from a workflow. Fails if other steps depend on it.",
        input_schema: {
          type: "object",
          properties: { step_id: { type: "integer", description: "Step ID to delete" } },
          required: %w[step_id]
        }
      },
      {
        name: "meta_reorder_steps",
        display_name: "Meta Reorder Steps",
        description: "Reorder all steps in a workflow by providing ordered step IDs.",
        input_schema: {
          type: "object",
          properties: {
            workflow_id: { type: "integer", description: "Workflow ID. Defaults to last created." },
            step_ids: { type: "array", items: { type: "integer" }, description: "Ordered array of step IDs" }
          },
          required: %w[step_ids]
        }
      },
      # --- Resource creation tools ---
      {
        name: "meta_create_tool",
        display_name: "Meta Create Tool",
        description: "Create a custom tool definition.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Tool name (snake_case)" },
            display_name: { type: "string" }, description: { type: "string" },
            docker_image: { type: "string", description: "Docker image for container execution" },
            execution_mode: { type: "string", enum: %w[app container], description: "Default: container" },
            input_schema: { type: "object", description: "JSON Schema for parameters" },
            command: { type: "string" },
            scope_type: { type: "string", enum: %w[Project Company] }
          },
          required: %w[name]
        }
      },
      {
        name: "meta_create_skill",
        display_name: "Meta Create Skill",
        description: "Create a custom skill (reusable instruction block).",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string" }, title: { type: "string" },
            content: { type: "string", description: "Skill content (instructions/knowledge)" },
            description: { type: "string" },
            scope_type: { type: "string", enum: %w[Project Company] },
            scope_id: { type: "integer" }
          },
          required: %w[name title content]
        }
      },
      {
        name: "meta_create_mcp_server",
        display_name: "Meta Create MCP Server",
        description: "Register an MCP (Model Context Protocol) server for external tool access.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string" }, display_name: { type: "string" }, description: { type: "string" },
            url: { type: "string", description: "Server endpoint URL" },
            transport: { type: "string", enum: %w[http sse stdio], description: "Default: http" },
            command: { type: "string", description: "Command for stdio transport" },
            headers: { type: "object" }, env: { type: "object" },
            scope_type: { type: "string", enum: %w[Project Company] },
            scope_id: { type: "integer" }
          },
          required: %w[name]
        }
      },
      # --- Link & list tools ---
      {
        name: "meta_link_resource_to_step",
        display_name: "Meta Link Resource to Step",
        description: "Link a tool, skill, or MCP server to a step.",
        input_schema: {
          type: "object",
          properties: {
            step_id: { type: "integer", description: "Step ID" },
            resource_type: { type: "string", enum: %w[tool skill mcp_server], description: "Resource type" },
            resource_id: { type: "integer", description: "Resource ID to link" }
          },
          required: %w[step_id resource_type resource_id]
        }
      },
      {
        name: "meta_list_agents",
        display_name: "Meta List Agents",
        description: "List agents visible for the target project.",
        input_schema: { type: "object", properties: {}, required: [] }
      },
      {
        name: "meta_list_tools",
        display_name: "Meta List Tools",
        description: "List custom and system tools available for the project.",
        input_schema: { type: "object", properties: {}, required: [] }
      },
      {
        name: "meta_list_skills",
        display_name: "Meta List Skills",
        description: "List skills available for the project.",
        input_schema: { type: "object", properties: {}, required: [] }
      },
      # --- Board tools ---
      {
        name: "meta_get_board",
        display_name: "Meta Get Board",
        description: "Get the project board with columns, purposes, task counts, and workflow bindings.",
        input_schema: { type: "object", properties: {}, required: [] }
      },
      {
        name: "meta_create_board_column",
        display_name: "Meta Create Board Column",
        description: "Create a new column on the project board.",
        input_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Column name" },
            purpose: { type: "string", description: "What this column represents" },
            position: { type: "integer", description: "Position (auto-assigned if omitted)" }
          },
          required: %w[name]
        }
      },
      {
        name: "meta_update_board_column",
        display_name: "Meta Update Board Column",
        description: "Update a board column's name, purpose, or position.",
        input_schema: {
          type: "object",
          properties: {
            column_id: { type: "integer" },
            name: { type: "string" }, purpose: { type: "string" }, position: { type: "integer" }
          },
          required: %w[column_id]
        }
      },
      {
        name: "meta_delete_board_column",
        display_name: "Meta Delete Board Column",
        description: "Delete an empty board column. Fails if column has tasks.",
        input_schema: {
          type: "object",
          properties: { column_id: { type: "integer" } },
          required: %w[column_id]
        }
      },
      {
        name: "meta_reorder_board_columns",
        display_name: "Meta Reorder Board Columns",
        description: "Reorder all board columns by providing ordered column IDs.",
        input_schema: {
          type: "object",
          properties: { column_ids: { type: "array", items: { type: "integer" }, description: "Ordered column IDs" } },
          required: %w[column_ids]
        }
      },
      {
        name: "meta_create_column_binding",
        display_name: "Meta Create Column Binding",
        description: "Bind a workflow to a board column for auto or manual triggering.",
        input_schema: {
          type: "object",
          properties: {
            column_id: { type: "integer" }, workflow_id: { type: "integer" },
            trigger_mode: { type: "string", enum: %w[manual auto], description: "Default: manual" },
            cooldown_seconds: { type: "integer", description: "Min gap between auto-triggers. Default: 5" }
          },
          required: %w[column_id workflow_id]
        }
      },
      {
        name: "meta_update_column_binding",
        display_name: "Meta Update Column Binding",
        description: "Update a column workflow binding's trigger mode or cooldown.",
        input_schema: {
          type: "object",
          properties: {
            binding_id: { type: "integer" },
            trigger_mode: { type: "string", enum: %w[manual auto] },
            cooldown_seconds: { type: "integer" }
          },
          required: %w[binding_id]
        }
      },
      {
        name: "meta_delete_column_binding",
        display_name: "Meta Delete Column Binding",
        description: "Remove a workflow binding from a column.",
        input_schema: {
          type: "object",
          properties: { binding_id: { type: "integer" } },
          required: %w[binding_id]
        }
      },
      {
        name: "meta_setup_board_from_preset",
        display_name: "Meta Setup Board From Preset",
        description: "Create or reset board from a preset (simple_kanban, dev_team, full_sdlc). Only works if columns are empty.",
        input_schema: {
          type: "object",
          properties: { preset: { type: "string", enum: %w[simple_kanban dev_team full_sdlc] } },
          required: %w[preset]
        }
      },
      {
        name: "meta_delete_workflow",
        display_name: "Meta Delete Workflow",
        description: "Soft-delete a workflow. Fails if workflow has active runs or is bound to a board column.",
        input_schema: {
          type: "object",
          properties: {
            workflow_id: { type: "integer", description: "Workflow ID to delete" }
          },
          required: %w[workflow_id]
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

      # -- Meta-workflow tools: used by Palad Builder to create entities --
      META_WORKFLOW_TOOLS.each do |attrs|
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
