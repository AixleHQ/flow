import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { RootLayout } from './layouts/RootLayout';

// Use lazyRouteComponent for page-level routes
const HomePage = lazyRouteComponent(() => import('../pages/home'));
const SessionPage = lazyRouteComponent(() => import('../pages/session'));
const LoginPage = lazyRouteComponent(() => import('../pages/login'));
const OnboardingPage = lazyRouteComponent(() => import('../pages/onboarding'));
const WorkspacePage = lazyRouteComponent(() => import('../pages/workspace'));
const ProjectsPage = lazyRouteComponent(() => import('../pages/projects'));
const ProjectPage = lazyRouteComponent(() => import('../pages/project'));
const WorkflowRunPage = lazyRouteComponent(() => import('../pages/workflow-run'));
const WorkflowBuilderPage = lazyRouteComponent(() => import('../pages/workflow-builder'));

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

// Homepage route - now shows projects dashboard
export const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: ProjectsPage,
});

// Projects list route
export const projectsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects',
  component: ProjectsPage,
});

// Single project route
export const projectRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects/$projectId',
  component: ProjectPage,
});

// Workflow run route - nested under project
export const workflowRunRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/projects/$projectId/workflow-runs/$runId',
  component: WorkflowRunPage,
});

// Workflow builder route
export const workflowBuilderRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/workflow-builder/$workflowId',
  component: WorkflowBuilderPage,
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

// Workspace route (legacy - for direct terminal access)
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
  projectsRoute,
  projectRoute,
  workflowRunRoute,
  workflowBuilderRoute,
  homeRoute,
  sessionRoute,
  workspaceRoute,
  setupRoute,
]);
