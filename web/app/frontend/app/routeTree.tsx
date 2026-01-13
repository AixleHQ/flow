import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { RootLayout } from './layouts/RootLayout';

// Use lazyRouteComponent for page-level routes
const HomePage = lazyRouteComponent(() => import('../pages/home'));

// Define the root route
export const rootRoute = createRootRoute({
  component: RootLayout,
});

// Homepage route
export const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: HomePage,
});

// Create the route tree
export const routeTree = rootRoute.addChildren([indexRoute]);
