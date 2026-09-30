import { Box, Drawer } from '@mantine/core';
import type { ReactNode } from 'react';

interface ResourceDrawerProps {
  opened: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  /** Typically a single full-width primary button — no Cancel. Close is the X in the header. */
  footer?: ReactNode;
  /**
   * Children fill the panel edge to edge and own their scrolling body and
   * pinned footer — for a form whose primary action lives in its own state.
   */
  bare?: boolean;
}

/**
 * The one create/edit side panel in the app: 460px, right-slide, drop shadow,
 * plain header (title + close, no accent icon tile), single full-width
 * primary footer action.
 */
export function ResourceDrawer({ opened, onClose, title, children, footer, bare = false }: ResourceDrawerProps) {
  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={460}
      title={title}
      closeButtonProps={{ 'aria-label': 'Close' }}
      padding={0}
      styles={{
        content: { display: 'flex', flexDirection: 'column' },
        header: {
          padding: '18px 24px',
          borderBottom: '1px solid var(--app-border-default)',
          flexShrink: 0,
        },
        title: { fontSize: 16, fontWeight: 600, color: 'var(--app-text-primary)' },
        body: { padding: 0, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' },
      }}
    >
      {bare ? (
        children
      ) : (
        <>
          <Box style={{ flex: 1, overflowY: 'auto', padding: '22px 24px 24px' }}>{children}</Box>

          {footer && (
            <Box style={{ padding: '16px 24px', borderTop: '1px solid var(--app-border-default)', flexShrink: 0 }}>
              {footer}
            </Box>
          )}
        </>
      )}
    </Drawer>
  );
}
