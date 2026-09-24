import type { Company, CurrentUser, Membership } from '@/types/generated';

import type { SharedPermissions, SharedProps, SharedSettings } from 'shared/ui';

// Every authenticated page renders inside AuthLayout, which reads currentUser/flash/projects/
// permissions/settings off usePage().props. Without currentUser the layout short-circuits to a
// FullPageLoader (the page content never mounts), and `flash` is dereferenced unguarded. So page
// tests must seed these. buildSharedProps() is the canonical, type-checked default — spread it into
// renderPage(..., { props: { ...buildSharedProps(), ...pageSpecificProps } }) or use renderAuthedPage().

const buildSharedCompany = (overrides: Partial<Company> = {}): Company => ({
  id: 1,
  name: 'Test Company',
  emailDomain: 'example.com',
  logoUrl: null,
  primaryColor: null,
  secondaryColor: null,
  ...overrides,
});

const buildSharedMembership = (overrides: Partial<Membership> = {}): Membership => ({
  id: 1,
  role: 'admin',
  state: 'active',
  company: buildSharedCompany(),
  ...overrides,
});

export const buildSharedUser = (overrides: Partial<CurrentUser> = {}): CurrentUser => ({
  id: 1,
  email: 'test@example.com',
  name: 'Test User',
  state: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  position: null,
  preferredAgentLanguage: 'en',
  selectedAgents: [],
  onboardingState: 'completed',
  onboardingCompletedAt: '2026-01-01T00:00:00Z',
  defaultAgentCredentialId: null,
  defaultAgentRuntime: null,
  configuredAgents: [],
  agentCredentials: [],
  shareActiveSessions: false,
  shareCompletedSessions: true,
  needsAgentSetup: false,
  currentRole: 'admin',
  currentCompany: buildSharedCompany(),
  memberships: [buildSharedMembership()],
  ...overrides,
});

const buildSharedSettings = (overrides: Partial<SharedSettings> = {}): SharedSettings => ({
  env: 'test',
  domain: 'localhost',
  githubAppSlug: null,
  appVersion: 'test',
  sentryFrontendDsn: null,
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
