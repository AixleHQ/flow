import { ActionIcon, Anchor, Box, Button, Group, Loader, Modal, Stack, Text, Tooltip } from '@mantine/core';
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

interface ChatChannelsModalProps {
  projectId: number;
  provider: string;
  opened: boolean;
  onClose: () => void;
  // Connecting and disconnecting; the list itself is for everyone on the project.
  canEdit: boolean;
}

const MESSENGER_SHORT_NAMES: Record<string, string> = { slack: 'Slack', teams: 'Teams' };

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
export const ChatChannelsModal = ({ projectId, provider, opened, onClose, canEdit }: ChatChannelsModalProps) => {
  const [channels, setChannels] = useState<ConnectedChatChannel[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const label = CHAT_PROVIDER_LABELS[provider] ?? provider;
  const shortName = MESSENGER_SHORT_NAMES[provider] ?? label;

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
    if (!opened) return;
    setChannels(null);
    load();
  }, [opened, load]);

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
    <>
      <Modal opened={opened && !connecting} onClose={onClose} title={`${label} channels`} size="lg">
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Chat triggers listen in, and workflows post to, these channels only. They belong to your company, so every
            project sees the same list.
          </Text>
          {channels === null ? (
            failed ? (
              <Text fz={13} c="var(--app-danger-fg)">
                The channels could not be loaded. Close this and try again.
              </Text>
            ) : (
              <Loader size="sm" aria-label={`Loading ${label} channels`} />
            )
          ) : channels.length === 0 ? (
            <Text fz={13} c="var(--app-text-secondary)">
              No channel is connected yet.
            </Text>
          ) : (
            <Box
              component="ul"
              m={0}
              p={0}
              aria-label={`${label} channels`}
              style={{
                listStyle: 'none',
                border: '1px solid var(--app-border-default)',
                borderRadius: 'var(--mantine-radius-md)',
              }}
            >
              {channels.map((channel, index) => (
                <Group
                  component="li"
                  key={channel.id}
                  gap="sm"
                  wrap="nowrap"
                  justify="space-between"
                  px="md"
                  py="sm"
                  style={index > 0 ? { borderTop: '1px solid var(--app-border-default)' } : undefined}
                >
                  <Box style={{ minWidth: 0 }}>
                    <Text fz={14} fw={500} truncate>
                      {channelName(channel)}
                    </Text>
                    <Text fz={12} c="var(--app-text-tertiary)" truncate>
                      {provenance(channel)}
                    </Text>
                  </Box>
                  <Group gap="xs" wrap="nowrap">
                    {channel.confirmation_url && (
                      <Anchor
                        href={channel.confirmation_url}
                        target="_blank"
                        rel="noreferrer"
                        fz={13}
                        style={{ whiteSpace: 'nowrap' }}
                      >
                        View in {shortName}
                      </Anchor>
                    )}
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
                </Group>
              ))}
            </Box>
          )}
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Close
            </Button>
            {canEdit && (
              <Button leftSection={<IconPlus size={14} />} onClick={() => setConnecting(true)}>
                Connect a channel
              </Button>
            )}
          </Group>
        </Stack>
      </Modal>
      {canEdit && (
        <ConnectChannelModal
          projectId={projectId}
          provider={provider}
          opened={opened && connecting}
          onClose={() => setConnecting(false)}
          onConnected={() => load()}
        />
      )}
    </>
  );
};
