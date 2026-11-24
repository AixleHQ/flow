# frozen_string_literal: true

module Runners
  # A runner session whose machine has not been heard for GRACE fails, unless
  # it was already finishing (docs/design/agent-runtimes/DESIGN.md §6.7).
  #
  #   Runners::ContactLoss.fail_if_lapsed!(session, environment)   # => true when the session was failed
  #
  # The dead-container scan calls it for a session whose machine
  # `Adapter#observe` reports `:unknown`, and sends no `status` op to it.
  #
  # The session keeps its machine, and so its admission slot, while the machine
  # is away (AD-4): it is marked (TerminalSession#contact_lost?), and its
  # cleanup waits (RunnerRuntime#cleanup_ready?) until the machine is heard
  # again, then stops the container, resets the machine and releases the slot.
  # A runner that is revoked or deleted never hears its machines again, so its
  # session lets the machine go when it fails, and the cleanup releases the
  # slot at once.
  module ContactLoss
    GRACE = 15.minutes
    MESSAGE = "Runner environment lost contact for 15 minutes."

    module_function

    def lapsed?(environment, now: Time.current)
      environment.silent_for?(GRACE, now)
    end

    def fail_if_lapsed!(session, environment, now: Time.current)
      return false unless lapsed?(environment, now: now)

      session.mark_contact_lost!(now)
      # A compare-and-set: a session that finished or was cancelled meanwhile keeps its outcome.
      failed = Sessions::Lifecycle.fail_if(session, expected_state: session.state, error_message: MESSAGE)
      if failed
        Machines.let_go!(session) if session.runner.retired?
      else
        session.clear_contact_lost!
      end
      failed
    end
  end
end
