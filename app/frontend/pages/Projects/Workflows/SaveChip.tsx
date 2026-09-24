import { Group, Loader, Text } from '@mantine/core';
import { IconAlertTriangle, IconCheck } from '@tabler/icons-react';
import { memo } from 'react';

interface SaveChipProps {
  saving: boolean;
  /** The last save was refused or never arrived; the screen is ahead of the server. */
  failed?: boolean;
}

export const SaveChip = memo(function SaveChip({ saving, failed = false }: SaveChipProps) {
  const label = saving ? 'Saving changes' : failed ? 'Changes not saved' : 'Changes saved';

  return (
    <Group gap={4} style={{ flexShrink: 0 }} aria-live="polite" aria-label={label}>
      {saving ? (
        <>
          <Loader size={12} color="var(--app-primary)" />
          <Text size="xs" style={{ color: 'var(--app-text-secondary)' }}>
            Saving…
          </Text>
        </>
      ) : failed ? (
        <>
          <IconAlertTriangle size={12} color="var(--mantine-color-red-6)" />
          <Text size="xs" c="red">
            Not saved
          </Text>
        </>
      ) : (
        <>
          <IconCheck size={12} color="var(--app-primary)" />
          <Text size="xs" style={{ color: 'var(--app-text-secondary)' }}>
            Saved
          </Text>
        </>
      )}
    </Group>
  );
});
