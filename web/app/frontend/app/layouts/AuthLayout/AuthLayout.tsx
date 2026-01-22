import { Box } from '@mui/material';
import { Outlet, useNavigate } from '@tanstack/react-router';
import { useEffect } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';

const ALLOWED_PATHS_FOR_INCOMPLETE_ONBOARDING: string[] = [Routes.frontend.onboardingPath];

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    minHeight: '100vh',
  },
  main: {
    flexGrow: 1,
  },
} as const;

const AuthLayout = () => {
  const { data, isLoading } = useGetCurrentUserQuery();
  const navigate = useNavigate();

  useEffect(() => {
    if (isLoading) return;

    // If not authenticated, redirect to login
    if (!data) {
      navigate({ to: Routes.frontend.loginPath });
      return;
    }

    // If user hasn't completed onboarding, redirect to onboarding (unless already there)
    const currentPath = window.location.pathname;
    const isOnboardingPath = ALLOWED_PATHS_FOR_INCOMPLETE_ONBOARDING.includes(currentPath);

    if (!data.onboardingCompletedAt && !isOnboardingPath) {
      navigate({ to: Routes.frontend.onboardingPath });
    }
  }, [data, isLoading, navigate]);

  // Show loading state while checking auth
  if (isLoading) {
    return null;
  }

  // Don't render if not authenticated (will redirect via useEffect)
  if (!data) {
    return null;
  }

  return (
    <Box sx={styles.root}>
      <Box component="main" sx={styles.main}>
        <Outlet />
      </Box>
    </Box>
  );
};

export { AuthLayout };
