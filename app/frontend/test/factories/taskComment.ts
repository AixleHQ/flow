import type TaskComment from '@/types/generated/TaskComment';

// The `: TaskComment` return annotation is the compile-time drift contract: if Typelizer
// regenerates TaskComment with a changed/added required field, this factory stops compiling.
export const buildTaskComment = (overrides: Partial<TaskComment> = {}): TaskComment => ({
  id: 9,
  body: 'Looks good to me',
  authorId: 1,
  authorType: 'human',
  tags: null,
  createdAt: '2026-01-02T00:00:00Z',
  // optional (?) computed attribute — realistic value, no compile-time guarantee
  authorName: 'Dana Scout',
  ...overrides,
});
