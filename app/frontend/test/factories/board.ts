import type Board from '@/types/generated/Board';

// The `: Board` return annotation is the compile-time drift contract: if Typelizer
// regenerates Board with a changed/added required field, this factory stops compiling.
export const buildBoard = (overrides: Partial<Board> = {}): Board => ({
  id: 11,
  name: 'Project Board',
  presetOrigin: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});
