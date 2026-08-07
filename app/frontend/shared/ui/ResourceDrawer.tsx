import { ActionIcon, Box, Drawer, Text } from '@mantine/core';
import { IconX } from '@tabler/icons-react';
import type { ReactNode } from 'react';

interface ResourceDrawerProps {
  opened: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  /** Typically a single full-width primary button — no Cancel. Close is the X in the header. */
  footer?: ReactNode;
}

/**
 * The one create/edit side panel in the app: 460px, right-slide, drop shadow,
 * plain header (title + close, no accent icon tile), single full-width
 * primary footer action. Matches the Sessions & Runs side panels.
 */
export function ResourceDrawer({ opened, onClose, title, children, footer }: ResourceDrawerProps) {
  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={460}
      withCloseButton={false}
      padding={0}
      styles={{
        body: { padding: 0, height: '100%', display: 'flex', flexDirection: 'column' },
        content: { display: 'flex', flexDirection: 'column' },
      }}
    >
      <Box
        style={{
          padding: '18px 24px',
          borderBottom: '1px solid var(--app-border-default)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexShrink: 0,
        }}
      >
        <Text component="h2" fz={16} fw={600} c="var(--app-text-primary)" m={0}>
          {title}
        </Text>
        <ActionIcon aria-label="Close" variant="subtle" color="gray" onClick={onClose}>
          <IconX size={16} />
        </ActionIcon>
      </Box>

      <Box style={{ flex: 1, overflowY: 'auto', padding: '22px 24px 24px' }}>{children}</Box>

      {footer && (
        <Box style={{ padding: '16px 24px', borderTop: '1px solid var(--app-border-default)', flexShrink: 0 }}>
          {footer}
        </Box>
      )}
    </Drawer>
  );
}
