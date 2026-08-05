import type Project from '@/types/generated/Project';

// The `: Project` return annotation is the compile-time drift contract: if Typelizer
// regenerates Project with a changed/added required field, this factory stops compiling.
// (Computed Alba fields are emitted as `unknown`, so concrete values here still satisfy the type
//  but carry no compile-time guarantee — see the research doc's "unknown gap".)
export const buildProject = (overrides: Partial<Project> = {}): Project => ({
  id: 1,
  name: 'Acme',
  description: null,
  slug: 'acme',
  state: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  collaboratorsCount: 0,
  membersCount: 1,
  lastActivityAt: null,
  sessionsCount: 0,
  workflowsCount: 0,
  boardTasksCount: 0,
  members: [],
  ...overrides,
});
