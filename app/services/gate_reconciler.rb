# frozen_string_literal: true

# The reconciliation side of CI gates. Webhooks are the happy path: a completed
# check suite / workflow run / pipeline arrives, `GateService` resolves the gate,
# and the column auto-trigger re-evaluates. That path has no recovery of its own —
# a delivery that never arrives, a run that was deleted, a repository that was
# detached from the project all leave the gate `pending` forever, which stops the
# task's automation permanently and silently.
#
# This sweep — driven by a Temporal cron (see `Workflows::GateReconciliationWorkflow`)
# — closes that hole. For every pending CI gate past the grace window it asks the
# provider what actually happened (`Ci::GateProbe`) and then does exactly one of
# four things:
#
#   completed     → resolve with the provider's own verdict, same as the webhook
#                   would have (`TaskService.resolve_gate_by_reconciliation`)
#   in_progress   → nothing, unless the gate's TTL has run out
#   unresolvable  → mark stale immediately; no webhook can ever resolve it
#   unavailable   → nothing, unless the gate's TTL has run out (transient)
#
# and records the outcome on the gate either way, so a gate's
# `reconciliation_log` explains what was seen and when.
#
# It never invents a passing conclusion: an expired or unresolvable gate becomes
# `stale` with a diagnostic reason, which unblocks the task's automation but is
# recorded as "we do not know", never as "CI was green".
class GateReconciler
  class << self
    # Sweep the reconcilable gates and act on each. Rows are claimed under
    # FOR UPDATE SKIP LOCKED in a short transaction (so two drainers never probe
    # the same gate) and the lock is released before the provider call — an HTTP
    # request must not run while holding row locks.
    #
    # Returns { checked:, resolved:, stale:, waiting:, errors: } counts.
    def reconcile_all(limit: Gate.reconcile_batch_size, now: Time.current)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      counts = { checked: 0, resolved: 0, stale: 0, waiting: 0, errors: 0 }

      claim_ids(limit: limit, now: now).each do |id|
        gate = Gate.find_by(id: id)
        next if gate.nil? || !gate.pending?

        counts[:checked] += 1
        counts[reconcile(gate, now: now)] += 1
      end

      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
      Rails.logger.info(
        "[GateReconciler] checked=#{counts[:checked]} resolved=#{counts[:resolved]} " \
        "stale=#{counts[:stale]} waiting=#{counts[:waiting]} errors=#{counts[:errors]} in #{elapsed}s"
      )

      counts.merge(elapsed: elapsed)
    end

    # Reconcile one gate. Returns the counter key for what happened:
    # :resolved, :stale, :waiting or :errors.
    def reconcile(gate, now: Time.current)
      result = Ci::GateProbe.new(gate).call

      case result.state
      when :completed    then resolve(gate, result)
      when :unresolvable then mark_stale(gate, "unresolvable", result, now: now)
      else                    keep_waiting(gate, result, now: now)
      end
    rescue StandardError => e
      # One bad gate must not end the sweep. The gate keeps its pending status and
      # is retried next tick; its TTL is still the backstop.
      Rails.logger.error("[GateReconciler] gate ##{gate.id} failed: #{e.class}: #{e.message}")
      :errors
    end

    private

    def claim_ids(limit:, now:)
      Gate.transaction do
        Gate
          .reconcilable(now)
          .limit(limit)
          .lock("FOR UPDATE SKIP LOCKED")
          .pluck(:id)
      end
    end

    # Act first, then log the outcome: an audit entry that says "resolved" for a
    # transition that then failed would be worse than no entry at all.
    def resolve(gate, result)
      TaskService.resolve_gate_by_reconciliation(
        gate: gate,
        resolution_data: resolution_data_for(gate, result)
      )
      gate.record_reconciliation!(outcome: "resolved:#{result.conclusion}", detail: result.detail)
      Rails.logger.info("[GateReconciler] gate ##{gate.id} resolved as #{result.conclusion} by reconciliation")
      :resolved
    end

    # A gate the provider says is still running (or that we could not read this
    # time) is left alone until its TTL runs out — the webhook is still the
    # cheapest way for it to resolve.
    def keep_waiting(gate, result, now:)
      return mark_stale(gate, "ttl_expired", result, now: now) if gate.expired?(now)

      gate.record_reconciliation!(outcome: result.state.to_s, detail: result.detail, now: now)
      :waiting
    end

    def mark_stale(gate, kind, result, now:)
      reason = stale_reason(gate, kind, result, now: now)
      TaskService.mark_gate_stale(gate: gate, reason: reason, detail: result.detail, now: now)
      gate.record_reconciliation!(outcome: "stale:#{kind}", detail: result.detail, now: now)
      Rails.logger.warn("[GateReconciler] gate ##{gate.id} marked stale: #{reason} (#{result.detail})")
      :stale
    end

    # Operator-facing, and deliberately specific about which of the two ways a
    # gate can go stale happened — they need different fixes.
    def stale_reason(gate, kind, result, now:)
      case kind
      when "unresolvable"
        "CI #{gate.reference_type.to_s.humanize.downcase} #{gate.reference} on " \
        "#{gate.metadata['repo_full_name']} cannot be read: #{result.detail}"
      else
        "no CI result after #{ActiveSupport::Duration.build(gate.age_seconds(now)).inspect} " \
        "(TTL #{Gate.ttl.inspect}); last probe: #{result.detail.presence || result.state}"
      end
    end

    # GitHub reports a `conclusion`, GitLab a pipeline `status` — the webhook path
    # records each under its own key (see `GateService`), so reconciliation does
    # too. Anything reading a gate's outcome (`Gate#conclusion`) accepts both.
    def resolution_data_for(gate, result)
      verdict_key = gate.provider == "gitlab" ? "status" : "conclusion"

      {
        verdict_key => result.conclusion,
        "source" => "reconciliation",
        "detail" => result.detail
      }.compact
    end
  end
end
