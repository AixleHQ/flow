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

      private

      def session_params
        params.require(:terminal_session).permit(
          :project_id, :session_type, :agent_type, :configured_agent_id, :mode,
          :initial_prompt, :requested_model,
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
