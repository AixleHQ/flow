# frozen_string_literal: true

module Workflows
  # GateReconciliationWorkflow — scheduled sweep that reconciles pending CI gates
  # against their CI provider and expires the ones nothing can resolve (see
  # `GateReconciler`). Wired into `app/temporal/schedules.yml`.
  #
  # The 300s budget is for the provider calls: a batch costs up to one or two HTTP
  # requests per gate, and a backlog is bounded by `gates.reconcile_batch_size`.
  #
  # max_attempts: 2 — the sweep is idempotent, but a second immediate attempt is
  # all that is worth spending: the next tick is minutes away and picks up
  # whatever this one missed.
  class GateReconciliationWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.gates_reconcile_ci_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
