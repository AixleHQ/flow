# frozen_string_literal: true

module Activities
  module Agent
    class CleanupContainerActivity < Base
      def run(input)
        session = TerminalSession.find(input.session_id)

        log(:info, "[CleanupAgent] Session #{session.id}")
        ContainerService.cleanup(session: session)
      rescue ActiveRecord::RecordNotFound => e
        log(:warn, "[CleanupAgent] Session not found: #{e.message}")
        { status: :not_found }
      end
    end
  end
end
