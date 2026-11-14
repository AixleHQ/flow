# frozen_string_literal: true

module Runners
  # A machine the operator installed `aixle-runner` on. The platform creates,
  # rebuilds and calls nothing (docs/design/agent-runtimes/DESIGN.md §5.1).
  class ManualAdapter < Adapter
    # §2.5: with no registered machine heard for this long, the runner is
    # unreachable. Between RunnerEnvironment::ONLINE_WINDOW and this, a machine
    # that is not heard is offline and the runner is degraded.
    UNREACHABLE_AFTER = 3.minutes
    REASON_LIMIT = 255

    def self.type = "manual"

    def capabilities(_runner)
      Capabilities.new(provisionable: false, rebuildable: false)
    end

    # From the runner's machines alone (§2.5):
    #
    # - `pending`: no machine has ever registered;
    # - `unreachable`: no machine can take a session (every one `failed`, or
    #   every one `gone`), or no registered machine was heard for more than
    #   UNREACHABLE_AFTER;
    # - `connected`: every registered machine was heard within
    #   RunnerEnvironment::ONLINE_WINDOW and none has failed;
    # - `degraded`: any other, with the offline and failed machines named.
    def check_health(runner, now: Time.current)
      machines = runner.environments.order(:id).to_a
      return health("pending") if machines.empty?

      registered = machines.select(&:registered?)
      failed = machines.select(&:failed?)
      return health("unreachable", unusable_reason(failed)) if registered.empty?

      offline = registered.reject { |machine| machine.heard?(now) }
      return health("connected") if offline.empty? && failed.empty?

      if registered.none? { |machine| machine.heard?(now, within: UNREACHABLE_AFTER) }
        return health("unreachable", "No machine has been heard for more than #{UNREACHABLE_AFTER.inspect}: " \
                                     "#{names(offline)}.")
      end

      health("degraded", degraded_reason(offline, failed))
    end

    private

    def health(status, reason = nil) = Health.new(status: status, reason: reason&.truncate(REASON_LIMIT))

    def unusable_reason(failed)
      return "No machine registered." if failed.empty?

      "No machine can take a session: #{failed.one? ? 'its machine' : 'every machine'} failed: #{failures(failed)}."
    end

    def degraded_reason(offline, failed)
      parts = []
      parts << "Offline: #{names(offline)}." if offline.any?
      parts << "Failed: #{failures(failed)}." if failed.any?
      parts.join(" ")
    end

    def failures(machines)
      machines.map { |machine| "#{name(machine)} (#{machine.state_reason.presence || 'no reason recorded'})" }.join("; ")
    end

    def names(machines) = machines.map { |machine| name(machine) }.join(", ")

    def name(machine) = machine.display_name.presence || machine.key
  end
end
