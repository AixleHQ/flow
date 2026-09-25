import { Text } from '@mantine/core';
import { type FC } from 'react';

import type { MCPServer } from '@/types/generated';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface DeleteMcpServerModalProps {
  opened: boolean;
  onClose: () => void;
  server: Pick<MCPServer, 'id' | 'name'> | null;
  basePath: string;
}

export const DeleteMcpServerModal: FC<DeleteMcpServerModalProps> = ({ opened, onClose, server, basePath }) => {
  if (!server) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Archive MCP Server"
      confirmLabel="Archive"
      itemId={server.id}
      basePath={basePath}
      description={
        <>
          Archive{' '}
          <Text span fw={600} c="var(--app-text-primary)">
            {server.name}
          </Text>
          ? New sessions stop getting it; its history and OAuth connections are kept, and you can restore it from the
          Archived tab. Archiving is refused while a workflow uses it.
        </>
      }
    />
  );
};
