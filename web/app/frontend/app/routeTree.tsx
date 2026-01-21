import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { RootLayout } from './layouts/RootLayout';

// Use lazyRouteComponent for page-level routes
const HomePage = lazyRouteComponent(() => import('../pages/home'));
const SessionPage = lazyRouteComponent(() => import('../pages/session'));
const LoginPage = lazyRouteComponent(() => import('../pages/login'));
const OnboardingPage = lazyRouteComponent(() => import('../pages/onboarding'));
const WorkspacePage = lazyRouteComponent(() => import('../pages/workspace'));

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

// Onboarding route
export const onboardingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/onboarding',
  component: OnboardingPage,
});

// Homepage route - now shows workspace
export const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: WorkspacePage,
});

// Legacy home page route
export const homeRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/home',
  component: HomePage,
});

// Session route with dynamic sessionId parameter
export const sessionRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/session/$sessionId',
  component: SessionPage,
});

// Workspace route
export const workspaceRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/workspace',
  component: WorkspacePage,
});

// Setup route (placeholder for agent setup)
export const setupRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/setup',
  component: WorkspacePage,
});

// Create the route tree
export const routeTree = rootRoute.addChildren([
  loginRoute,
  onboardingRoute,
  indexRoute,
  homeRoute,
  sessionRoute,
  workspaceRoute,
  setupRoute,
]);
