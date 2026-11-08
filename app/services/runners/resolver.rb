# frozen_string_literal: true

module Runners
  # Decides, at launch, whether a run or a session may go to the runner it names
  # (docs/design/agent-runtimes/DESIGN.md §3.4, §8). It runs where a run is
  # dispatched, before a step session is built, and when a standalone session is
  # created, so a runner that changed since it was picked is checked again: the
  # flag for the company, visibility to the project, and status.
  #
  # A record with no runner is hosted and returns nil without reading anything,
  # which keeps the hosted path free of the flag (§12.3). A runner that passes
  # every check is returned; every other outcome is a refusal, and nothing falls
  # back to hosted. A `manual` runner with no registered machine, or whose every
  # machine failed its reset, is refused as unreachable (§8); one whose machines
  # are all busy is not: its session waits for a free machine at create_container
  # (Runners::Machines).
  #
  #   Runners::Resolver.resolve!(run)  # => nil (hosted), the Runner, or raises Refused
  module Resolver
    class Refused < StandardError
      attr_reader :reason

      def initialize(reason, message)
        @reason = reason
        super(message)
      end
    end

    UNAVAILABLE = "runner_unavailable"
    FORBIDDEN = "runner_forbidden"
    UNREACHABLE = Machines::UNREACHABLE
    REASONS = [ UNAVAILABLE, FORBIDDEN, UNREACHABLE ].freeze

    module_function

    # `pick_from` names where another runner is picked, for the message: the
    # workflow for a run and its steps, the session form for a standalone session.
    def resolve!(record, pick_from: "on the workflow")
      return nil if record.runner_id.nil?

      project = record.project
      unless Feature.enabled?(:external_runners, company: project&.company)
        raise Refused.new(UNAVAILABLE, Selection::NOT_ENABLED)
      end

      # Looked up through the tenant boundary, never through `record.runner`: a
      # stale or bypassed id that names another project's or company's runner
      # finds nothing, and the message names only the id the record already holds.
      runner = project && TenantScope.owned(Runner, project: project).find_by(id: record.runner_id)
      if runner.nil?
        raise Refused.new(FORBIDDEN, "Runner #{record.runner_id} is not available to project #{project&.name}.")
      end

      check_status!(runner, pick_from)
      availability = Machines.availability(runner)
      raise Refused.new(UNREACHABLE, Machines.unavailable_message(runner, availability, pick_from)) unless availability.available?

      runner
    end

    def check_status!(runner, pick_from)
      if runner.deleted?
        raise Refused.new(UNAVAILABLE, "Runner \"#{runner.name}\" is deleted. Pick another runner #{pick_from}.")
      elsif runner.revoked?
        raise Refused.new(UNAVAILABLE, "Runner \"#{runner.name}\" is revoked. Pick another runner #{pick_from}.")
      elsif runner.disabled?
        raise Refused.new(UNAVAILABLE, "Runner \"#{runner.name}\" is disabled. Re-enable it or pick another runner #{pick_from}.")
      end
    end
  end
end
