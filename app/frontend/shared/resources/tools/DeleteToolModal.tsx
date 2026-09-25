import { Box, Text } from '@mantine/core';
import { type FC } from 'react';

import type { Tool } from '@/types/generated';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface DeleteToolModalProps {
  opened: boolean;
  onClose: () => void;
  tool: Pick<Tool, 'id' | 'name' | 'displayName'> | null;
  basePath: string;
}

export const DeleteToolModal: FC<DeleteToolModalProps> = ({ opened, onClose, tool, basePath }) => {
  if (!tool) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Archive Tool"
      confirmLabel="Archive"
      itemId={tool.id}
      basePath={basePath}
      description="Archive this tool? Agents stop being served it; it keeps its history, and you can restore it from the Archived tab. Archiving is refused while a workflow uses it."
      preview={
        <Box>
          <Text fw={500} c="var(--app-text-primary)">
            {tool.displayName}
          </Text>
          <Text fz={12} ff="JetBrains Mono, monospace" c="dimmed">
            {tool.name}
          </Text>
        </Box>
      }
    />
  );
};
