import type TaskAsset from '@/types/generated/TaskAsset';

// The `: TaskAsset` return annotation is the compile-time drift contract: if Typelizer
// regenerates TaskAsset with a changed/added required field, this factory stops compiling.
export const buildTaskAsset = (overrides: Partial<TaskAsset> = {}): TaskAsset => ({
  id: 31,
  name: 'mockup.png',
  tags: [],
  authorId: 1,
  authorType: 'human',
  createdAt: '2026-01-02T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  fileUrl: 'https://files.example.com/mockup.png',
  fileSize: 4096,
  contentType: 'image/png',
  // optional (?) computed attribute — realistic value, no compile-time guarantee
  shareUrl: null,
  ...overrides,
});
