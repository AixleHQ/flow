import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Text } from '@mantine/core';
import { useState, type FC } from 'react';

interface McpServer {
  id: number;
  name: string;
  displayName: string;
}

interface DeleteMcpServerModalProps {
  opened: boolean;
  onClose: () => void;
  server: McpServer | null;
  basePath: string;
}

export const DeleteMcpServerModal: FC<DeleteMcpServerModalProps> = ({ opened, onClose, server, basePath }) => {
  const [loading, setLoading] = useState(false);

  if (!server) return null;

  const handleDelete = () => {
    setLoading(true);
    router.delete(`${basePath}/${server.id}`, {
      preserveScroll: true,
      onFinish: () => setLoading(false),
      onSuccess: () => onClose(),
    });
  };

  return (
    <Modal opened={opened} onClose={onClose} title="Delete MCP Server" size="sm">
      <Box>
        <Text fz={14} c="dimmed" mb="md">
          Are you sure you want to delete{' '}
          <Text span fw={600} c="var(--app-text-primary)">
            {server.displayName}
          </Text>
          ? This action cannot be undone.
        </Text>

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button color="red" onClick={handleDelete} loading={loading}>
            Delete
          </Button>
        </Group>
      </Box>
    </Modal>
  );
};
