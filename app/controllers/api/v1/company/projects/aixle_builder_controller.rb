# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class AixleBuilderController < ApplicationController
          # POST /api/v1/company/projects/:project_id/aixle_builder/start
          def start
            meta_tool_ids = Tool.where(kind: :workflow, name: aixle_builder_tool_names).pluck(:id)

            session = SessionService.create_and_start(
              user: current_user,
              project: current_project,
              session_type: "agent_session",
              agent_type: params[:agent_runtime] || current_user.default_agent_runtime || "claude_code",
              params: {
                mode: "interactive",
                initial_prompt: "First read the reference files in /workspace/references/ (aixle-system-reference.md and bmad-llms-full.txt) to understand the platform. Then help me build a workflow automation — start by asking what process I want to automate.",
                tool_ids: meta_tool_ids,
                requested_model: params[:preferred_model],
                metadata: { aixle_builder: true },
                input_asset_ids: Array(params[:input_asset_ids]).map(&:to_i),
                session_config: {
                  "bmad_enabled" => true,
                  "config_files" => builder_reference_files
                }
              }
            )

            respond_with session, serializer: TerminalSessionSerializer
          end

          # GET /api/v1/company/projects/:project_id/aixle_builder/status
          def status
            sessions = current_project.terminal_sessions
                                      .where(user: current_user)
                                      .where("metadata @> ?", { aixle_builder: true }.to_json)
                                      .order(created_at: :desc)
                                      .limit(20)

            respond_with sessions, each_serializer: TerminalSessionSerializer
          end

          private

          def aixle_builder_tool_names
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
              meta_delete_workflow
            ]
          end

          # Reference docs injected into /workspace/references/ via config_files
          def builder_reference_files
            files = {}

            ref_dir = Rails.root.join("references")
            if ref_dir.exist?
              ref_dir.children.select(&:file?).each do |path|
                files["/workspace/references/#{path.basename}"] = File.read(path)
              end
            end

            files
          end
        end
      end
    end
  end
end
