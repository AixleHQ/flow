import { createRootRoute, createRoute, lazyRouteComponent, redirect } from '@tanstack/react-router';

import { Routes } from 'shared/routes';
import { getSelectedProjectId } from 'widgets/AppHeader';

import { AuthLayout, RootLayout } from './layouts';

// Use lazyRouteComponent for page-level routes
const LoginPage = lazyRouteComponent(() => import('../pages/login'));
const OnboardingPage = lazyRouteComponent(() => import('../pages/onboarding'));
const ProjectsPage = lazyRouteComponent(() => import('../pages/projects'));
const ProjectPage = lazyRouteComponent(() => import('../pages/project'));
const WorkflowRunPage = lazyRouteComponent(() => import('../pages/workflow-run'));
const WorkflowBuilderPage = lazyRouteComponent(() => import('../pages/workflow-builder'));
const ProfilePage = lazyRouteComponent(() => import('../pages/profile'));
// Company pages
const CompanyMembersPage = lazyRouteComponent(() => import('../pages/company-members'));
const ConfigItemsPage = lazyRouteComponent(() => import('../pages/config-items'));
const AgentsPage = lazyRouteComponent(() => import('../pages/agents'));
const ToolsPage = lazyRouteComponent(() => import('../pages/tools'));
const McpServersPage = lazyRouteComponent(() => import('../pages/mcp-servers'));
const SkillsPage = lazyRouteComponent(() => import('../pages/skills'));
const AssetsPage = lazyRouteComponent(() => import('../pages/assets'));
const IntegrationsPage = lazyRouteComponent(() => import('../pages/integrations'));
const WorkflowsPage = lazyRouteComponent(() => import('../pages/workflows'));
const RepositoriesPage = lazyRouteComponent(() => import('../pages/repositories'));
const CompanySessionsPage = lazyRouteComponent(() => import('../pages/company-sessions'));
const CompanySessionNewPage = lazyRouteComponent(() =>
  import('../pages/company-sessions').then((m) => ({ default: m.CompanySessionNewPage })),
);
const CompanySessionViewPage = lazyRouteComponent(() =>
  import('../pages/company-sessions').then((m) => ({ default: m.CompanySessionViewPage })),
);
const SessionArtifactsPage = lazyRouteComponent(() => import('../pages/session-artifacts'));

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

// Homepage route - redirects to last selected project or projects list
export const indexRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.rootPath,
  beforeLoad: () => {
    const lastProjectId = getSelectedProjectId();
    if (lastProjectId) {
      throw redirect({ to: Routes.frontend.companyProjectPath(lastProjectId) });
    }
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
  path: Routes.frontend.companyProjectTabPath('$projectId', '$tab') as '/company/projects/$projectId/$tab',
  validateSearch: (search: Record<string, unknown>) => ({
    assigneeId: search.assigneeId as string | undefined,
    taskType: search.taskType as string | undefined,
    priority: search.priority as string | undefined,
    tags: search.tags as string | undefined,
    search: search.search as string | undefined,
    task: search.task as number | undefined,
  }),
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

// Workflow runs list — redirect to project tab
export const workflowRunsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.workflowRunsPath('$projectId'),
  beforeLoad: ({ params }: { params: { projectId: string } }) => {
    throw redirect({ to: Routes.frontend.companyProjectTabPath(params.projectId, 'runs') });
  },
});

// Workflow run route - nested under project
export const workflowRunRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.workflowRunPath('$projectId', '$runId'),
  component: WorkflowRunPage,
});

// Workflow builder routes (company & project scoped)
export const companyWorkflowBuilderRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyWorkflowBuilderPath('$workflowId'),
  component: WorkflowBuilderPage,
});

export const projectWorkflowBuilderRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.projectWorkflowBuilderPath('$projectId', '$workflowId'),
  component: WorkflowBuilderPage,
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

// Company assets route
export const companyAssetsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyAssetsPath,
  component: AssetsPage,
});

export const companyIntegrationsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyIntegrationsPath,
  component: IntegrationsPage,
});

export const companyWorkflowsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyWorkflowsPath,
  component: WorkflowsPage,
});

export const companyRepositoriesRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyRepositoriesPath,
  component: RepositoriesPage,
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

export const companySessionArtifactsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySessionArtifactsPath('$sessionId'),
  component: SessionArtifactsPage,
});

export const projectSessionArtifactsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectSessionArtifactsPath('$projectId', '$sessionId'),
  component: SessionArtifactsPage,
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
    workflowRunsRoute,
    workflowRunRoute,
    companyWorkflowBuilderRoute,
    projectWorkflowBuilderRoute,
    profileRoute,
    companyMembersRoute,
    companyConfigItemsRoute,
    companyAgentsRoute,
    companyToolsRoute,
    companyMcpServersRoute,
    companySkillsRoute,
    companyAssetsRoute,
    companyIntegrationsRoute,
    companyWorkflowsRoute,
    companyRepositoriesRoute,
    companySettingsRoute,
    companyBrandingRoute,
    companySessionsRoute,
    companySessionNewRoute,
    companySessionRoute,
    companySessionArtifactsRoute,
    projectSessionArtifactsRoute,
  ]),
]);
