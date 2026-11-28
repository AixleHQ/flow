# frozen_string_literal: true

module Runners
  # The platform could not make an environment ready for a session: the
  # machine was refused, failed to build, failed the runner's checks, or did not
  # check in in time (docs/design/agent-runtimes/runner-coder.md §5.2). The
  # message is for people and reaches the session. RunnerRuntime#create_container
  # turns it into a CreateRefusedError, so the phase fails as non-retryable and
  # the cleanup runs. A lack of capacity is not a ProvisionError: it is a
  # ContainerRuntime::CapacityError, and the session waits.
  class ProvisionError < StandardError; end
end
