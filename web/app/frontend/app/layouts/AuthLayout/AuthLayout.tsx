import { Box } from '@mui/material';
import { Outlet, useNavigate } from '@tanstack/react-router';
import { useEffect, useRef } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';
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
} as const;

const AuthLayout = () => {
  const { data, isLoading } = useGetCurrentUserQuery();
  const navigate = useNavigate();
  const hasNavigated = useRef(false);

  useEffect(() => {
    if (isLoading) return;

    // If not authenticated, redirect to login
    if (!data) {
      navigate({ to: Routes.frontend.loginPath });
      return;
    }

    // Prevent duplicate navigations in React Strict Mode
    if (hasNavigated.current) return;

    const currentPath = window.location.pathname;
    const isOnboardingPath = currentPath === Routes.frontend.onboardingPath;
    const isOnboardingCompleted = data.onboardingState === 'completed';

    // AC4: Cannot leave onboarding until complete
    // If user hasn't completed onboarding and is NOT on onboarding page, redirect to onboarding
    if (!isOnboardingCompleted && !isOnboardingPath) {
      hasNavigated.current = true;
      navigate({ to: Routes.frontend.onboardingPath });
      return;
    }

    // AC6: Cannot return to onboarding after completion
    // If user HAS completed onboarding and IS on onboarding page, redirect to projects
    if (isOnboardingCompleted && isOnboardingPath) {
      hasNavigated.current = true;
      navigate({ to: Routes.frontend.projectsPath });
      return;
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

  // Don't show header on onboarding page
  const showHeader =
    data.onboardingState === 'completed' && window.location.pathname !== Routes.frontend.onboardingPath;

  return (
    <Box sx={styles.root}>
      {showHeader && <AppHeader />}
      <Box component="main" sx={styles.main}>
        <Outlet />
      </Box>
    </Box>
  );
};

export { AuthLayout };
