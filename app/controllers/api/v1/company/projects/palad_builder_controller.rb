# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class PaladBuilderController < ApplicationController
          # POST /api/v1/company/projects/:project_id/palad_builder/start
          def start
            meta_tool_ids = Tool.where(kind: :workflow, name: palad_builder_tool_names).pluck(:id)

            session = SessionService.create_and_start(
              user: current_user,
              project: current_project,
              session_type: "agent_session",
              agent_type: params[:agent_runtime] || current_user.default_agent_runtime || "claude_code",
              params: {
                mode: "interactive",
                initial_prompt: palad_builder_prompt,
                tool_ids: meta_tool_ids,
                requested_model: params[:preferred_model],
                metadata: { palad_builder: true }
              }
            )

            respond_with session, serializer: TerminalSessionSerializer
          end

          # GET /api/v1/company/projects/:project_id/palad_builder/status
          def status
            sessions = current_project.terminal_sessions
                                      .where(user: current_user)
                                      .where("metadata @> ?", { palad_builder: true }.to_json)
                                      .order(created_at: :desc)
                                      .limit(20)

            respond_with sessions, each_serializer: TerminalSessionSerializer
          end

          private

          def palad_builder_tool_names
            %w[
              meta_create_workflow meta_create_agent meta_create_step
              meta_create_sub_step meta_get_workflow meta_list_workflows
              meta_finalize_workflow meta_update_step meta_delete_step
              meta_reorder_steps meta_create_tool meta_create_skill
              meta_create_mcp_server meta_link_resource_to_step
              meta_list_agents meta_list_tools meta_list_skills
              meta_get_board meta_create_board_column meta_update_board_column
              meta_delete_board_column meta_reorder_board_columns
              meta_create_column_binding meta_update_column_binding
              meta_delete_column_binding meta_setup_board_from_preset
            ]
          end

          def palad_builder_prompt
            <<~PROMPT
              # Palad Builder

              You are a Workflow Architect for the Palad platform. Help the user build
              workflow automations by creating entities through the provided meta-tools.

              ## What You Can Build

              **Workflows** — ordered sequences of Steps, each step runs one agent session.
              **Steps** — one agent + one terminal + one deliverable. Has instructions, tools, skills.
              **SubSteps** — progress markers within a step (trackable, not separate sessions).
              **Agents** — LLM personas with system prompts (persona, communication style, principles).
              **Board Columns** — stages on the project board (Backlog, In Progress, Done, etc.).
              **Column Bindings** — connect a workflow to a column (auto-trigger or manual button).

              ## Palad Platform Architecture

              - **Company** owns Projects, Agents, Tools, Skills, MCP Servers, Workflows
              - **Project** owns project-scoped entities + Board + Tasks
              - Company-scoped entities are shared across all projects
              - Project-scoped entities are visible only in that project
              - Each Project has ONE Board with ordered columns
              - ColumnWorkflowBinding: when task enters column → workflow triggers (auto or manual)

              ## How Workflows Execute

              1. WorkflowRun created → Steps execute in order (or parallel via depends_on_step_ids)
              2. Each Step = one terminal session with one agent
              3. Step instructions define what the agent does (MOST IMPORTANT field)
              4. SubSteps = progress tracking (agent calls mark_sub_step)
              5. Modes: interactive (agent can ask user) or non_interactive (fully autonomous)

              ## Step Design Guidelines

              - Each step = one focused deliverable (don't split one task across steps)
              - Instructions should be detailed markdown with: Task, Context, Requirements, Output Format
              - Use depends_on_step_ids for parallel execution (DAG)
              - skip_policy: "if_outputs_exist" for idempotent re-runs
              - on_failure: "retry" + max_retries for transient failures
              - For board-triggered workflows: all steps must be non-interactive

              ## Your Process

              1. Ask what the user wants to automate
              2. Explore existing resources (meta_list_* tools)
              3. Propose structure — wait for approval
              4. Create agents → create workflow → create steps with detailed instructions
              5. Optionally configure board columns and automation bindings
              6. Validate with meta_finalize_workflow

              ## Rules

              - ALWAYS propose before creating. Ask for confirmation.
              - Show progress after each creation.
              - Step instructions are the MOST IMPORTANT thing — be detailed and specific.
              - Board automation is optional — ask if the user wants it.
            PROMPT
          end
        end
      end
    end
  end
end
