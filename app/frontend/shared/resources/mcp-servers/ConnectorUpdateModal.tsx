import { router } from '@inertiajs/react';
import { Alert, Button, Code, Group, Modal, Stack, Text } from '@mantine/core';
import { IconArrowUpCircle } from '@tabler/icons-react';
import { useState, type FC } from 'react';

import type { McpServer } from './types';

interface ConnectorUpdateModalProps {
  server: McpServer | null;
  basePath: string;
  onClose: () => void;
}

// Updating is never automatic: it changes which code runs, which is the exact
// thing pinning a version exists to prevent happening quietly. The dialog states
// what moves and waits for a decision.
export const ConnectorUpdateModal: FC<ConnectorUpdateModalProps> = ({ server, basePath, onClose }) => {
  const [submitting, setSubmitting] = useState(false);

  const apply = () => {
    if (!server) return;
    setSubmitting(true);
    router.post(
      `${basePath}/${server.id}/update_connector`,
      {},
      { onFinish: () => setSubmitting(false), onSuccess: onClose },
    );
  };

  return (
    <Modal opened={!!server} onClose={onClose} title={`Update ${server?.name ?? ''}`} size="md">
      {server && (
        <Stack gap="md">
          <Group gap={8} align="center">
            <Code>{server.connectorVersion ?? '—'}</Code>
            <Text fz={13} c="dimmed">
              →
            </Text>
            <Code>{server.connectorUpdateVersion}</Code>
          </Group>

          <Text fz={13} c="dimmed">
            The values you already entered are kept for every setting this version still asks for. If it needs something
            new, the update stops and tells you rather than guessing.
          </Text>

          <Alert color="blue" variant="light" icon={<IconArrowUpCircle size={16} />}>
            Whatever this version declares becomes the new approved baseline, so tool changes that come with it will not
            be reported as drift.
          </Alert>

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Not now
            </Button>
            <Button loading={submitting} onClick={apply}>
              Update
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
};
