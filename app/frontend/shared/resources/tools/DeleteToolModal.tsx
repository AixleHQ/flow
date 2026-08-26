import { Box, Text } from '@mantine/core';
import { type FC } from 'react';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface Tool {
  id: number;
  name: string;
  displayName: string;
}

interface DeleteToolModalProps {
  opened: boolean;
  onClose: () => void;
  tool: Tool | null;
  basePath: string;
}

export const DeleteToolModal: FC<DeleteToolModalProps> = ({ opened, onClose, tool, basePath }) => {
  if (!tool) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Delete Tool"
      itemId={tool.id}
      basePath={basePath}
      description="Are you sure you want to delete this tool?"
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
      warning="This action cannot be undone. Any workflows using this tool may be affected."
    />
  );
};
