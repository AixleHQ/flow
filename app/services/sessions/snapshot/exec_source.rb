# frozen_string_literal: true

module Sessions
  class Snapshot
    # Reads a snapshot with one exec into the session's container, through the runtime
    # ContainerRuntime.for_session gives it: a pod exec when hosted, one runner op on a
    # runner session. The pod-exec handshake is the expensive part, not the commands, so
    # every part comes from the same exec.
    class ExecSource
      def initialize(session, runtime:)
        @session = session
        @runtime = runtime
      end

      # Raises ContainerRuntime::ContainerUnreachableError when the container is gone:
      # the caller skips such a session rather than judging it on an empty read.
      # @return [Hash{Symbol => String}] the raw output of each part that was read
      def read(parts)
        return {} if parts.empty? || session.container_id.blank?

        container = runtime.resolve_container(session.container_id)
        return {} unless container

        command = Command.new(parts)
        # exec! (not exec) so a destroyed pod arrives as ContainerUnreachableError instead
        # of an exit code of 1 that looks like an ordinary command failure.
        stdout, _stderr, status = runtime.exec!(container, command.argv, stdout: true, stderr: true)
        status.to_i.zero? ? command.parse(Array(stdout).join) : {}
      rescue ContainerRuntime::ContainerUnreachableError
        raise
      rescue StandardError => e
        Rails.logger.warn("[Sessions::Snapshot] session=#{session.id} could not read the terminal: #{e.class}: #{e.message}")
        {}
      end

      private

      attr_reader :session, :runtime
    end
  end
end
