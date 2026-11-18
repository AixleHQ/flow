import type { Trigger, TriggerRepository } from 'shared/resources/triggers/types';

import { buildChatChannel } from './chatChannel';

export const buildChatTrigger = (overrides: Partial<Trigger> = {}): Trigger => ({
  id: 2,
  kind: 'chat',
  source: 'chat',
  chat_provider: 'slack',
  chat_channel: buildChatChannel(),
  event_type: 'chat.message',
  filter_predicate: { provider: 'slack' },
  status_reporting: 'lifecycle',
  subject_policy: 'none',
  enabled: true,
  ...overrides,
});

export const buildPullRequestTrigger = (overrides: Partial<Trigger> = {}): Trigger => ({
  id: 31,
  kind: 'pull_request',
  source: 'pull_request',
  event_type: 'pull_request.review.submitted',
  repository_id: null,
  aixle_changes: 'ignore',
  filter_predicate: {},
  subject_policy: 'none',
  subject_column_id: null,
  subject_title_template: null,
  enabled: true,
  ...overrides,
});

export const buildTriggerRepository = (overrides: Partial<TriggerRepository> = {}): TriggerRepository => ({
  id: 8,
  fullName: 'acme/storefront',
  provider: 'github',
  mentionsRecognized: true,
  ...overrides,
});
