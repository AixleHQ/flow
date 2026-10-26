import type { ChatChannel } from './types';

// Teams channel names repeat from team to team ("General"), so a channel shown on its own carries its team.
export function channelName(channel: Pick<ChatChannel, 'label' | 'team_name'>): string {
  return channel.team_name ? `${channel.team_name} / ${channel.label}` : channel.label;
}
