import { Box, Text } from '@mantine/core';
import { type FC } from 'react';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

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
  if (!agent) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Delete Agent"
      itemId={agent.id}
      basePath={basePath}
      description="Are you sure you want to delete this agent?"
      preview={
        <>
          <Text fz={24}>{agent.icon || '🤖'}</Text>
          <Box>
            <Text fw={500} c="var(--app-text-primary)">
              {agent.title}
            </Text>
            <Text fz={12} ff="JetBrains Mono, monospace" c="dimmed">
              {agent.name}
            </Text>
          </Box>
        </>
      }
      warning="This action cannot be undone. Any sessions or workflows using this agent may be affected."
    />
  );
};
