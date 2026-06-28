import type { SharedPermissions, SharedProps, SharedSettings, SharedUser } from 'shared/ui';

// Every authenticated page renders inside AuthLayout, which reads currentUser/flash/projects/
// permissions/settings off usePage().props. Without currentUser the layout short-circuits to a
// FullPageLoader (the page content never mounts), and `flash` is dereferenced unguarded. So page
// tests must seed these. buildSharedProps() is the canonical, type-checked default — spread it into
// renderPage(..., { props: { ...buildSharedProps(), ...pageSpecificProps } }) or use renderAuthedPage().

export const buildSharedUser = (overrides: Partial<SharedUser> = {}): SharedUser => ({
  id: 1,
  email: 'test@example.com',
  name: 'Test User',
  role: 'admin',
  state: 'active',
  position: null,
  preferredAgentLanguage: 'en',
  selectedAgents: [],
  onboardingState: 'completed',
  onboardingCompletedAt: '2026-01-01T00:00:00Z',
  defaultAgentCredentialId: null,
  defaultAgentRuntime: null,
  configuredAgents: [],
  agentCredentials: [],
  company: {
    id: 1,
    name: 'Test Company',
    emailDomain: 'example.com',
    logoUrl: null,
    primaryColor: null,
    secondaryColor: null,
  },
  ...overrides,
});

export const buildSharedSettings = (overrides: Partial<SharedSettings> = {}): SharedSettings => ({
  env: 'test',
  domain: 'localhost',
  githubAppSlug: null,
  sentryFrontendDsn: null,
  appVersion: 'test',
  ...overrides,
});

export const buildSharedPermissions = (overrides: Partial<SharedPermissions> = {}): SharedPermissions => ({
  isAdmin: true,
  canManageMembers: true,
  canManageProjects: true,
  ...overrides,
});

export const buildSharedProps = (overrides: Partial<SharedProps> = {}): SharedProps => ({
  currentUser: buildSharedUser(),
  flash: {},
  projects: [],
  permissions: buildSharedPermissions(),
  settings: buildSharedSettings(),
  ...overrides,
});
