import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { AuthLayout, RootLayout } from './layouts';

// Use lazyRouteComponent for page-level routes
const HomePage = lazyRouteComponent(() => import('../pages/home'));
// TODO: SessionPage was removed/renamed - needs investigation
// const SessionPage = lazyRouteComponent(() => import('../pages/session'));
const LoginPage = lazyRouteComponent(() => import('../pages/login'));
const OnboardingPage = lazyRouteComponent(() => import('../pages/onboarding'));
const WorkspacePage = lazyRouteComponent(() => import('../pages/workspace'));
const ProjectsPage = lazyRouteComponent(() => import('../pages/projects'));
const ProjectPage = lazyRouteComponent(() => import('../pages/project'));
const WorkflowRunPage = lazyRouteComponent(() => import('../pages/workflow-run'));
const WorkflowBuilderPage = lazyRouteComponent(() => import('../pages/workflow-builder'));
const TerminalTestPage = lazyRouteComponent(() => import('../pages/terminal-test'));

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

// AuthLayout route - wraps all authenticated pages
export const authLayoutRoute = createRoute({
  id: 'authLayout',
  getParentRoute: () => rootRoute,
  component: AuthLayout,
});

// Onboarding route (still under authLayout for authentication check)
export const onboardingRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/onboarding',
  component: OnboardingPage,
});

// Homepage route - now shows projects dashboard
export const indexRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/',
  component: ProjectsPage,
});

// Projects list route
export const projectsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/projects',
  component: ProjectsPage,
});

// Single project route
export const projectRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/projects/$projectId',
  component: ProjectPage,
});

// Workflow run route - nested under project
export const workflowRunRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/projects/$projectId/workflow-runs/$runId',
  component: WorkflowRunPage,
});

// Workflow builder route
export const workflowBuilderRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/workflow-builder/$workflowId',
  component: WorkflowBuilderPage,
});

// Legacy home page route
export const homeRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/home',
  component: HomePage,
});

// Session route with dynamic sessionId parameter
// TODO: SessionPage was removed - using placeholder
export const sessionRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/session/$sessionId',
  component: () => null,
});

// Workspace route (legacy - for direct terminal access)
export const workspaceRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/workspace',
  component: WorkspacePage,
});

// Setup route (placeholder for agent setup)
export const setupRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/setup',
  component: WorkspacePage,
});

// Terminal test route (for debugging WebSocket connections)
export const terminalTestRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/terminal-test',
  component: TerminalTestPage,
});

// Terminal test route with existing session (by route token)
export const terminalTestSessionRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: '/terminal-test/$routeToken',
  component: TerminalTestPage,
});

// Create the route tree
export const routeTree = rootRoute.addChildren([
  loginRoute,
  authLayoutRoute.addChildren([
    onboardingRoute,
    indexRoute,
    projectsRoute,
    projectRoute,
    workflowRunRoute,
    workflowBuilderRoute,
    homeRoute,
    sessionRoute,
    workspaceRoute,
    setupRoute,
    terminalTestRoute,
    terminalTestSessionRoute,
  ]),
]);
