import { Link, usePage } from '@inertiajs/react';
import { Anchor, Box, Button, Container, Group, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';

import { Logo, type SharedProps } from 'shared/ui';

interface PublicLayoutProps {
  children: ReactNode;
}

/**
 * The shell for pages a guest can open (the template catalog). AuthLayout
 * cannot host them: it renders a full-page loader until it has a currentUser.
 * No company rail, no projects — the installation's own host is shown so a
 * visitor knows where an install would land.
 */
export function PublicLayout({ children }: PublicLayoutProps) {
  const { flash, settings } = usePage().props as unknown as SharedProps & { settings?: { domain?: string } };

  const prevFlashRef = useRef<typeof flash | undefined>(undefined);
  useEffect(() => {
    if (!flash || flash === prevFlashRef.current) return;
    prevFlashRef.current = flash;
    if (typeof flash.alert === 'string') notifications.show({ message: flash.alert, color: 'red' });
    if (typeof flash.notice === 'string') notifications.show({ message: flash.notice, color: 'green' });
  }, [flash]);

  return (
    <Box mih="100dvh" bg="var(--app-bg-default)">
      <Box component="header" style={{ borderBottom: '1px solid var(--app-border-default)' }}>
        <Container size="xl" py="sm">
          <Group justify="space-between">
            <Group gap="xl">
              <Anchor component={Link} href="/templates" aria-label="Aixle Flow templates">
                <Logo width={96} />
              </Anchor>
              <Group gap="lg">
                <Anchor component={Link} href="/templates" c="var(--app-text-primary)" size="sm">
                  Templates
                </Anchor>
                <Anchor href="/docs" c="var(--app-text-secondary)" size="sm">
                  Docs
                </Anchor>
              </Group>
            </Group>
            <Group gap="md">
              {settings?.domain && (
                <Text size="xs" ff="var(--app-font-mono)" c="var(--app-text-tertiary)">
                  {settings.domain}
                </Text>
              )}
              <Button component="a" href="/login" size="xs">
                Sign in
              </Button>
            </Group>
          </Group>
        </Container>
      </Box>
      <Container size="xl" py={28} component="main" id="app-main">
        {children}
      </Container>
    </Box>
  );
}
