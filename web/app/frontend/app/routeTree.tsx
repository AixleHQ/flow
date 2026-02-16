import { createRootRoute, createRoute, lazyRouteComponent, redirect } from '@tanstack/react-router';

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
const ToolsPage = lazyRouteComponent(() => import('../pages/tools'));
const McpServersPage = lazyRouteComponent(() => import('../pages/mcp-servers'));
const SkillsPage = lazyRouteComponent(() => import('../pages/skills'));
const CompanySessionsPage = lazyRouteComponent(() => import('../pages/company-sessions'));
const CompanySessionNewPage = lazyRouteComponent(() =>
  import('../pages/company-sessions').then((m) => ({ default: m.CompanySessionNewPage })),
);
const CompanySessionViewPage = lazyRouteComponent(() =>
  import('../pages/company-sessions').then((m) => ({ default: m.CompanySessionViewPage })),
);

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
  beforeLoad: () => {
    throw redirect({ to: Routes.frontend.companyProjectsPath });
  },
  component: ProjectsPage,
});

// Company projects list route
export const companyProjectsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectsPath,
  component: ProjectsPage,
});

// Single project route - redirects to overview tab
export const projectRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectPath('$projectId'),
  beforeLoad: ({ params }: { params: { projectId: string } }) => {
    throw redirect({ to: Routes.frontend.companyProjectTabPath(params.projectId, 'overview') });
  },
  component: ProjectPage,
});

// Project tab route
export const projectTabRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectTabPath('$projectId', '$tab'),
  component: ProjectPage,
});

// Project session new route
export const projectSessionNewRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectSessionNewPath('$projectId'),
  component: CompanySessionNewPage,
});

// Project session view route
export const projectSessionViewRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectSessionPath('$projectId', '$sessionId'),
  component: CompanySessionViewPage,
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

// Company tools route
export const companyToolsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyToolsPath,
  component: ToolsPage,
});

// Company MCP servers route
export const companyMcpServersRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyMcpServersPath,
  component: McpServersPage,
});

// Company skills route
export const companySkillsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySkillsPath,
  component: SkillsPage,
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

// Company sessions routes
export const companySessionsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySessionsPath,
  component: CompanySessionsPage,
});

export const companySessionNewRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySessionNewPath,
  component: CompanySessionNewPage,
});

export const companySessionRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySessionPath('$sessionId'),
  component: CompanySessionViewPage,
});

export const routeTree = rootRoute.addChildren([
  loginRoute,
  authLayoutRoute.addChildren([
    onboardingRoute,
    indexRoute,
    companyProjectsRoute,
    projectRoute,
    projectTabRoute,
    projectSessionNewRoute,
    projectSessionViewRoute,
    workflowRunRoute,
    workflowBuilderRoute,
    terminalTestRoute,
    terminalTestSessionRoute,
    profileRoute,
    companyMembersRoute,
    companyConfigItemsRoute,
    companyAgentsRoute,
    companyToolsRoute,
    companyMcpServersRoute,
    companySkillsRoute,
    companySettingsRoute,
    companyBrandingRoute,
    companySessionsRoute,
    companySessionNewRoute,
    companySessionRoute,
  ]),
]);
