import type TaskStatistics from '@/types/generated/TaskStatistics';

// The `: TaskStatistics` return annotation is the compile-time drift contract: if Typelizer
// regenerates TaskStatistics with a changed/added required field, this factory stops compiling.
export const buildTaskStatistics = (overrides: Partial<TaskStatistics> = {}): TaskStatistics => ({
  costTotals: { totalCostCents: 250 },
  tokenTotals: { totalTokens: 12500 },
  timeTotals: { totalDurationSeconds: 95 },
  gateStats: [],
  workflowBreakdowns: [],
  ...overrides,
});
