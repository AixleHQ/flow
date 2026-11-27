import { ActionIcon, Group, Tooltip } from '@mantine/core';
import { IconCheck, IconPencil, IconX } from '@tabler/icons-react';

/** Pencil that turns into a green save check and a red cancel cross while a field is being edited. */
export function InlineEditActions({
  label,
  editing,
  saving = false,
  canSave = true,
  onEdit,
  onSave,
  onCancel,
}: {
  /** Lower-case name of what is edited ("title"), used in the button labels. */
  label: string;
  editing: boolean;
  saving?: boolean;
  canSave?: boolean;
  onEdit: () => void;
  onSave: () => void;
  onCancel: () => void;
}) {
  if (!editing) {
    return (
      <Tooltip label={`Edit ${label}`} withArrow>
        <ActionIcon variant="subtle" color="gray" size="sm" aria-label={`Edit ${label}`} onClick={onEdit}>
          <IconPencil size={16} />
        </ActionIcon>
      </Tooltip>
    );
  }
  return (
    <Group gap={2} wrap="nowrap" style={{ flexShrink: 0 }}>
      <Tooltip label={`Save ${label}`} withArrow>
        <ActionIcon
          variant="subtle"
          color="green"
          size="sm"
          aria-label={`Save ${label}`}
          onClick={onSave}
          loading={saving}
          disabled={!canSave}
        >
          <IconCheck size={16} />
        </ActionIcon>
      </Tooltip>
      <Tooltip label={`Cancel ${label}`} withArrow>
        <ActionIcon
          variant="subtle"
          color="red"
          size="sm"
          aria-label={`Cancel ${label}`}
          onClick={onCancel}
          disabled={saving}
        >
          <IconX size={16} />
        </ActionIcon>
      </Tooltip>
    </Group>
  );
}
