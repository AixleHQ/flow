import { Group, Loader, Text } from '@mantine/core';
import { IconCheck } from '@tabler/icons-react';
import { memo } from 'react';

interface SaveChipProps {
  saving: boolean;
}

export const SaveChip = memo(function SaveChip({ saving }: SaveChipProps) {
  return (
    <Group
      gap={4}
      style={{ flexShrink: 0 }}
      aria-live="polite"
      aria-label={saving ? 'Saving changes' : 'Changes saved'}
    >
      {saving ? (
        <>
          <Loader size={12} color="var(--app-primary)" />
          <Text size="xs" style={{ color: 'var(--app-text-secondary)' }}>
            Saving…
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
