# frozen_string_literal: true

module Runners
  # What is specific to a `manual` runner's machines on the way a session is
  # launched (docs/design/agent-runtimes/DESIGN.md §7.3, §8): whether the runner
  # has a machine that can take a session, and the messages that say why not.
  # Which environment a session holds, its release and its failure are
  # Runners::Allocator's, whatever the type
  # (docs/design/agent-runtimes/runner-coder.md §5); the scrub, the reset and the
  # sweep of stale sessions are ManualAdapter's.
  #
  #   Runners::Machines.availability(runner)   # => Availability, for the launch's checks
  #
  # A machine is `failed` (§5.2) only for a failure of its own or of its runner:
  # a reset that failed, a check-in that reports missing prerequisites, a
  # refresh token presented twice. A session's outcome never fails a machine.
  module Machines
    # Whether a runner has a machine that can take a session: `:available`
    # (one registered and reachable, free or busy), `:all_offline` (some
    # registered, none reachable, with the offline machines for the message),
    # `:none_registered`, or `:all_failed`, with the machines that are out of
    # rotation, `failed`, for the message.
    Availability = Data.define(:status, :failed, :offline) do
      def available? = status == :available
    end

    # The runner has no machine that can take a session (DESIGN.md §8,
    # `runner_unreachable`): none registered, every one `failed`, or every
    # registered one offline.
    class NoMachine < StandardError
      def reason = UNREACHABLE
    end

    UNREACHABLE = "runner_unreachable"

    # The wait reason of ContainerRuntime::CapacityError when every machine that
    # can take a session is busy (SessionAdmission::WAIT_REASONS, §10).
    RUNNER_CAPACITY = "runner_capacity"

    module_function

    def availability(runner)
      registered = RunnerEnvironment.where(runner_id: runner.id, state: "registered")
      return Availability.new(status: :available, failed: [], offline: []) if registered.heard.exists?

      offline = registered.order(:id).to_a
      return Availability.new(status: :all_offline, failed: [], offline: offline) if offline.any?

      failed = RunnerEnvironment.where(runner_id: runner.id, state: "failed").order(:id).to_a
      Availability.new(status: failed.empty? ? :none_registered : :all_failed, failed: failed, offline: [])
    end

    # Why the runner cannot take a session, for a result that is not
    # `:available`. `pick_from` names where another runner is picked.
    def unavailable_message(runner, availability, pick_from = nil)
      elsewhere = pick_from ? " #{pick_from}" : ""
      case availability.status
      when :all_offline
        machines = availability.offline
        listed = machines.map { |machine| machine.display_name.presence || machine.key }
        "Runner \"#{runner.name}\" has no machine online: #{machines.one? ? 'its machine is' : 'every machine is'} offline " \
          "(#{listed.join(', ')}). Start aixle-runner on #{machines.one? ? 'it' : 'one of them'}, or pick another runner#{elsewhere}."
      when :none_registered
        "Runner \"#{runner.name}\" has no machine registered. Register a machine on it, or pick another runner#{elsewhere}."
      when :all_failed
        machines = availability.failed
        listed = machines.map { |machine| "#{label(machine)} (#{out_of_rotation_reason(machine)})" }
        "Runner \"#{runner.name}\" has no machine that can take a session: " \
          "#{machines.one? ? 'its machine is out of rotation' : 'every machine is out of rotation'}: #{listed.join('; ')}. " \
          "A failed machine stays out until it is revoked: revoke it on the runner page and register the host again with Add machine, or pick another runner#{elsewhere}."
      else
        raise ArgumentError, "runner \"#{runner.name}\" is available"
      end
    end

    def label(environment)
      environment.display_name.presence || environment.key
    end

    # "<class>: <message>" of an op result that carries an error.
    def failure_text(result)
      error = result&.dig("error") || {}
      [ error["class"], error["message"] ].compact_blank.join(": ").presence || "no reason given"
    end

    def out_of_rotation_reason(machine)
      machine.state_reason.presence || "no reason recorded"
    end
    private_class_method :out_of_rotation_reason
  end
end
