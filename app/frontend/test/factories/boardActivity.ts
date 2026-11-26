import type BoardActivity from '@/types/generated/BoardActivity';

// The `: BoardActivity` return annotation is the compile-time drift contract: if Typelizer
// regenerates BoardActivity with a changed/added required field, this factory stops compiling.
export const buildBoardActivity = (overrides: Partial<BoardActivity> = {}): BoardActivity => ({
  id: 31,
  eventType: 'task_updated',
  actorId: 1,
  actorType: 'human',
  boardTaskId: 1,
  createdAt: '2026-01-02T00:00:00Z',
  metadata: {},
  changedFields: [],
  actorName: 'Dana Scout',
  description: "Dana Scout updated 'Wire up authentication'",
  ...overrides,
});
