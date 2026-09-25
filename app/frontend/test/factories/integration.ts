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
  azureAuthMode: null,
  azureOrganization: null,
  azureProjectName: null,
  azureIdentity: null,
  azureUrl: null,
  installationId: null,
  githubAuthMode: null,
  githubUrl: null,
  coderUrl: null,
  coderDefaultTemplate: null,
  coderMachinePrefix: null,
  coderLockTtlMinutes: null,
  slackRequestUrl: null,
  // Always present, empty for every provider but Azure DevOps: the operation
  // profile and the covered projects are lists the server always serializes,
  // not optional fields.
  azureCapabilities: [],
  azureProjectIds: [],
  azureProjectDisplayNames: [],
  // Always present, empty unless this is a GitHub connection on a classic
  // personal access token — the only case GitHub reports scopes for.
  githubTokenScopes: [],
  ...overrides,
});
