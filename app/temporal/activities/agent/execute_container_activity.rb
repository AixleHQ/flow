# frozen_string_literal: true

module Activities
  module Agent
    class ExecuteContainerActivity < Base
      def run(input)
        session = TerminalSession.find(input.session_id)

        log(:info, "[ExecuteAgent] Session #{session.id} (#{session.session_type})")
        ContainerService.execute(session: session)
      rescue ContainerService::ExecutionError, ArgumentError => e
        raise TemporalExceptions.wrap(e, retryable: false)
      end
    end
  end
end
