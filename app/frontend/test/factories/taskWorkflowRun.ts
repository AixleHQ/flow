import type TaskWorkflowRun from '@/types/generated/TaskWorkflowRun';

// The `: TaskWorkflowRun` return annotation is the compile-time drift contract: if Typelizer
// regenerates TaskWorkflowRun with a changed/added required field, this factory stops compiling.
export const buildTaskWorkflowRun = (overrides: Partial<TaskWorkflowRun> = {}): TaskWorkflowRun => ({
  id: 55,
  state: 'completed',
  mode: 'auto',
  startedAt: null,
  completedAt: null,
  createdAt: '2026-01-02T00:00:00Z',
  // optional (?) computed attribute — realistic value, no compile-time guarantee
  workflowName: 'Implement Feature',
  ...overrides,
});
