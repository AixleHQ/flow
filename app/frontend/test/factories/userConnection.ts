import type ActAsConsent from '@/types/generated/ActAsConsent';
import type UserConnection from '@/types/generated/UserConnection';

export const buildUserConnection = (overrides: Partial<UserConnection> = {}): UserConnection => ({
  provider: 'github',
  status: 'connected',
  login: 'octo-user',
  name: 'Octo User',
  avatarUrl: null,
  connectedAt: '2026-11-11T10:00:00Z',
  ...overrides,
});

export const buildActAsConsent = (overrides: Partial<ActAsConsent> = {}): ActAsConsent => ({
  projectId: 7,
  projectName: 'Acme',
  inOwnTasks: false,
  inOthersTasks: false,
  ...overrides,
});
