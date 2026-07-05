import type BoardPreset from '@/types/generated/BoardPreset';

// The `: BoardPreset` return annotation is the compile-time drift contract: if Typelizer
// regenerates BoardPreset with a changed/added required field, this factory stops compiling.
export const buildBoardPreset = (overrides: Partial<BoardPreset> = {}): BoardPreset => ({
  key: 'simple_kanban',
  displayName: 'Simple Kanban',
  columns: ['Todo', 'Doing', 'Done'],
  ...overrides,
});
