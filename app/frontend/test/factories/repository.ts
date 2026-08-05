import type Repository from '@/types/generated/Repository';

import { buildIntegration } from './integration';

// The `: Repository` return annotation is the compile-time drift contract: if Typelizer
// regenerates Repository with a changed/added required field, this factory stops compiling.
export const buildRepository = (overrides: Partial<Repository> = {}): Repository => ({
  id: 42,
  fullName: 'acme/payments-api',
  cloneUrl: 'https://github.com/acme/payments-api.git',
  sourceBranch: 'main',
  isPrivate: true,
  description: 'Handles invoices',
  purpose: 'Billing service',
  lastFetchedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  integration: buildIntegration(),
  publicSource: false,
  scopeIndicator: 'project',
  ...overrides,
});
