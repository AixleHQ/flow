import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Text } from '@mantine/core';
import { useState, type FC } from 'react';

interface Agent {
  id: number;
  name: string;
  title: string;
  icon: string | null;
}

interface DeleteAgentModalProps {
  opened: boolean;
  onClose: () => void;
  agent: Agent | null;
  basePath: string;
}

export const DeleteAgentModal: FC<DeleteAgentModalProps> = ({ opened, onClose, agent, basePath }) => {
  const [deleting, setDeleting] = useState(false);

  const handleDelete = () => {
    if (!agent) return;

    setDeleting(true);
    router.delete(`${basePath}/${agent.id}`, {
      preserveScroll: true,
      onSuccess: () => {
        setDeleting(false);
        onClose();
      },
      onError: () => {
        setDeleting(false);
      },
    });
  };

  if (!agent) return null;

  return (
    <Modal opened={opened} onClose={onClose} title="Delete Agent" size="sm" centered>
      <Text c="dimmed" mb="md">
        Are you sure you want to delete this agent?
      </Text>

      <Box
        p="sm"
        mb="md"
        style={{
          backgroundColor: 'var(--app-bg-deep)',
          borderRadius: 'var(--mantine-radius-sm)',
          display: 'flex',
          alignItems: 'center',
          gap: 12,
        }}
      >
        <Text fz={24}>{agent.icon || '🤖'}</Text>
        <Box>
          <Text fw={500} c="var(--app-text-primary)">
            {agent.title}
          </Text>
          <Text fz={12} ff="JetBrains Mono, monospace" c="dimmed">
            {agent.name}
          </Text>
        </Box>
      </Box>

      <Text fz={13} c="yellow" mb="md">
        This action cannot be undone. Any sessions or workflows using this agent may be affected.
      </Text>

      <Group justify="flex-end">
        <Button variant="default" onClick={onClose} disabled={deleting}>
          Cancel
        </Button>
        <Button color="red" onClick={handleDelete} loading={deleting}>
          Delete
        </Button>
      </Group>
    </Modal>
  );
};
