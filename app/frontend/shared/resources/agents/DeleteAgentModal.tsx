import { Box, Text } from '@mantine/core';
import { type FC } from 'react';

import type { Agent } from '@/types/generated';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface DeleteAgentModalProps {
  opened: boolean;
  onClose: () => void;
  agent: Pick<Agent, 'id' | 'name' | 'title' | 'icon'> | null;
  basePath: string;
}

export const DeleteAgentModal: FC<DeleteAgentModalProps> = ({ opened, onClose, agent, basePath }) => {
  if (!agent) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Archive Agent"
      confirmLabel="Archive"
      itemId={agent.id}
      basePath={basePath}
      description="Archive this agent? It disappears from pickers and new sessions but keeps its history, and you can restore it from the Archived tab. Archiving is refused while a workflow uses it."
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
    />
  );
};
