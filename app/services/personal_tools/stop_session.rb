# frozen_string_literal: true

module PersonalTools
  class StopSession < Base
    tool do
      display_name "Stop Session"
      description "Stop a running agent session. The graceful stop lets the container finish and " \
                  "collect its logs and outputs; force marks the session failed instead, which is " \
                  "what unblocks a workflow step waiting on a wedged agent."
      audience :user
      tags :sessions
      destructive
      param :session_id, type: :integer, description: "Session id, from list_sessions.", required: true
      param :force, type: :boolean,
                    description: "Fail the session rather than finishing it (default false)."
      param :reason, type: :string, description: "Recorded as the session's error message when forcing."
    end

    STOPPABLE_STATES = %w[not_started queued running ready finishing].freeze

    def execute
      session = find_session!
      return error("Read-only members cannot stop sessions") if read_only_member?(session)
      unless session.state.in?(STOPPABLE_STATES)
        return error("Session #{session.id} is already #{session.state}")
      end

      if session.queued?
        SessionService.finish(session: session)
        return stopped(session, "cancel")
      end
      params[:force] ? force_stop(session) : graceful_stop(session)
    rescue TerminalSession::InvalidStateError => e
      error(e.message)
    end

    private

    # Anyone who may SEE a session may stop it (product decision, 2026-08-10) —
    # with the one carve-out the viewer role exists for: a read-only member
    # never writes, and killing someone's running agent is a write.
    def read_only_member?(session)
      return false if session.user_id == user.id

      membership = session_membership(session)
      membership.nil? || membership.viewer?
    end

    # Through SessionService, never `session.finish!`/`fail!`: only the service
    # signals the session's own container workflow, and only that signal lets its
    # cleanup phase run — which is what deletes the pod, Service, IngressRoute
    # and Middlewares and uploads the logs.
    def graceful_stop(session)
      SessionService.finish(session: session)
      stopped(session, "finish")
    end

    def force_stop(session)
      SessionService.fail_session(session: session, error_message: params[:reason].presence || "Stopped over MCP")
      stopped(session, "fail")
    end

    def stopped(session, how)
      success(session_id: session.id, stopped_with: how, state: session.reload.state)
    end
  end
end
