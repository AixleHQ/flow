# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsController < Api::V1::ApplicationController
      # POST /api/v1/terminal_sessions
      # Creates a new interactive terminal session with a Docker container
      def create
        session_id = SecureRandom.uuid
        step_name = params[:step_name] || 'interactive'

        begin
          ContainerManager.create_session(
            session_id: session_id,
            step_name: step_name,
            repo_url: params[:repo_url],
            interactive: true
          )

          # Wait a moment for container to start and ports to be assigned
          sleep 0.5

          # Get ttyd URL for frontend connection
          ttyd_info = ContainerManager.get_ttyd_url(session_id: session_id, step_name: step_name)

          render json: {
            id: session_id,
            step_name: step_name,
            status: 'running',
            ttyd_url: ttyd_info&.dig(:ws_url),
            ttyd_port: ttyd_info&.dig(:port),
            created_at: Time.current.iso8601
          }, status: :created
        rescue ContainerManager::ApiKeyMissingError => e
          render json: { error: e.message }, status: :service_unavailable
        rescue ContainerManager::ContainerError => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue Docker::Error::DockerError => e
          Rails.logger.error("[TerminalSessionsController] Docker error: #{e.message}")
          render json: { error: "Failed to create container: #{e.message}" }, status: :service_unavailable
        end
      end

      # GET /api/v1/terminal_sessions/:id
      # Get terminal session status
      def show
        session_id = params[:id]
        step_name = params[:step_name] || 'interactive'

        running = ContainerManager.container_running?(session_id: session_id, step_name: step_name)

        if running
          ttyd_info = ContainerManager.get_ttyd_url(session_id: session_id, step_name: step_name)

          render json: {
            id: session_id,
            step_name: step_name,
            status: 'running',
            ttyd_url: ttyd_info&.dig(:ws_url),
            ttyd_port: ttyd_info&.dig(:port)
          }
        else
          render json: { error: 'Terminal session not found or not running' }, status: :not_found
        end
      end

      # DELETE /api/v1/terminal_sessions/:id
      # Stop and remove terminal session container
      def destroy
        session_id = params[:id]
        step_name = params[:step_name] || 'interactive'

        ContainerManager.stop_session(session_id: session_id, step_name: step_name)

        render json: { status: 'stopped' }
      end
    end
  end
end
