import { Box, Center, Stack, Text } from '@mantine/core';
import type { ReactNode } from 'react';

interface EmptyStateProps {
  /** A Tabler icon element, e.g. `<IconRobot size={22} />`. Not an emoji. */
  icon?: ReactNode;
  title: string;
  /** One or two lines saying what this is for and how to get the first one. */
  description?: string;
  /** The action that resolves the emptiness. */
  action?: ReactNode;
}

/**
 * The one empty state in the app.
 *
 * The resource pages had grown two dialects: five of them rendered a 48px emoji
 * (Tools and Skills both used 🔧, so the two pages were indistinguishable at a
 * glance) while others rendered a lineart glyph in a circular chip. This is the
 * chip version, because it themes and it does not depend on the platform's
 * emoji font.
 */
export function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  return (
    <Center py={48} px="md">
      <Stack align="center" gap="xs" maw={420}>
        {icon && (
          <Box
            mb={4}
            style={{
              width: 44,
              height: 44,
              borderRadius: 10,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: 'var(--app-bg-elevated)',
              border: '1px solid var(--app-border-default)',
              color: 'var(--app-text-secondary)',
            }}
          >
            {icon}
          </Box>
        )}
        <Text fz={15} fw={600} c="var(--app-text-primary)" ta="center">
          {title}
        </Text>
        {description && (
          <Text size="sm" c="var(--app-text-secondary)" ta="center">
            {description}
          </Text>
        )}
        {action && <Box mt="sm">{action}</Box>}
      </Stack>
    </Center>
  );
}
