import type StepRun from '@/types/generated/StepRun';

// The `: StepRun` return annotation is the compile-time drift contract: if Typelizer
// regenerates StepRun with a changed/added required field, this factory stops compiling.
export const buildStepRun = (overrides: Partial<StepRun> = {}): StepRun => ({
  id: 101,
  stepId: 1,
  state: 'pending',
  stepNote: null,
  errorMessage: null,
  errorCategory: null,
  terminalSessionId: null,
  startedAt: null,
  completedAt: null,
  allowNonInteractive: false,
  dependsOnStepIds: [],
  dependsOnNames: [],
  subStepRuns: [],
  // optional (?) computed attributes — realistic values, no compile-time guarantee.
  // terminalSessionState/terminalUrl/ideUrl are `string | undefined` (not nullable): omit for "absent".
  stepName: 'Compile Specs',
  stepPosition: 1,
  ...overrides,
});
