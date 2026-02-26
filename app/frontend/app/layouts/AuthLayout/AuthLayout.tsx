import { Box, Typography } from '@mui/material';
import { Outlet, useLocation, useNavigate } from '@tanstack/react-router';
import { useEffect } from 'react';

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
  const navigate = useNavigate();
  const location = useLocation();

  const isOnboardingPath = location.pathname === Routes.frontend.onboardingPath;
  const isOnboardingCompleted = user?.onboardingState === 'completed';

  const needsLogin = !isLoading && !user;
  const needsOnboarding = !isLoading && user && !isOnboardingCompleted && !isOnboardingPath;
  const needsRedirectFromOnboarding = !isLoading && user && isOnboardingCompleted && isOnboardingPath;

  useEffect(() => {
    if (needsLogin) {
      navigate({ to: Routes.frontend.loginPath });
    } else if (needsOnboarding) {
      navigate({ to: Routes.frontend.onboardingPath });
    } else if (needsRedirectFromOnboarding) {
      navigate({ to: Routes.frontend.companyProjectsPath });
    }
  }, [needsLogin, needsOnboarding, needsRedirectFromOnboarding, navigate]);

  if (isLoading || needsLogin || needsOnboarding || needsRedirectFromOnboarding) {
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
