import type BoardColumn from '@/types/generated/BoardColumn';

// The `: BoardColumn` return annotation is the compile-time drift contract: if Typelizer
// regenerates BoardColumn with a changed/added required field, this factory stops compiling.
// NOTE: Typelizer emits `workflowBinding`'s nested keys as snake_case (workflow_id / trigger_mode /
// cooldown_seconds), unlike the standalone ColumnWorkflowBinding resource (camelCase).
export const buildBoardColumn = (overrides: Partial<BoardColumn> = {}): BoardColumn => ({
  id: 100,
  name: 'Backlog',
  position: 0,
  purpose: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  tasksCount: 0,
  workflowBinding: null,
  ...overrides,
});
