# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsController < Api::V1::ApplicationController
      # POST /api/v1/terminal_sessions
      # Creates a new interactive terminal session with a Docker container
      def create
        session_id = SecureRandom.uuid
        step_name = params[:step_name] || "dev"

        begin
          ContainerManager.create_session(
            session_id: session_id,
            step_name: step_name,
            repo_url: params[:repo_url],
            repo_branch: params[:repo_branch]
          )

          # Wait for container to start and services to be ready
          sleep 2

          # Get service URLs for frontend connection
          urls = ContainerManager.get_session_urls(session_id: session_id, step_name: step_name)

          render json: {
            id: session_id,
            step_name: step_name,
            status: "running",
            ttyd: urls&.dig(:ttyd),
            watcher: urls&.dig(:watcher),
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
        step_name = params[:step_name] || "dev"

        running = ContainerManager.container_running?(session_id: session_id, step_name: step_name)

        if running
          urls = ContainerManager.get_session_urls(session_id: session_id, step_name: step_name)

          render json: {
            id: session_id,
            step_name: step_name,
            status: "running",
            ttyd: urls&.dig(:ttyd),
            watcher: urls&.dig(:watcher)
          }
        else
          render json: { error: "Terminal session not found or not running" }, status: :not_found
        end
      end

      # DELETE /api/v1/terminal_sessions/:id
      # Stop and remove terminal session container
      def destroy
        session_id = params[:id]
        step_name = params[:step_name] || "dev"

        ContainerManager.stop_session(session_id: session_id, step_name: step_name)

        render json: { status: "stopped" }
      end
    end
  end
end
