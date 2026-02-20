# frozen_string_literal: true

module Activities
  module Agent
    class PullImageActivity < Base
      def run(input)
        session = TerminalSession.find(input.session_id)
        strategy = session.strategy

        log(:info, "[PullAgent] Image for session #{session.id}")
        strategy.pull_image
      rescue Docker::Error::NotFoundError => e
        raise TemporalExceptions.wrap(e, retryable: false)
      rescue Docker::Error::DockerError => e
        raise TemporalExceptions.wrap(e, retryable: true)
      end
    end
  end
end
