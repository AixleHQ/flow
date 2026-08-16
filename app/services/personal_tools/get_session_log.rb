# frozen_string_literal: true

module PersonalTools
  class GetSessionLog < Base
    tool do
      display_name "Get Session Log"
      description "Return the tail of one session's terminal output — read live from the container " \
                  "while it runs, from the stored log once it is over — together with how long the " \
                  "agent has been silent and whether its output ends in a provider quota error. " \
                  "This is the tool for telling a working agent from a wedged one; list_sessions " \
                  "gives you the id."
      audience :user
      tags :sessions
      read_only
      param :session_id, type: :integer, description: "Session id, from list_sessions.", required: true
      param :lines, type: :integer, description: "Tail size in lines (default 200, cap 2000)."
      param :raw, type: :boolean,
                  description: "Keep ANSI escape sequences in a stored log (default false). Live " \
                               "reads are already plain text."
    end

    DEFAULT_LINES = 200
    MAX_LINES = 2_000

    def execute
      session = find_session!
      payload = ::Sessions::LogTail.new(session).call(lines: requested_lines, raw: params[:raw])

      success(base_payload(session).merge(payload))
    end

    private

    def requested_lines
      requested = params[:lines].present? ? params[:lines].to_i : DEFAULT_LINES
      requested.clamp(1, MAX_LINES)
    end

    def base_payload(session)
      {
        session_id: session.id,
        state: session.state,
        session_type: session.session_type,
        agent_type: session.agent_type,
        mode: session.mode,
        project_id: session.project_id,
        started_at: session.started_at,
        finished_at: session.finished_at,
        error_message: session.error_message
      }
    end
  end
end
