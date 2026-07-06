import type Integration from '@/types/generated/Integration';

// The `: Integration` return annotation is the compile-time drift contract: if Typelizer
// regenerates Integration with a changed/added required field, this factory stops compiling.
export const buildIntegration = (overrides: Partial<Integration> = {}): Integration => ({
  id: 1,
  name: 'GitHub',
  provider: 'github',
  status: 'active',
  projectId: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  settings: {},
  scopeIndicator: 'company',
  connectedBy: { id: 1, name: 'Ada' },
  ...overrides,
});
