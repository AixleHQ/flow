import { formatElapsedTime } from 'shared/lib/formatElapsedTime';

import type { Gate, Task } from './types';

// What a gate's CI state is, tolerating a payload that predates ciStatus: a gate the server did not
// classify is pending unless it says otherwise.
export function gateCiStatus(gate: Gate): string {
  return gate.ciStatus ?? gate.status ?? 'pending';
}

// The CI verdict a card advertises, from the newest CI gate the task has: which of the four states
// (waiting / passed / failed / stale) it is in, and the one-line reason a reader needs. Stale is its
// own state on purpose — it means "no CI verdict was ever obtained", which is neither a pass nor a
// failure, and it is the state a lost webhook now lands in instead of waiting forever.
export function ciGateSummary(task: Task): { label: string; color: string; tooltip: string } | null {
  const gate = (task.ciGates ?? [])[0];
  if (!gate) return null;

  const kind = gateCiStatus(gate);
  const name = gate.gateType.replace(/_/g, ' ');

  switch (kind) {
    case 'stale':
      return {
        label: 'CI stale',
        color: 'orange',
        tooltip: gate.diagnosticReason
          ? `${name} — stale: ${gate.diagnosticReason}`
          : `${name} — no CI result was ever obtained`,
      };
    case 'failed':
      return {
        label: 'CI failed',
        color: 'red',
        tooltip: `${name} — ${gate.conclusion ?? 'failed'}`,
      };
    case 'succeeded':
      return { label: 'CI passed', color: 'green', tooltip: `${name} — ${gate.conclusion ?? 'success'}` };
    default:
      return {
        label: 'CI pending',
        color: 'yellow',
        tooltip: `${name} — waiting ${formatElapsedTime(gate.createdAt)}${gate.expired ? ' (past its TTL)' : ''}`,
      };
  }
}

// The part of a gate's story its chip does NOT already tell, as a short muted suffix. The state
// itself is the chip's label, so repeating it here would only be noise; age is not — "waiting"
// reads very differently at two minutes and at eleven hours — and neither is a failure that ended
// in something other than a plain failed check (timed out, cancelled, action required).
export function gateDetail(gate: Gate): string | null {
  const kind = gateCiStatus(gate);
  if (kind === 'succeeded') return null;
  if (kind === 'failed') {
    const conclusion = gate.conclusion;
    if (!conclusion || conclusion === 'failure' || conclusion === 'failed') return null;
    return conclusion.replace(/_/g, ' ');
  }

  const elapsed = formatElapsedTime(gate.createdAt);
  if (kind === 'stale') return elapsed;
  return gate.expired ? `${elapsed} · past TTL` : elapsed;
}

// What the chip's tooltip spells out: the gate type the row no longer prints as a pill, plus the
// provider's own conclusion when there is one worth naming — and, for a stale gate, why
// reconciliation gave up. That last one is a sentence of prose, not a label: it rides in the
// tooltip so a stale row stays as compact as every other one, worded the same way the card's CI
// summary chip words it.
export function gateTooltip(gate: Gate): string {
  const name = gate.gateType.replace(/_/g, ' ');
  if (gateCiStatus(gate) === 'stale') {
    return gate.diagnosticReason
      ? `${name} — stale: ${gate.diagnosticReason}`
      : `${name} — stale: no CI result was ever obtained`;
  }
  return gate.conclusion ? `${name} — ${gate.conclusion}` : name;
}

// The provider page a gate row links to: the pull request for a checks gate, the run page for a
// workflow gate. Null when the metadata a link needs was never recorded.
export function gateLink(gate: Gate): { href: string; label: string; kind: 'pr' | 'run' } | null {
  const repo = gate.metadata.repoFullName;
  if (!repo) return null;

  if (gate.gateType === 'github_checks_completed' && gate.metadata.prNumber) {
    return {
      href: `https://github.com/${repo}/pull/${gate.metadata.prNumber}`,
      label: `${repo} #${gate.metadata.prNumber}`,
      kind: 'pr',
    };
  }
  if (gate.gateType === 'github_workflow_completed' && gate.metadata.runId) {
    return {
      href: `https://github.com/${repo}/actions/runs/${gate.metadata.runId}`,
      label: `${repo} #${gate.metadata.runId}`,
      kind: 'run',
    };
  }
  return null;
}
