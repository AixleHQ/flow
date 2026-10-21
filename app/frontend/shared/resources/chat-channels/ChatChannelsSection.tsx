import { ActionIcon, Box, Button, Group, Loader, Stack, Text, Tooltip } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconPlus, IconUnlink } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { apiMutate, apiRequest } from 'shared/lib/apiFetch';
import { formatDateMedium } from 'shared/lib/formatDate';
import { CHAT_PROVIDER_LABELS } from 'shared/resources/triggers/describeTrigger';
import { apiV1ProjectChatChannelPath, apiV1ProjectChatChannelsPath } from 'shared/routes';

import { channelName } from './channelName';
import { ConnectChannelModal } from './ConnectChannelModal';
import type { ConnectedChatChannel } from './types';

interface ChatChannelsSectionProps {
  projectId: number;
  provider: string;
  // Connecting and disconnecting; the list itself is for everyone on the project.
  canEdit: boolean;
}

function provenance(channel: ConnectedChatChannel): string {
  return [
    channel.requested_by && `connected by ${channel.requested_by}`,
    channel.posted_by && `posted by ${channel.posted_by}`,
    channel.connected_at && formatDateMedium(channel.connected_at),
  ]
    .filter(Boolean)
    .join(' · ');
}

/** The company's channels in one messenger: what its chat triggers can listen to and its workflows post in. */
export const ChatChannelsSection = ({ projectId, provider, canEdit }: ChatChannelsSectionProps) => {
  const [channels, setChannels] = useState<ConnectedChatChannel[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const label = CHAT_PROVIDER_LABELS[provider] ?? provider;

  const load = useCallback(async () => {
    try {
      const data = await apiRequest<{ channels: ConnectedChatChannel[] }>(
        apiV1ProjectChatChannelsPath(projectId, { provider }),
      );
      setChannels(data.channels);
      setFailed(false);
    } catch {
      setFailed(true);
    }
  }, [projectId, provider]);

  useEffect(() => {
    load();
  }, [load]);

  const disconnect = (channel: ConnectedChatChannel) => {
    const name = channelName(channel);
    modals.openConfirmModal({
      title: 'Disconnect channel',
      children: (
        <Text size="sm">
          Disconnect <b>{name}</b> from your company? Chat triggers listening there switch off until they get another
          channel, and workflows can no longer post there. The bot says so in the channel.
        </Text>
      ),
      labels: { confirm: 'Disconnect', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        const ok = await apiMutate(
          apiV1ProjectChatChannelPath(projectId, channel.id),
          { method: 'DELETE' },
          'The channel could not be disconnected',
        );
        if (!ok) return;
        setChannels((prev) => prev?.filter((c) => c.id !== channel.id) ?? prev);
        notifications.show({ message: `${name} disconnected`, color: 'green' });
      },
    });
  };

  return (
    <Box py={4}>
      <Group justify="space-between" mb={6}>
        <Text fz={12} fw={600} c="var(--app-text-secondary)">
          Channels
        </Text>
        {canEdit && (
          <Button
            size="compact-xs"
            variant="light"
            leftSection={<IconPlus size={12} />}
            onClick={() => setConnecting(true)}
          >
            Connect a channel
          </Button>
        )}
      </Group>
      {channels === null ? (
        failed ? (
          <Text fz={12} c="var(--app-danger-fg)">
            The channels could not be loaded. Reload the page to try again.
          </Text>
        ) : (
          <Loader size="xs" aria-label={`Loading ${label} channels`} />
        )
      ) : channels.length === 0 ? (
        <Text fz={12} c="dimmed">
          No channel is connected yet. Chat triggers listen in, and workflows post to, connected channels only.
        </Text>
      ) : (
        <Stack component="ul" gap={4} m={0} p={0} style={{ listStyle: 'none' }} aria-label={`${label} channels`}>
          {channels.map((channel) => (
            <Group component="li" key={channel.id} gap="sm" wrap="nowrap" justify="space-between">
              <Box style={{ minWidth: 0 }}>
                <Text fz={13} fw={500} truncate>
                  {channelName(channel)}
                </Text>
                <Text fz={11} c="dimmed" truncate>
                  {provenance(channel)}
                </Text>
              </Box>
              {canEdit && (
                <Tooltip label="Disconnect">
                  <ActionIcon
                    aria-label={`Disconnect ${channelName(channel)}`}
                    variant="subtle"
                    size="sm"
                    color="red"
                    onClick={() => disconnect(channel)}
                  >
                    <IconUnlink size={16} />
                  </ActionIcon>
                </Tooltip>
              )}
            </Group>
          ))}
        </Stack>
      )}
      {canEdit && (
        <ConnectChannelModal
          projectId={projectId}
          provider={provider}
          opened={connecting}
          onClose={() => setConnecting(false)}
          onConnected={() => load()}
        />
      )}
    </Box>
  );
};
