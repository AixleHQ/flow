// A Slack or Teams channel connected to the company (Chat::ChannelAccess.describe).
// snake_case: it arrives over the JSON API, not as Inertia props.
export interface ChatChannel {
  // The registry id, not the messenger's own channel id.
  id: number;
  name: string | null;
  label: string;
  kind: string;
  team_name: string | null;
  provider: string;
}

export interface ConnectedChatChannel extends ChatChannel {
  connected_at: string | null;
  requested_by: string | null;
  posted_by: string | null;
  // The bot's confirmation in the channel: a Slack permalink, or the Teams message the code was posted in.
  confirmation_url: string | null;
}

export type ChatConnectCodeState = 'pending' | 'redeemed' | 'expired';

// The server leaves out every field that has no value.
export interface ChatConnectCode {
  id: number;
  provider: string;
  state: ChatConnectCodeState;
  expires_at: string;
  // The channel the code is for, as the server understood what was typed: Slack `#deploys`, Teams `Sales / General`.
  channel_name: string;
  trigger_id?: number;
  failure_reason?: string;
  bot_name?: string;
  mention?: string;
  invite: string;
  // The code and the line to post are in the create response only.
  command?: string;
  code?: string;
  channel?: ChatChannel;
}
