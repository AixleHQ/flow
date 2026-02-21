import { Outlet } from '@tanstack/react-router';
import * as React from 'react';

import { RoutePendingIndicator } from 'shared/ui';

/**
 * Root layout component
 * Handles global app structure and includes the ThemeProvider
 */
export const RootLayout: React.FC = () => {
  return (
    <>
      <RoutePendingIndicator />
      <Outlet />
    </>
  );
};
