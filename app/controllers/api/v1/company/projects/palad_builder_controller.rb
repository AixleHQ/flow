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
                initial_prompt: "Help me build a workflow automation. Start by asking what process I want to automate.",
                tool_ids: meta_tool_ids,
                requested_model: params[:preferred_model],
                metadata: { palad_builder: true },
                session_config: { "bmad_enabled" => true }
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
        end
      end
    end
  end
end
