import { Table, Text } from '@mantine/core';
import type { ReactNode } from 'react';

interface ResourceTableShellProps {
  children: ReactNode;
  /** Ensures the table never collapses columns below legibility on narrow viewports. */
  minWidth?: number;
}

/**
 * The one resource list table shell in the app: bordered, rounded, dark
 * header row, horizontal scroll below `minWidth` instead of squeezing
 * columns. Wraps a plain `<Table>` — pass columns/rows as children.
 */
export function ResourceTableShell({ children, minWidth = 720 }: ResourceTableShellProps) {
  return (
    <Table.ScrollContainer
      minWidth={minWidth}
      style={{
        border: '1px solid var(--app-border-default)',
        borderRadius: 'var(--mantine-radius-md)',
      }}
    >
      {children}
    </Table.ScrollContainer>
  );
}

interface ResourceThProps {
  children: ReactNode;
  align?: 'left' | 'right';
  w?: number;
}

/** The one table header cell label style in the app. */
export function ResourceTh({ children, align = 'left', w }: ResourceThProps) {
  return (
    <Table.Th w={w}>
      <Text fz={12} fw={600} c="dimmed" tt="uppercase" ta={align} style={{ letterSpacing: 0.5 }}>
        {children}
      </Text>
    </Table.Th>
  );
}

/** Row/table total, right-aligned in the toolbar. Sans — never mono, per design spec. */
export function ResourceCount({ children }: { children: ReactNode }) {
  return (
    <Text fz={13} c="dimmed" ml="auto" style={{ whiteSpace: 'nowrap' }}>
      {children}
    </Text>
  );
}
