import { Text } from '@mantine/core';
import { type FC } from 'react';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface McpServer {
  id: number;
  name: string;
}

interface DeleteMcpServerModalProps {
  opened: boolean;
  onClose: () => void;
  server: McpServer | null;
  basePath: string;
}

export const DeleteMcpServerModal: FC<DeleteMcpServerModalProps> = ({ opened, onClose, server, basePath }) => {
  if (!server) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Delete MCP Server"
      itemId={server.id}
      basePath={basePath}
      description={
        <>
          Are you sure you want to delete{' '}
          <Text span fw={600} c="var(--app-text-primary)">
            {server.name}
          </Text>
          ? This action cannot be undone.
        </>
      }
    />
  );
};
