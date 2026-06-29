import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Text } from '@mantine/core';
import { useState, type FC } from 'react';

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
  const [deleting, setDeleting] = useState(false);

  const handleDelete = () => {
    if (!tool) return;

    setDeleting(true);
    router.delete(`${basePath}/${tool.id}`, {
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

  if (!tool) return null;

  return (
    <Modal opened={opened} onClose={onClose} title="Delete Tool" size="sm" centered>
      <Text c="dimmed" mb="md">
        Are you sure you want to delete this tool?
      </Text>

      <Box
        p="sm"
        mb="md"
        style={{
          backgroundColor: 'var(--app-bg-deep)',
          borderRadius: 'var(--mantine-radius-sm)',
        }}
      >
        <Text fw={500} c="var(--app-text-primary)">
          {tool.displayName}
        </Text>
        <Text fz={12} ff="JetBrains Mono, monospace" c="dimmed">
          {tool.name}
        </Text>
      </Box>

      <Text fz={13} c="yellow" mb="md">
        This action cannot be undone. Any workflows using this tool may be affected.
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
