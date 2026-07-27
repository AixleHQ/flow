import type SubStepRun from '@/types/generated/SubStepRun';

// The `: SubStepRun` return annotation is the compile-time drift contract: if Typelizer
// regenerates SubStepRun with a changed/added required field, this factory stops compiling.
export const buildSubStepRun = (overrides: Partial<SubStepRun> = {}): SubStepRun => ({
  id: 1,
  state: 'completed',
  startedAt: '2026-01-01T00:00:00Z',
  completedAt: '2026-01-01T00:00:30Z',
  // optional (?) computed attributes — realistic values, no compile-time guarantee.
  // `subStepName` is `string | undefined` (not nullable): omit for "absent".
  subStepName: 'Fetch data',
  ...overrides,
});
