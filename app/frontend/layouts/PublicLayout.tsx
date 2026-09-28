import { Link, usePage } from '@inertiajs/react';
import { Anchor, Box, Button, Container, Group, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';

import { howItWorksPath, loginPath, templatesPath } from 'shared/routes';
import { BrandLockup, type SharedProps } from 'shared/ui';

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
  const { flash, settings, currentUser } = usePage<Partial<SharedProps> & { [key: string]: unknown }>().props;

  // /how-it-works sells a workspace you can create and a price we invoice, so it
  // exists only where we host. Linking to it elsewhere would be a link to a
  // redirect.
  const sellsItself = settings?.selfServeSignup === true;
  const home = sellsItself ? howItWorksPath() : templatesPath();

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
              <Anchor component={Link} href={home} aria-label="Aixle Flow">
                <BrandLockup size="sm" />
              </Anchor>
              <Group gap="lg">
                {sellsItself && (
                  <Anchor component={Link} href={howItWorksPath()} c="var(--app-text-secondary)" size="sm">
                    How it works
                  </Anchor>
                )}
                <Anchor component={Link} href={templatesPath()} c="var(--app-text-secondary)" size="sm">
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
              <Button component="a" href={currentUser ? '/' : loginPath()} size="xs">
                {currentUser ? 'Open Flow' : 'Sign in'}
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
