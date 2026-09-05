import type WorkflowRun from '@/types/generated/WorkflowRun';

// The `: WorkflowRun` return annotation is the compile-time drift contract: if Typelizer
// regenerates WorkflowRun with a changed/added required field, this factory stops compiling.
export const buildWorkflowRun = (overrides: Partial<WorkflowRun> = {}): WorkflowRun => ({
  id: 42,
  workflowId: 9,
  projectId: 7,
  userId: 1,
  state: 'running',
  startedAt: null,
  completedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  failureReason: null,
  failedAgentCredentialId: null,
  mode: 'interactive',
  stepsCompleted: 1,
  stepsTotal: 3,
  costCents: 0,
  totalTokens: 0,
  stepRuns: [],
  controllableByViewer: true,
  // optional (?) computed attributes — realistic values, no compile-time guarantee.
  // failedAccountName is `string | undefined` (not nullable): omit for "absent".
  workflowName: 'Nebula Pipeline',
  userName: 'Dana Operator',
  agentType: 'codex',
  ...overrides,
});
