import { createRootRoute, createRoute, lazyRouteComponent } from '@tanstack/react-router';

import { Routes } from 'shared/routes';

import { AuthLayout, RootLayout } from './layouts';

// Use lazyRouteComponent for page-level routes
const LoginPage = lazyRouteComponent(() => import('../pages/login'));
const OnboardingPage = lazyRouteComponent(() => import('../pages/onboarding'));
const ProjectsPage = lazyRouteComponent(() => import('../pages/projects'));
const ProjectPage = lazyRouteComponent(() => import('../pages/project'));
const WorkflowRunPage = lazyRouteComponent(() => import('../pages/workflow-run'));
const WorkflowBuilderPage = lazyRouteComponent(() => import('../pages/workflow-builder'));
const TerminalTestPage = lazyRouteComponent(() => import('../pages/terminal-test'));
const ProfilePage = lazyRouteComponent(() => import('../pages/profile'));
// Company pages
const CompanyMembersPage = lazyRouteComponent(() => import('../pages/company-members'));
const ConfigItemsPage = lazyRouteComponent(() => import('../pages/config-items'));
const AgentsPage = lazyRouteComponent(() => import('../pages/agents'));

// Define the root route
export const rootRoute = createRootRoute({
  component: RootLayout,
});

// Login route
export const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: Routes.frontend.loginPath,
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
  path: Routes.frontend.onboardingPath,
  component: OnboardingPage,
});

// Homepage route - redirects to company projects
export const indexRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.rootPath,
  component: ProjectsPage,
});

// Company projects list route
export const companyProjectsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectsPath,
  component: ProjectsPage,
});

// Single project route (under company)
export const projectRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectPath('$projectId'),
  component: ProjectPage,
});

// Workflow run route - nested under project
export const workflowRunRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.workflowRunPath('$projectId', '$runId'),
  component: WorkflowRunPage,
});

// Workflow builder route
export const workflowBuilderRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.workflowBuilderPath('$workflowId'),
  component: WorkflowBuilderPage,
});

// Terminal test route (for debugging WebSocket connections)
export const terminalTestRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.terminalTestPath,
  component: TerminalTestPage,
});

// Terminal test route with existing session (by route token)
export const terminalTestSessionRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.terminalTestSessionPath('$routeToken'),
  component: TerminalTestPage,
});

// Profile route
export const profileRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.profilePath,
  component: ProfilePage,
});

// Company members route
export const companyMembersRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyMembersPath,
  component: CompanyMembersPage,
});

// Company config items route
export const companyConfigItemsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyConfigItemsPath,
  component: ConfigItemsPage,
});

// Company agents route
export const companyAgentsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyAgentsPath,
  component: AgentsPage,
});

// Company settings route (placeholder)
export const companySettingsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySettingsPath,
  component: () => <div style={{ padding: 24, color: '#A1A1AA' }}>Company Settings - Coming Soon</div>,
});

// Company branding route (placeholder)
export const companyBrandingRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyBrandingPath,
  component: () => <div style={{ padding: 24, color: '#A1A1AA' }}>Company Branding - Coming Soon</div>,
});

export const routeTree = rootRoute.addChildren([
  loginRoute,
  authLayoutRoute.addChildren([
    onboardingRoute,
    indexRoute,
    companyProjectsRoute,
    projectRoute,
    workflowRunRoute,
    workflowBuilderRoute,
    terminalTestRoute,
    terminalTestSessionRoute,
    profileRoute,
    companyMembersRoute,
    companyConfigItemsRoute,
    companyAgentsRoute,
    companySettingsRoute,
    companyBrandingRoute,
  ]),
]);
