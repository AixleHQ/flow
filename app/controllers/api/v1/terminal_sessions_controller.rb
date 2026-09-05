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
        project = session_params[:project_id] ? member_company_projects.find(session_params[:project_id]) : nil

        if session_params[:session_type] != "auth_setup" && viewer_for?(project)
          return render json: { error: "Viewers cannot launch sessions" }, status: :forbidden
        end

        agent = session_params[:configured_agent_id] ? find_accessible_agent(session_params[:configured_agent_id], project) : nil

        session = SessionService.create_and_start(
          user: current_user,
          project: project,
          # Project-less auth_setup sessions authenticate a credential, which is
          # billed to a company — so name it explicitly rather than let anything
          # downstream guess.
          company: project ? nil : auth_setup_company,
          session_type: session_params[:session_type],
          agent_type: session_params[:agent_type],
          configured_agent: agent,
          params: session_params.except(:project_id, :session_type, :agent_type, :configured_agent_id)
        )

        # `create_and_start` returns the unsaved record when validation rejects it —
        # e.g. an attached config item that belongs to another project. Serializing an
        # unpersisted session raises on its Global ID, so the client would get a 500
        # where it should get the errors it can act on.
        unless session.persisted?
          return render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
        end

        render json: TerminalSessionResource.new(session).to_h, status: :created
      rescue Oauth::PreflightError, CloudAuth::PreflightError => e
        # Session-start preflight (§4.6): block launch with a "Connect …" CTA rather
        # than starting a session doomed to fail during provisioning. Both errors carry
        # the same entry shape, so the client renders one list.
        render json: { error: e.message, reauth_required: e.connections }, status: :unprocessable_entity
      rescue SessionService::UnsafeMcpUrlError => e
        # F34: a selected MCP server's URL failed the launch-time safety re-check.
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def destroy
        session = find_session(params[:id])
        unless session.state.in?(%w[not_started finished failed cancelled])
          render json: { error: "Cannot delete active session" }, status: :bad_request
          return
        end
        # A row whose reservation is still held refuses to be destroyed; saying
        # "ok" to that would report a deletion that did not happen.
        unless session.destroy
          render json: { error: session.errors.full_messages.to_sentence }, status: :conflict
          return
        end
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
        session = find_readable_session(params[:id])
        return head :not_found unless session.state.in?(%w[finished failed])

        log = session.session_logs.find_by(name: "terminal_output.log")
        return head :not_found unless log&.file

        response.set_header("X-Log-Truncated", "true") if log.file_size.to_i > MAX_LOG_BYTES
        send_data read_log_tail(log), type: "text/plain; charset=utf-8", disposition: "inline"
      end

      private

      # Which company an auth_setup session authenticates a credential for.
      #
      # An explicit company_id wins (validated against the user's ACTIVE memberships,
      # so it can never name a company they left). Otherwise it is the company the
      # request is already acting for — the one the profile page that opened this
      # session is showing. Falling back to "only if they belong to exactly one"
      # left every multi-company user with a company-less session, and the credential
      # such a session writes cannot be saved at all.
      def auth_setup_company
        if params[:company_id].present?
          wanted = params[:company_id].to_i
          # Membership checked on the already-loaded list, but the company is loaded
          # directly: dereferencing :company off that list is what Bullet's "USE eager
          # loading" gate rejects, and eager-loading it on every request trips the
          # opposite gate. Same tension as AuthConcern#current_company.
          return nil unless current_user.active_memberships.any? { |m| m.company_id == wanted }

          # ::Company — inside Api::V1 the bare constant resolves to the controller
          # namespace module, not the model.
          return ::Company.find_by(id: wanted)
        end

        current_company
      end

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
          input_asset_ids: [], repository_ids: [], config_item_ids: [],
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

      # Read-only lookup for the log replay: the user's own sessions PLUS
      # sessions in projects they can reach, the latter only while the owner
      # shares them (TerminalSession#visible_to?). Everything else here stays
      # owner-scoped through #find_session — replaying someone's log is a share
      # the owner opted into; finishing or deleting their session is not.
      # 404 rather than 403: a session the owner keeps private should not be
      # distinguishable from one that does not exist.
      def find_readable_session(id)
        scope = TerminalSession.readable_by(current_user)
        session = if id.to_s.match?(/^\d+$/)
          scope.find(id)
        else
          scope.find_by!(route_token: id)
        end

        raise ActiveRecord::RecordNotFound unless session.visible_to?(current_user)

        session
      end

      def find_accessible_agent(id, project)
        scope = if project
          # Agent visibility follows the PROJECT's company.
          Agent.visible_for_project(project)
        else
          Agent.where(scope_type: "Company", scope_id: member_company_ids)
        end
        scope.find(id)
      end

      # Projects reachable through the user's ACTIVE memberships (API calls
      # carry no web session, so the company is derived per project).
      def member_company_projects
        Project.where(company_id: member_company_ids)
      end

      def member_company_ids
        current_user.company_memberships.active.select(:company_id)
      end

      # Viewer check against the target project's company; without a project
      # (auth_setup flows), fall back to the global viewer-everywhere predicate.
      def viewer_for?(project)
        if project
          membership = current_user.company_memberships.active.find_by(company_id: project.company_id)
          membership.nil? || membership.viewer?
        else
          current_user.active_memberships.none? || current_user.active_memberships.all?(&:viewer?)
        end
      end
    end
  end
end
