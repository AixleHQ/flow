import type BoardTask from '@/types/generated/BoardTask';

export const buildBoardTask = (overrides: Partial<BoardTask> = {}): BoardTask => ({
  id: 1,
  title: 'Task',
  description: null,
  taskType: 'feature',
  priority: null,
  assigneeId: null,
  boardColumnId: 10,
  position: 0,
  parentTaskId: null,
  tags: null,
  createdAt: '2026-06-25T00:00:00Z',
  updatedAt: '2026-06-25T00:00:00Z',
  // computed Alba attributes — emitted as `unknown` by Typelizer
  assigneeName: 'Ada',
  archived: false,
  commentsCount: 3,
  childrenCount: 0,
  assetsCount: 0,
  recentWorkflowRuns: [],
  pendingGates: [],
  ...overrides,
});
