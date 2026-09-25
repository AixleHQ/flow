import type TaskWorkflowRun from 'types/generated/TaskWorkflowRun';

// Run states that mean "this run has not settled yet". `queued` belongs here:
// the run is waiting for a session slot and will proceed on its own, so the
// ticket is in flight — unlike a pending gate, which needs a human and
// deliberately clears the active flag below.
export const WORKFLOW_ACTIVE_STATES = new Set(['pending', 'running', 'paused', 'queued']);

// Step states that mean "there is something live to look at right now".
const STEP_ACTIVE_STATES = new Set(['running', 'waiting_input']);

// A run has one session per step, so "jump into the session" needs a single target.
// Prefer the session of a step that is still active — that is the one the user is
// after when a run is in flight — and otherwise fall back to the most recent step
// that ever got a session. Returns null when the run has no session at all, which
// is what keeps the control from rendering (AC-4).
export function runSessionId(run: TaskWorkflowRun): number | null {
  const steps = run.steps ?? [];
  const active = [...steps].reverse().find((s) => STEP_ACTIVE_STATES.has(s.state) && s.terminalSessionId != null);
  if (active) return active.terminalSessionId ?? null;
  const last = [...steps].reverse().find((s) => s.terminalSessionId != null);
  return last?.terminalSessionId ?? null;
}

// Helper to get workflow status indicator color
export const workflowStatusColor = (state: string): string => {
  // Waiting for a session slot is in flight but not working, and it reads as
  // `info` everywhere else in the app — the sessions list already shows QUEUED
  // in blue, so the board says the same thing. Checked before the active branch,
  // which would otherwise paint it amber like a run that is actually executing.
  if (state === 'queued') return 'var(--app-info-fg)';
  if (WORKFLOW_ACTIVE_STATES.has(state)) return 'var(--app-warning-fg)';
  if (state === 'failed') return 'var(--app-danger-fg)';
  if (state === 'completed' || state === 'succeeded') return 'var(--app-success-fg)';
  return 'var(--app-text-tertiary)';
};
