// The workflow-run payload the board sends alongside a task, plus the state vocabulary
// and lookups that read it. Shared by BoardPage and the task drawer's run components.

export interface TaskWorkflowRun {
  id: number;
  workflowName: string;
  state: string;
  mode: string;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  totalCostCents?: number;
  totalTokens?: number;
  durationSeconds?: number;
  steps?: Array<{
    name: string;
    state: string;
    startedAt: string | null;
    finishedAt: string | null;
    durationSeconds: number | null;
    terminalSessionId?: number | null;
  }>;
}

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
