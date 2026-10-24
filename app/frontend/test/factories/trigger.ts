import type { Trigger } from 'shared/resources/triggers/types';

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
