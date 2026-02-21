# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsController < ApplicationController
      before_action :set_terminal_session, only: %i[show update destroy finish]

      # GET /api/v1/terminal_sessions
      # User-scoped sessions (for auth/onboarding/profile).
      # Company/project-wide history → /api/v1/company/terminal_sessions
      def index
        scope = current_user.terminal_sessions
                            .includes(:project)
                            .order(created_at: :desc)

        respond_with paginate(scope), each_serializer: TerminalSessionSerializer
      end

      # GET /api/v1/terminal_sessions/:id
      # Get single terminal session
      def show
        respond_with @session, serializer: TerminalSessionSerializer
      end

      # POST /api/v1/terminal_sessions
      # Create and start new terminal session (auth_setup type)
      def create
        @session = current_user.terminal_sessions.build(session_params)

        if @session.save
          # Trigger AASM start event (will start Temporal workflow)
          @session.start! if @session.may_start?
        end

        respond_with @session, serializer: TerminalSessionSerializer
      end

      # PATCH /api/v1/terminal_sessions/:id
      # Update session metadata (e.g., user preferences)
      def update
        @session.update(update_params)
        respond_with @session, serializer: TerminalSessionSerializer
      end

      # POST /api/v1/terminal_sessions/:id/finish
      # Gracefully finish session — stop, collect artifacts, collect usage.
      # Works for any session type (auth_setup, agent_session, etc.)
      def finish
        @session.request_finish!

        render json: {
          data: TerminalSessionSerializer.new(@session).attributes,
          message: "Session finishing, collecting artifacts..."
        }
      rescue TerminalSession::InvalidStateError => e
        render json: { error: e.message }, status: :bad_request
      end


      # DELETE /api/v1/terminal_sessions/:id
      # Delete a terminal session (only if not active)
      def destroy
        unless @session.state.in?(%w[not_started finished failed])
          return render json: { error: "Cannot delete active session. Cancel it first." }, status: :bad_request
        end

        @session.destroy
        head :ok
      end

      private

      def set_terminal_session
        # Find by ID (numeric) or route_token (hex string)
        @session = if params[:id].to_s.match?(/^\d+$/)
                     current_user.terminal_sessions.find_by(id: params[:id])
        else
                     current_user.terminal_sessions.find_by(route_token: params[:id])
        end

        render json: { error: "Terminal session not found" }, status: :not_found unless @session
      end

      def session_params
        permitted = params.require(:terminal_session).permit(
          :session_type,
          :agent_type,
          :project_id,
          :configured_agent_id,
          :mode,
          :initial_prompt,
          metadata: {},
          tool_ids: [],
          skill_ids: [],
          mcp_server_ids: [],
          input_asset_ids: [],
          repository_ids: [],
          session_config: {}
        )

        if params.dig(:terminal_session, :session_config).present?
          raw = params[:terminal_session][:session_config]
          permitted[:session_config] = raw.to_unsafe_h.slice("config_files", "env_vars")
        end

        permitted
      end

      def update_params
        params.require(:terminal_session).permit(metadata: {})
      end
    end
  end
end
