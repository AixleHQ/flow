import { Group, Loader, Text } from '@mantine/core';
import { IconCheck } from '@tabler/icons-react';

interface SaveChipProps {
  saving: boolean;
}

export function SaveChip({ saving }: SaveChipProps) {
  return (
    <Group gap={4} style={{ flexShrink: 0 }}>
      {saving ? (
        <>
          <Loader size={12} color="var(--accent)" />
          <Text size="xs" style={{ color: 'var(--text-2)' }}>
            Saving…
          </Text>
        </>
      ) : (
        <>
          <IconCheck size={12} color="var(--accent)" />
          <Text size="xs" style={{ color: 'var(--text-2)' }}>
            Saved
          </Text>
        </>
      )}
    </Group>
  );
}
