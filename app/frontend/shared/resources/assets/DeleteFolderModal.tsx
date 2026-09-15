import { Button, Group, Modal, Text } from '@mantine/core';
import { IconAlertTriangle, IconTrash } from '@tabler/icons-react';

export interface DeleteFolderModalProps {
  opened: boolean;
  onClose: () => void;
  folderLabel: string;
  itemCount: number;
  submitting: boolean;
  onConfirm: (recursive: boolean) => void;
}

export function DeleteFolderModal({
  opened,
  onClose,
  folderLabel,
  itemCount,
  submitting,
  onConfirm,
}: DeleteFolderModalProps) {
  const empty = itemCount === 0;

  return (
    <Modal opened={opened} onClose={onClose} title={empty ? 'Delete folder' : 'Folder not empty'} centered size="sm">
      {empty ? (
        <Text size="sm" c="var(--app-text-secondary)">
          Delete{' '}
          <Text component="span" fw={600} c="var(--app-text-primary)" span>
            {folderLabel}
          </Text>
          ? This cannot be undone.
        </Text>
      ) : (
        <Group
          gap={10}
          align="flex-start"
          p="sm"
          style={{
            borderRadius: 8,
            background: 'var(--app-warning-bg)',
            border: '1px solid var(--app-warning-border)',
          }}
        >
          <IconAlertTriangle size={17} style={{ flexShrink: 0, marginTop: 1, color: 'var(--app-warning-fg)' }} />
          <Text size="sm" c="var(--app-text-primary)">
            <Text component="span" fw={600} span>
              {folderLabel}
            </Text>{' '}
            still has {itemCount} item{itemCount === 1 ? '' : 's'} inside. Move or delete its contents first, then
            delete the folder — or delete it and everything inside it now.
          </Text>
        </Group>
      )}
      <Group justify="flex-end" mt="lg">
        <Button variant="default" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        {empty ? (
          <Button
            color="red"
            leftSection={<IconTrash size={16} />}
            loading={submitting}
            onClick={() => onConfirm(false)}
          >
            Delete
          </Button>
        ) : (
          <Button
            color="red"
            leftSection={<IconTrash size={16} />}
            loading={submitting}
            onClick={() => onConfirm(true)}
          >
            Delete anyway
          </Button>
        )}
      </Group>
    </Modal>
  );
}
