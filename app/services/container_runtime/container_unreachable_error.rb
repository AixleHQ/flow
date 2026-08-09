# frozen_string_literal: true

module ContainerRuntime
  # Raised when the runtime could not reach the container at all — the pod was
  # deleted, its node died, or the API refused the exec upgrade.
  #
  # This is deliberately distinct from "the command ran and exited non-zero",
  # which #exec reports as an exit code. Collapsing both into `["", "", 1]` is
  # what let ScanQuotaErrorsActivity re-exec into destroyed pods forever: it
  # could not tell a dead container from a command that simply failed.
  class ContainerUnreachableError < StandardError
    attr_reader :status_code, :container_identifier

    def initialize(message = nil, status_code: nil, container_identifier: nil)
      @status_code = status_code
      @container_identifier = container_identifier
      super(message.presence || default_message)
    end

    private

    def default_message
      target = container_identifier.presence || "container"
      reason = status_code ? "exec handshake returned HTTP #{status_code}" : "exec handshake failed"

      "#{target} is unreachable (#{reason})"
    end
  end
end
