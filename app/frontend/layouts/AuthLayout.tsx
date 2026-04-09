import { usePage } from '@inertiajs/react';
import { Box, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';

import { AppHeader, AppSidebar, FullPageLoader, Logo, type SharedProps } from 'shared/ui';

import classes from './AuthLayout.module.css';

interface AuthLayoutProps {
  children: ReactNode;
  projectId?: string;
  currentTab?: string;
  noPadding?: boolean;
}

export function AuthLayout({
  children,
  projectId: propProjectId,
  currentTab: propCurrentTab,
  noPadding,
}: AuthLayoutProps) {
  const pageProps = usePage().props as unknown as SharedProps & {
    project?: { id: number; name: string };
  };
  const { currentUser, flash } = pageProps;

  const projectId = propProjectId ?? (pageProps.project ? String(pageProps.project.id) : undefined);
  const currentTab = propCurrentTab ?? deriveTabFromPath();

  const prevFlashRef = useRef(flash);
  useEffect(() => {
    if (flash === prevFlashRef.current) return;
    prevFlashRef.current = flash;
    if (flash.notice) {
      notifications.show({ message: flash.notice, color: 'green' });
    }
    if (flash.alert) {
      notifications.show({ message: flash.alert, color: 'red' });
    }
  }, [flash]);

  if (!currentUser) {
    return <FullPageLoader />;
  }

  const isOnboardingCompleted = currentUser.onboardingState === 'completed';
  const showChrome = isOnboardingCompleted;

  return (
    <Box className={classes.root}>
      {showChrome && <AppHeader currentProjectId={projectId} currentTab={currentTab} />}
      <Box className={classes.body}>
        {showChrome && projectId && <AppSidebar projectId={projectId} currentTab={currentTab} />}
        <Box className={classes.contentColumn}>
          <Box component="main" className={noPadding ? classes.mainNoPadding : classes.main}>
            {children}
          </Box>
          {showChrome && (
            <Box component="footer" className={classes.footer}>
              <Text component="span" size="xs" c="dimmed" lh={1}>
                Powered by
              </Text>
              <Logo width={44} h={12} style={{ transform: 'translateY(-1px)' }} />
            </Box>
          )}
        </Box>
      </Box>
    </Box>
  );
}

function deriveTabFromPath(): string | undefined {
  if (typeof window === 'undefined') return undefined;
  const match = window.location.pathname.match(/\/company\/projects\/\d+\/(\w+)/);
  return match?.[1];
}
