import { Group, Text, Tooltip } from '@mantine/core';
import { IconRosetteDiscountCheckFilled } from '@tabler/icons-react';

import type { TemplatePublisher } from '../types';

export function PublisherLabel({ publisher }: { publisher: TemplatePublisher }) {
  return (
    <Group gap={4} wrap="nowrap">
      <Text size="xs" c="var(--app-text-tertiary)">
        by {publisher.displayName}
      </Text>
      {publisher.verified && (
        <Tooltip label="Verified publisher">
          <IconRosetteDiscountCheckFilled size={14} color="var(--app-primary)" aria-label="Verified publisher" />
        </Tooltip>
      )}
    </Group>
  );
}
