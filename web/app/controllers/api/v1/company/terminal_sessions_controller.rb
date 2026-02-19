# frozen_string_literal: true

module Api
  module V1
    module Company
      class TerminalSessionsController < ApplicationController
        # GET /api/v1/company/terminal_sessions
        # Company-wide session history with Ransack filtering.
        #
        # Supported filters (via q[] params):
        #   q[agent_type_eq]    - filter by agent type (claude_code, cursor_cli, codex, gemini_cli)
        #   q[state_eq]         - filter by state (running, collected, failed, etc.)
        #   q[session_type_eq]  - filter by session type (agent_session, auth_setup, etc.)
        #   q[created_at_gteq]  - sessions created after date
        #   q[created_at_lteq]  - sessions created before date
        #   q[user_id_eq]       - filter by user
        def index
          scope = current_company.terminal_sessions
                                 .includes(:user, :project)
                                 .ransack(q_params).result
                                 .order(created_at: :desc)

          respond_with paginate(scope), each_serializer: TerminalSessionSerializer
        end

        # GET /api/v1/company/terminal_sessions/:id
        def show
          session = current_company.terminal_sessions.find(params[:id])
          respond_with session, serializer: TerminalSessionSerializer
        end
      end
    end
  end
end
