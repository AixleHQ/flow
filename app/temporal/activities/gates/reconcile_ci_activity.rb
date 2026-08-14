# frozen_string_literal: true

module Activities
  module Gates
    # Reconciles pending CI gates against their provider — the recovery path for a
    # gate whose resolving webhook never arrived. Driven by
    # `Workflows::GateReconciliationWorkflow` on a Temporal schedule.
    #
    # A thin driver: every decision (which gates are due, what the provider says,
    # resolve vs. leave waiting vs. mark stale) lives in `GateReconciler` and is
    # unit-tested there.
    #
    # Retries are safe. Claiming is FOR UPDATE SKIP LOCKED and each gate's
    # transition is a one-way pending → resolved/stale move, so a re-run only ever
    # looks at gates the previous attempt did not finish.
    class ReconcileCiActivity < ::Activities::Base
      def run(_input = nil)
        counts = ::GateReconciler.reconcile_all

        log(:info, "checked #{counts[:checked]} pending CI gates: resolved #{counts[:resolved]}, " \
                   "stale #{counts[:stale]}, still waiting #{counts[:waiting]}, errors #{counts[:errors]}")

        counts
      end
    end
  end
end
