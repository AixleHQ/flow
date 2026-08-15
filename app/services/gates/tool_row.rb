# frozen_string_literal: true

module Gates
  # The shape a gate takes when an agent reads it over MCP — shared by the
  # personal `list_gates` and the in-session `board_list_gates` so the two
  # cannot drift into describing the same gate differently.
  #
  # Everything a caller needs to tell "CI is still running" from "the webhook
  # never arrived and this gate is now stale", including the reconciliation
  # trail that explains how it got there.
  module ToolRow
    def self.call(gate)
      {
        id: gate.id,
        gate_type: gate.gate_type,
        status: gate.status,
        ci_status: gate.ci_status,
        conclusion: gate.conclusion,
        metadata: gate.metadata,
        source: gate.source,
        creator: gate.creator&.name,
        creator_id: gate.creator_id,
        created_at: gate.created_at,
        resolved_at: gate.resolved_at,
        age_seconds: gate.age_seconds,
        expires_at: gate.expires_at,
        expired: gate.expired?,
        diagnostic_reason: gate.diagnostic_reason,
        last_reconciled_at: gate.last_reconciled_at,
        reconcile_attempts: gate.reconcile_attempts,
        reconciliation_log: gate.reconciliation_log
      }
    end
  end
end
