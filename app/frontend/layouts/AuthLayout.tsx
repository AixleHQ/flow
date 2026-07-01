import { usePage } from '@inertiajs/react';
import { Box, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';

import { AppSidebar, FullPageLoader, Logo, type SharedProps } from 'shared/ui';

import classes from './AuthLayout.module.css';

interface AuthLayoutProps {
  children: ReactNode;
  projectId?: string;
  currentTab?: string;
  noPadding?: boolean;
}

export function AuthLayout({ children, projectId: propProjectId, noPadding }: AuthLayoutProps) {
  const pageProps = usePage().props as unknown as SharedProps & {
    project?: { id: number; name: string };
  };
  const { currentUser, flash, projects = [], permissions } = pageProps;

  const projectId = propProjectId ?? (pageProps.project ? String(pageProps.project.id) : undefined);
  const context = projectId ? 'project' : 'company';

  const prevFlashRef = useRef(flash);
  useEffect(() => {
    if (flash === prevFlashRef.current) return;
    prevFlashRef.current = flash;
    if (typeof flash.notice === 'string') {
      notifications.show({ message: flash.notice, color: 'green' });
    }
    if (typeof flash.alert === 'string') {
      notifications.show({ message: flash.alert, color: 'red' });
    }
    // "Needs setup" summary after copying a workflow from the catalog: a list of
    // resources that were not copied / need manual setup (secrets, assets, etc).
    const needsSetup = flash.needs_setup;
    if (Array.isArray(needsSetup) && needsSetup.length > 0) {
      notifications.show({
        title: 'Some resources need setup',
        message: needsSetup.join(' '),
        color: 'yellow',
        autoClose: false,
      });
    }
  }, [flash]);

  if (!currentUser) {
    return <FullPageLoader />;
  }

  const isOnboardingCompleted = currentUser.onboardingState === 'completed';
  const showChrome = isOnboardingCompleted;

  return (
    <Box className={classes.root}>
      {showChrome && (
        <AppSidebar
          projectId={projectId}
          context={context}
          projects={projects}
          currentProjectId={projectId ?? null}
          permissions={permissions}
        />
      )}
      <Box className={classes.contentColumn}>
        <Box component="main" className={noPadding ? classes.mainNoPadding : classes.main}>
          {children}
        </Box>
        {showChrome && (
          <Box component="footer" className={classes.footer}>
            <Text component="span" size="xs" c="dimmed" lh={1}>
              Powered by
            </Text>
            <Logo width={50} />
          </Box>
        )}
      </Box>
    </Box>
  );
}
