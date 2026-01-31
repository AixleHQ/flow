import { Box, Typography } from '@mui/material';
import { Outlet, useLocation, useNavigate } from '@tanstack/react-router';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';
import { Loader, Logo } from 'shared/ui';
import { AppHeader } from 'widgets/AppHeader';

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    minHeight: '100vh',
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

  if (isLoading) {
    return <Loader />;
  }

  if (!user) {
    return navigate({ to: Routes.frontend.loginPath });
  }

  const isOnboardingPath = location.pathname === Routes.frontend.onboardingPath;
  const isOnboardingCompleted = user.onboardingState === 'completed';

  if (!isOnboardingCompleted && !isOnboardingPath) {
    return navigate({ to: Routes.frontend.onboardingPath });
  }

  if (isOnboardingCompleted && isOnboardingPath) {
    return navigate({ to: Routes.frontend.companyProjectsPath });
  }

  const showHeader =
    user.onboardingState === 'completed' && window.location.pathname !== Routes.frontend.onboardingPath;

  const showFooter = showHeader;

  return (
    <Box sx={styles.root}>
      {showHeader && <AppHeader />}
      <Box component="main" sx={styles.main}>
        <Outlet />
      </Box>
      {showFooter && (
        <Box component="footer" sx={styles.footer}>
          <Typography sx={styles.footerText}>Powered by</Typography>
          <Logo width={60} />
        </Box>
      )}
    </Box>
  );
};

export { AuthLayout };
