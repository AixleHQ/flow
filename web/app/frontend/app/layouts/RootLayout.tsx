import { Outlet, useLocation, useNavigate } from '@tanstack/react-router';
import * as React from 'react';
import { useEffect } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';
import Routes from 'shared/routes';
import { RoutePendingIndicator } from 'shared/ui';

const PUBLIC_PATHS = [Routes.frontend.loginPath];

/**
 * Root layout component
 * Handles global app structure, authentication, and onboarding redirects
 */
export const RootLayout: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const isPublicPath = PUBLIC_PATHS.includes(location.pathname);

  // Skip fetching user data on public paths
  const { data, isLoading, isError } = useGetCurrentUserQuery(undefined, {
    skip: isPublicPath,
  });

  useEffect(() => {
    // Don't redirect on public paths
    if (isPublicPath) return;

    // Wait for data to load
    if (isLoading) return;

    // If error (not authenticated), redirect to login
    if (isError) {
      navigate({ to: Routes.frontend.loginPath });
      return;
    }

    // If user hasn't completed onboarding, redirect to onboarding
    if (data?.user && !data.user.onboardingCompleted && location.pathname !== Routes.frontend.onboardingPath) {
      navigate({ to: Routes.frontend.onboardingPath });
    }
  }, [data, isLoading, isError, isPublicPath, location.pathname, navigate]);

  return (
    <>
      <RoutePendingIndicator />
      <Outlet />
    </>
  );
};
