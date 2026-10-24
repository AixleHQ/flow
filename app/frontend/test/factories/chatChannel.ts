import type { ChatChannel, ChatConnectCode, ConnectedChatChannel } from 'shared/resources/chat-channels/types';
import type { ChatConversationOption, ChatProviderOption } from 'shared/resources/triggers/types';

export const buildChatChannel = (overrides: Partial<ChatChannel> = {}): ChatChannel => ({
  id: 11,
  name: 'deploys',
  label: '#deploys',
  kind: 'channel',
  team_name: null,
  provider: 'slack',
  ...overrides,
});

export const buildConnectedChatChannel = (overrides: Partial<ConnectedChatChannel> = {}): ConnectedChatChannel => ({
  ...buildChatChannel(),
  connected_at: '2026-10-22T09:00:00Z',
  requested_by: 'Jane Doe',
  posted_by: 'ivan',
  confirmation_url: null,
  ...overrides,
});

// As the create response sends it: the only one that carries the code and the line to post.
export const buildChatConnectCode = (overrides: Partial<ChatConnectCode> = {}): ChatConnectCode => ({
  id: 31,
  provider: 'slack',
  state: 'pending',
  expires_at: '2026-10-22T10:10:00Z',
  channel_name: '#deploys',
  bot_name: 'aixle-flow',
  mention: '@aixle-flow',
  invite: '/invite @aixle-flow',
  command: 'connect aixle-7F3K9QXM',
  code: 'aixle-7F3K9QXM',
  ...overrides,
});

export const buildChatConversationOption = (
  overrides: Partial<ChatConversationOption> = {},
): ChatConversationOption => ({
  id: 11,
  name: 'deploys',
  label: '#deploys',
  kind: 'channel',
  teamName: null,
  provider: 'slack',
  ...overrides,
});

export const buildChatProviderOption = (overrides: Partial<ChatProviderOption> = {}): ChatProviderOption => ({
  key: 'slack',
  label: 'Slack',
  botName: 'aixle-flow',
  conversations: [],
  ...overrides,
});
