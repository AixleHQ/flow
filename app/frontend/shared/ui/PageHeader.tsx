import { Box, Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';

interface PageHeaderProps {
  /** The page title. Rendered as the page's single `<h1>`. */
  title: ReactNode;
  /** One line under the title. Keep it to what the page is for. */
  subtitle?: ReactNode;
  /** Primary/secondary actions, right-aligned on the title row. */
  actions?: ReactNode;
  /** Rendered inline after the title — status badges, counts, ids. */
  meta?: ReactNode;
  /** Space below the header. Defaults to 20px. */
  mb?: number;
}

/**
 * The one page title in the app.
 *
 * Before this existed, page titles shipped as styled `<Text>` at four different
 * sizes (24 / 26 / 32 / 36) and two of the most-visited pages — sessions and
 * workflow runs — had no title at all. Because they were `<Text>`, no page in
 * the product had an `<h1>`, so a screen-reader rotor returned an empty
 * document outline everywhere.
 *
 * Use this on every page. Do not hand-roll a title.
 */
export function PageHeader({ title, subtitle, actions, meta, mb = 20 }: PageHeaderProps) {
  return (
    <Box mb={mb}>
      <Group justify="space-between" align="flex-start" wrap="nowrap" gap="md">
        <Stack gap={4} style={{ minWidth: 0 }}>
          <Group gap="sm" wrap="wrap" align="center">
            <Title order={1} fz={28} fw={600} lh={1.2} style={{ minWidth: 0 }}>
              {title}
            </Title>
            {meta}
          </Group>
          {subtitle && (
            <Text size="sm" c="var(--app-text-secondary)">
              {subtitle}
            </Text>
          )}
        </Stack>
        {actions && (
          <Group gap="xs" wrap="nowrap" style={{ flexShrink: 0 }}>
            {actions}
          </Group>
        )}
      </Group>
    </Box>
  );
}
