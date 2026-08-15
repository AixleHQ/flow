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
    # Retries are safe. Claiming is durable (a claimed gate leaves the due set for a
    # grace window) and each gate's transition is a compare-and-set on a still-
    # pending row, so a re-run — or a retry overlapping the attempt it replaces —
    # only ever finishes gates the previous attempt did not.
    class ReconcileCiActivity < ::Activities::Base
      def run(_input = nil)
        counts = ::GateReconciler.reconcile_all

        log(:info, "checked #{counts[:checked]} pending CI gates: resolved #{counts[:resolved]}, " \
                   "stale #{counts[:stale]}, still waiting #{counts[:waiting]}, " \
                   "superseded #{counts[:skipped]}, errors #{counts[:errors]}")

        counts
      end
    end
  end
end
