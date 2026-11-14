# frozen_string_literal: true

module Runners
  # The periodic check that sets each live runner's health status
  # (docs/design/agent-runtimes/DESIGN.md §2.5): the type's adapter works out
  # a status and a reason (`Adapter#check_health`), and this applies it through
  # RunnerStateMachine (`mark_connected`, `mark_degraded`, `mark_unreachable`).
  # Nothing else sets that status: not the gateway when a heartbeat arrives, and
  # not a machine's registration, so it may lag by up to the schedule's minute.
  #
  #   Runners::HealthCheck.run!   # RunnerHealthCheckWorkflow, every minute
  #
  # A disabled, revoked or deleted runner is not checked (Runner.live), and one
  # that changes meanwhile is left as it is: the status is applied under the
  # runner's row lock, on the row as it is then. The launch's refusal does not
  # read this status; it reads the machines' availability (Runners::Machines).
  module HealthCheck
    module_function

    # Checks every live runner. One that fails is logged and does not stop the
    # others. Answers how many were checked, how many changed and how many failed.
    def run!(now: Time.current)
      counts = { checked: 0, changed: 0, failed: 0 }
      Runner.live.find_each do |runner|
        counts[:checked] += 1
        counts[:changed] += 1 if check!(runner, now: now)
      rescue StandardError => e
        counts[:failed] += 1
        Rails.logger.error("[Runners::HealthCheck] runner #{runner.id}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e, extra: { runner_id: runner.id })
      end
      counts
    end

    # Checks one runner and applies the result. Answers whether its status or
    # its reason changed.
    def check!(runner, now: Time.current)
      health = Adapter.for(runner).check_health(runner, now: now)
      runner.with_lock { apply(runner, health) }
    end

    # `runner` is locked and reloaded. A runner that is no longer live, or whose
    # first machine has not registered (`pending`), keeps its status.
    def apply(runner, health)
      return false unless runner.status.to_sym.in?(RunnerStateMachine::HEALTH_STATES)
      return false if health.status == "pending"

      if runner.status == health.status
        return false if runner.status_reason == health.reason

        runner.refresh_status_reason!(health.reason)
        return true
      end

      case health.status
      when "connected" then runner.mark_connected!
      when "degraded" then runner.mark_degraded!(health.reason)
      when "unreachable" then runner.mark_unreachable!(health.reason)
      else raise ArgumentError, "unknown health status #{health.status.inspect}"
      end
      true
    end
  end
end
