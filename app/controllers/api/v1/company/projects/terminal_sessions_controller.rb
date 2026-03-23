# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class TerminalSessionsController < ApplicationController
          # GET /api/v1/company/projects/:project_id/terminal_sessions
          # Project-scoped session history with Ransack filtering.
          #
          # Supported filters (via q[] params):
          #   q[agent_type_eq]    - filter by agent type
          #   q[state_eq]         - filter by state
          #   q[session_type_eq]  - filter by session type
          #   q[created_at_gteq]  - sessions created after date
          #   q[created_at_lteq]  - sessions created before date
          #   q[user_id_eq]       - filter by user
          def index
            scope = current_project.terminal_sessions
                                   .includes(
                                     :user,
                                     :project,
                                     :tools,
                                     :skills,
                                     :mcp_servers,
                                     :input_assets,
                                     :repositories,
                                     :output_assets,
                                     :session_logs
                                   )
                                   .ransack(q_params).result
                                   .order(created_at: :desc)

            respond_with paginate(scope), each_serializer: TerminalSessionSerializer
          end

          # GET /api/v1/company/projects/:project_id/terminal_sessions/:id
          def show
            session = current_project.terminal_sessions.find(params[:id])
            respond_with session, serializer: TerminalSessionSerializer
          end
        end
      end
    end
  end
end
