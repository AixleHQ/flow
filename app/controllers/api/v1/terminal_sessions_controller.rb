# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionsController < ApplicationController
      skip_before_action :authenticate_user!, only: []

      def show
        session = find_session(params[:id])
        render json: TerminalSessionResource.new(session).to_h
      end

      def create
        if current_user.read_only? && session_params[:session_type] != "auth_setup"
          return render json: { error: "Viewers cannot launch sessions" }, status: :forbidden
        end

        project = session_params[:project_id] ? current_user.company.projects.find(session_params[:project_id]) : nil
        agent = session_params[:configured_agent_id] ? find_accessible_agent(session_params[:configured_agent_id], project) : nil

        session = SessionService.create_and_start(
          user: current_user,
          project: project,
          session_type: session_params[:session_type],
          agent_type: session_params[:agent_type],
          configured_agent: agent,
          params: session_params.except(:project_id, :session_type, :agent_type, :configured_agent_id)
        )

        render json: TerminalSessionResource.new(session).to_h, status: :created
      rescue Oauth::PreflightError => e
        # Session-start preflight (§4.6): block launch with a "Connect …" CTA rather
        # than starting a session doomed to fail during provisioning.
        render json: { error: e.message, reauth_required: e.connections }, status: :unprocessable_entity
      rescue SessionService::UnsafeMcpUrlError => e
        # F34: a selected MCP server's URL failed the launch-time safety re-check.
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def destroy
        session = find_session(params[:id])
        unless session.state.in?(%w[not_started finished failed])
          render json: { error: "Cannot delete active session" }, status: :bad_request
          return
        end
        session.destroy
        head :ok
      end

      # @summary Finish an active terminal session
      def finish
        session = current_user.terminal_sessions.find(params[:id])
        SessionService.finish(session: session)
        render json: TerminalSessionResource.new(session).to_h
      rescue TerminalSession::InvalidStateError => e
        render json: { error: e.message }, status: :bad_request
      end

      # Cap the bytes served (and buffered) per replay request. The raw PTY stream
      # can be large (TUI redraw spam); serve only the tail so neither the server
      # nor the browser buffers an unbounded blob.
      MAX_LOG_BYTES = 2 * 1024 * 1024

      # @summary Stream a finished session's captured terminal log (raw ANSI bytes)
      def terminal_log
        session = find_session(params[:id])
        return head :not_found unless session.state.in?(%w[finished failed])

        log = session.session_logs.find_by(name: "terminal_output.log")
        return head :not_found unless log&.file

        response.set_header("X-Log-Truncated", "true") if log.file_size.to_i > MAX_LOG_BYTES
        send_data read_log_tail(log), type: "text/plain; charset=utf-8", disposition: "inline"
      end

      private

      # Read at most the last MAX_LOG_BYTES of the attachment. Seek to the tail on
      # the underlying IO so large files are not fully loaded; fall back to a
      # read-then-slice if the storage IO is not seekable.
      def read_log_tail(log)
        size = log.file_size.to_i
        log.file.open do |io|
          io.seek(size - MAX_LOG_BYTES) if size > MAX_LOG_BYTES
          io.read
        end
      rescue StandardError
        content = log.file.read.to_s
        content.bytesize > MAX_LOG_BYTES ? content.byteslice(-MAX_LOG_BYTES, MAX_LOG_BYTES) : content
      end

      def session_params
        params.require(:terminal_session).permit(
          :project_id, :session_type, :agent_type, :configured_agent_id, :mode,
          :initial_prompt, :requested_model, :auth_kind,
          tool_ids: [], skill_ids: [], mcp_server_ids: [],
          input_asset_ids: [], repository_ids: [],
          session_config: [ :bmad_enabled, { bmad_modules: [] } ]
        )
      end

      def find_session(id)
        if id.to_s.match?(/^\d+$/)
          current_user.terminal_sessions.find(id)
        else
          current_user.terminal_sessions.find_by!(route_token: id)
        end
      end

      def find_accessible_agent(id, project)
        scope = project ? Agent.visible_for_project(project) : Agent.belonging_to_company(current_user.company)
        scope.find(id)
      end
    end
  end
end
