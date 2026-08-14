# frozen_string_literal: true

module Ci
  # What one look at a CI provider told us about a gate's run. The vocabulary the
  # provider adapters answer in and the only thing `GateReconciler` branches on,
  # so a new provider never has to teach the reconciler its own status names.
  #
  #   completed     → provider has a verdict (`conclusion` carries it verbatim)
  #   in_progress   → not finished; the webhook may still arrive
  #   unresolvable  → the run/PR/pipeline/repository cannot be read at all, so no
  #                   webhook can ever resolve this gate (deleted run, unlinked
  #                   repository, integration removed)
  #   unavailable   → we could not tell (rate limit, 5xx, bad credentials);
  #                   transient, so try again on the next sweep
  #
  # `detail` is operator-facing text: it ends up in the gate's reconciliation log
  # and, for a stale gate, in its `diagnostic_reason`.
  ProbeResult = Struct.new(:state, :conclusion, :detail, keyword_init: true) do
    class << self
      def completed(conclusion, detail = nil)
        new(state: :completed, conclusion: conclusion.to_s.presence, detail: detail)
      end

      def in_progress(detail = nil)
        new(state: :in_progress, detail: detail)
      end

      def unresolvable(detail)
        new(state: :unresolvable, detail: detail)
      end

      def unavailable(detail)
        new(state: :unavailable, detail: detail)
      end
    end

    def completed?
      state == :completed
    end

    def in_progress?
      state == :in_progress
    end

    def unresolvable?
      state == :unresolvable
    end

    def unavailable?
      state == :unavailable
    end
  end
end
