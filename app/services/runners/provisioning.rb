# frozen_string_literal: true

module Runners
  # One step toward an environment the platform created being ready
  # (docs/design/agent-runtimes/runner-coder.md §5.2): the shared advance of a
  # provisioned runner type. A type's adapter makes `advance!(environment)` this
  # call with itself, and supplies the three things that differ:
  #
  #   adapter.provision(environment)         # no machine yet: ask for one. :pending or :ready
  #   adapter.prepare(environment)           # a machine is named: ask again. :pending or :ready
  #   adapter.inject_bootstrap(environment)  # the machine is ready: install `aixle-runner` on it
  #
  # `provision` writes the machine's name with `record_external_id!`, which sets
  # `boot_started_at` on the first write only.
  #
  # One step per call, decided by the state, and each step idempotent, because
  # Temporal retries the phase:
  #
  # - `provisioning`: past the timeout, the environment fails. With no
  #   `external_id`, `provision`; with one, `prepare`. `:pending` until the
  #   machine is ready. Then `inject_bootstrap` (once: an environment with a
  #   registration token minted already was installed on, or was being, and
  #   fails rather than install twice), then `finish_build` if the row is still
  #   `provisioning` (`register` may have moved it, runner-coder.md §8.4).
  # - `booting`: waits for the check-in; past the timeout, the environment fails.
  # - `idle`: ready.
  # - `failed`, `tearing_down` and `gone`: the session that holds it cannot get
  #   it, and fails with the reason.
  #
  # The adapter's calls (HTTP, SSH) run with no lock of ours, and the result of
  # each is saved under the row's own lock. The step does not re-read the
  # environment after each adapter call to see whether a teardown began
  # meanwhile: a machine given after the teardown finished is deleted by the
  # reconciler's sweep (§11). A ProvisionError from the adapter fails the
  # environment with its message and propagates; a CapacityError (the
  # integration has nothing to give) leaves the row `provisioning`, with no
  # machine and no clock, and the retry asks again.
  #
  # This module never writes a session's state.
  module Provisioning
    module_function

    # Answers `:ready` or `:pending`, or raises Runners::ProvisionError.
    def advance!(environment, adapter, now: Time.current)
      environment = RunnerEnvironment.find(environment.id)

      case environment.state.to_s
      when "provisioning" then provisioning_step!(environment, adapter, now)
      when "booting" then booting_step!(environment, now)
      when "idle" then :ready
      else raise ProvisionError, unusable_message(environment)
      end
    end

    # The machine's name, written under the row's lock. `boot_started_at` is set
    # with the first one and never changed by a later one.
    def record_external_id!(environment, external_id, now: Time.current)
      RunnerEnvironment.transaction do
        locked = RunnerEnvironment.lock.find(environment.id)
        attributes = { external_id: external_id }
        attributes[:boot_started_at] = now if locked.external_id.blank? && locked.boot_started_at.nil?
        locked.update!(attributes)
      end
    end

    # The environment fails with `message`, whatever its adapter says about the
    # step that found it: `mark_failed`, which clears the hold. The environment is
    # then torn down (the session's cleanup or the reconciler: §9.3, §11).
    def fail!(environment, message)
      Allocator.transition!(environment) do |locked|
        locked.mark_failed!(message) if locked.may_mark_failed?
      end
      raise ProvisionError, message
    end

    def provisioning_step!(environment, adapter, now)
      fail!(environment, timed_out_message(environment)) if timed_out?(environment, now)

      result = with_failure(environment) do
        environment.external_id.blank? ? adapter.provision(environment) : adapter.prepare(environment)
      end
      return :pending unless result == :ready

      install!(environment, adapter)
      :pending
    end
    private_class_method :provisioning_step!

    def install!(environment, adapter)
      fresh = RunnerEnvironment.find(environment.id)
      return unless fresh.provisioning?

      if fresh.credentials.where(kind: "registration").exists?
        fail!(fresh, "The install on workspace #{fresh.external_id} was interrupted.")
      end

      with_failure(fresh) { adapter.inject_bootstrap(fresh) }
      Allocator.transition!(fresh) { |locked| locked.finish_build! if locked.provisioning? }
    end
    private_class_method :install!

    def booting_step!(environment, now)
      fail!(environment, timed_out_message(environment)) if timed_out?(environment, now)

      :pending
    end
    private_class_method :booting_step!

    def with_failure(environment)
      yield
    rescue ProvisionError => e
      fail!(environment, e.message)
    end
    private_class_method :with_failure

    def timed_out?(environment, now)
      environment.boot_started_at.present? && environment.boot_started_at + timeout <= now
    end
    private_class_method :timed_out?

    def timeout = Settings.runners.bootstrap_timeout.to_f.seconds
    private_class_method :timeout

    def timed_out_message(environment)
      minutes = (timeout / 60).round
      if environment.booting?
        "Workspace started but aixle-runner did not check in within #{minutes} min. " \
          "Check that the workspace can reach #{Settings.domain}:443."
      else
        "The workspace was not ready within #{minutes} min."
      end
    end
    private_class_method :timed_out_message

    def unusable_message(environment)
      reason = environment.state_reason.presence
      "The environment #{environment.state.to_s.humanize(capitalize: false)}#{": #{reason}" if reason}"
    end
    private_class_method :unusable_message
  end
end
