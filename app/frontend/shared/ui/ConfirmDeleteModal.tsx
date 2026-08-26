import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Text } from '@mantine/core';
import { useState, type FC, type ReactNode } from 'react';

interface ConfirmDeleteModalProps {
  opened: boolean;
  onClose: () => void;
  title: string;
  /** id of the item being deleted; the modal renders nothing while this is null */
  itemId: number | null;
  basePath: string;
  description: ReactNode;
  /** rendered inside the highlighted preview box, e.g. the item's name/icon */
  preview?: ReactNode;
  warning?: ReactNode;
  onDeleteError?: () => void;
}

export const ConfirmDeleteModal: FC<ConfirmDeleteModalProps> = ({
  opened,
  onClose,
  title,
  itemId,
  basePath,
  description,
  preview,
  warning,
  onDeleteError,
}) => {
  const [loading, setLoading] = useState(false);

  if (itemId === null) return null;

  const handleDelete = () => {
    setLoading(true);
    router.delete(`${basePath}/${itemId}`, {
      preserveScroll: true,
      onSuccess: () => onClose(),
      onError: () => onDeleteError?.(),
      onFinish: () => setLoading(false),
    });
  };

  return (
    <Modal opened={opened} onClose={onClose} title={title} size="sm" centered>
      <Text fz={14} c="dimmed" mb="md">
        {description}
      </Text>

      {preview && (
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
          {preview}
        </Box>
      )}

      {warning && (
        <Text fz={13} c="var(--app-warning-fg)" mb="md">
          {warning}
        </Text>
      )}

      <Group justify="flex-end">
        <Button variant="default" onClick={onClose} disabled={loading}>
          Cancel
        </Button>
        <Button color="red" onClick={handleDelete} loading={loading}>
          Delete
        </Button>
      </Group>
    </Modal>
  );
};
