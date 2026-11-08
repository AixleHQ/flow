# frozen_string_literal: true

module ContainerRuntime
  # Raised by #create_container when the runtime answered that the create
  # failed, so its outcome is known and nothing of it is left to appear later:
  # an external runner's `container.start` refused (runner/protocol/PROTOCOL.md
  # §6.2), its pull included. A create whose answer never came is not this
  # error: its outcome stays uncertain (AdmittedPhaseActivity#record_failed_operation).
  class CreateRefusedError < StandardError; end
end
