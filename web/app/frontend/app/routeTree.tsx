import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { RootLayout } from './layouts/RootLayout';

// Use lazyRouteComponent for page-level routes
const HomePage = lazyRouteComponent(() => import('../pages/home'));
const SessionPage = lazyRouteComponent(() => import('../pages/session'));
const LoginPage = lazyRouteComponent(() => import('../pages/login'));

// Define the root route
export const rootRoute = createRootRoute({
  component: RootLayout,
});

// Login route
export const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/login',
  component: LoginPage,
});

// Homepage route
export const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: HomePage,
});

// Session route with dynamic sessionId parameter
export const sessionRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/session/$sessionId',
  component: SessionPage,
});

// Create the route tree
export const routeTree = rootRoute.addChildren([loginRoute, indexRoute, sessionRoute]);
