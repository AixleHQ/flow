import type ProjectTracker from '@/types/generated/ProjectTracker';

// The `: ProjectTracker` return annotation is the drift contract with the generated type.
export const buildProjectTracker = (overrides: Partial<ProjectTracker> = {}): ProjectTracker => ({
  id: 5,
  handle: 'customer-platform',
  name: 'Customer Platform',
  provider: 'azure_devops',
  externalScopeId: '6ce954b1-ce1f-45d1-b94d-e6bf2464ba2c',
  primary: true,
  access: 'read_write',
  status: 'active',
  integrationId: 42,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  integrationName: 'acme/Customer Platform',
  usable: true,
  mentionsRecognized: true,
  ...overrides,
});
