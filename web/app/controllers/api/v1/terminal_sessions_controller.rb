# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsController < ApplicationController
      before_action :set_terminal_session, only: %i[show update destroy finish_auth cancel]

      # GET /api/v1/terminal_sessions
      # List all terminal sessions for current user
      def index
        @sessions = current_user.terminal_sessions
                                .order(created_at: :desc)
                                .limit(50)

        respond_with @sessions, each_serializer: TerminalSessionSerializer
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

      # POST /api/v1/terminal_sessions/:id/finish_auth
      # Mark authentication as finished (triggers artifact collection)
      def finish_auth
        unless @session.session_type == "auth_setup"
          return render json: { error: "Can only finish auth for auth_setup sessions" }, status: :bad_request
        end

        unless @session.may_stop?
          return render json: { error: "Session cannot be stopped in current state: #{@session.state}" },
                        status: :bad_request
        end

        @session.stop!

        # Send signal to Temporal workflow to finish and cleanup
        if @session.temporal_workflow_id.present?
          TemporalService.send_signal(@session.temporal_workflow_id, :container_finished)
        end

        render json: {
          data: TerminalSessionSerializer.new(@session).as_json,
          message: "Authentication finished, collecting artifacts..."
        }
      end

      # POST /api/v1/terminal_sessions/:id/cancel
      # Cancel/stop active session (sends signal to gracefully shutdown and cleanup)
      def cancel
        unless @session.may_cancel?
          return render json: { error: "Session cannot be cancelled in current state: #{@session.state}" },
                        status: :bad_request
        end

        # Send cancel signal to Temporal workflow to trigger graceful cleanup
        # This allows the workflow to run stop_container activity without collecting artifacts
        if @session.temporal_workflow_id.present?
          TemporalService.send_signal(@session.temporal_workflow_id, :container_cancelled)
        end

        # Update state to cancelled
        @session.cancel!

        render json: {
          data: TerminalSessionSerializer.new(@session).as_json,
          message: "Session cancelled"
        }
      end

      # DELETE /api/v1/terminal_sessions/:id
      # Delete a terminal session (only if not active)
      def destroy
        unless @session.state.in?(%w[not_started collected failed cancelled])
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
          metadata: {},
          session_config: [
            :agent_id, :mode, :initial_prompt,
            { config_files: {}, env_vars: {}, mcp_server_ids: [], tool_ids: [], skill_ids: [] }
          ]
        )

        if params.dig(:terminal_session, :session_config).present?
          raw = params[:terminal_session][:session_config]
          permitted[:session_config] = raw.to_unsafe_h.slice(
            *TerminalSession::ALLOWED_SESSION_CONFIG_KEYS
          )
        end

        permitted
      end

      def update_params
        params.require(:terminal_session).permit(metadata: {})
      end
    end
  end
end
