import { Box, Typography } from '@mui/material';
import { Outlet, useLocation, useRouter } from '@tanstack/react-router';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';
import { Loader, Logo } from 'shared/ui';
import { AppHeader } from 'widgets/AppHeader';
import { AppSidebar } from 'widgets/AppSidebar';

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
  },
  body: {
    display: 'flex',
    flex: 1,
    minHeight: 0,
  },
  contentColumn: {
    display: 'flex',
    flexDirection: 'column',
    flex: 1,
    minWidth: 0,
    minHeight: 0,
    overflow: 'auto',
  },
  main: {
    flexGrow: 1,
  },
  footer: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 1,
    py: 2,
    opacity: 0.5,
    transition: 'opacity 0.2s',
    '&:hover': {
      opacity: 0.8,
    },
  },
  footerText: {
    fontSize: 12,
    color: 'text.secondary',
  },
} as const;

const AuthLayout = () => {
  const { data: user, isLoading } = useGetCurrentUserQuery();
  const router = useRouter();
  const location = useLocation();

  if (isLoading) {
    return <Loader />;
  }

  if (!user) {
    router.navigate({ to: Routes.frontend.loginPath });
    return <Loader />;
  }

  const isOnboardingPath = location.pathname === Routes.frontend.onboardingPath;
  const isOnboardingCompleted = user.onboardingState === 'completed';

  if (!isOnboardingCompleted && !isOnboardingPath) {
    router.navigate({ to: Routes.frontend.onboardingPath });
    return <Loader />;
  }

  if (isOnboardingCompleted && isOnboardingPath) {
    router.navigate({ to: Routes.frontend.companyProjectsPath });
    return <Loader />;
  }

  const showChrome = isOnboardingCompleted && !isOnboardingPath;

  return (
    <Box sx={styles.root}>
      {showChrome && <AppHeader />}
      <Box sx={styles.body}>
        {showChrome && <AppSidebar />}
        <Box sx={styles.contentColumn}>
          <Box component="main" sx={styles.main}>
            <Outlet />
          </Box>
          {showChrome && (
            <Box component="footer" sx={styles.footer}>
              <Typography sx={styles.footerText}>Powered by</Typography>
              <Logo width={60} />
            </Box>
          )}
        </Box>
      </Box>
    </Box>
  );
};

export { AuthLayout };
