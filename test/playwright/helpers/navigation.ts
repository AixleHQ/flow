import { Page } from '@playwright/test';

import { BASE_URL, HTTP_CREDENTIALS } from './auth';

async function goTo(page: Page, path: string): Promise<void> {
  await page.context().setHTTPCredentials(HTTP_CREDENTIALS);
  await page.goto(`${BASE_URL}${path}`, { waitUntil: 'domcontentloaded' });
}

/**
 * Navigate to the Login page.
 */
export async function goToLogin(page: Page): Promise<void> {
  await goTo(page, '/login');
}

/**
 * Navigate to the Projects list page.
 */
export async function goToProjects(page: Page): Promise<void> {
  await goTo(page, '/company/projects');
}

/**
 * Navigate to a single Project page.
 * @param projectId - The ID of the project to open.
 */
export async function goToProject(page: Page, projectId: string): Promise<void> {
  await goTo(page, `/company/projects/${projectId}/overview`);
}

/**
 * Navigate to the Agents page.
 */
export async function goToAgents(page: Page): Promise<void> {
  await goTo(page, '/company/agents');
}

/**
 * Navigate to the Skills page.
 */
export async function goToSkills(page: Page): Promise<void> {
  await goTo(page, '/company/skills');
}

/**
 * Navigate to the Tools page.
 */
export async function goToTools(page: Page): Promise<void> {
  await goTo(page, '/company/tools');
}

/**
 * Navigate to the Integrations page.
 */
export async function goToIntegrations(page: Page): Promise<void> {
  await goTo(page, '/company/integrations');
}

/**
 * Navigate to the MCP Servers page.
 */
export async function goToMcpServers(page: Page): Promise<void> {
  await goTo(page, '/company/mcp-servers');
}

/**
 * Navigate to the Repositories page.
 */
export async function goToRepositories(page: Page): Promise<void> {
  await goTo(page, '/company/repositories');
}

/**
 * Navigate to the Assets page.
 */
export async function goToAssets(page: Page): Promise<void> {
  await goTo(page, '/company/assets');
}

/**
 * Navigate to the Company Members page.
 */
export async function goToCompanyMembers(page: Page): Promise<void> {
  await goTo(page, '/company/members');
}

/**
 * Navigate to the Company Sessions page.
 */
export async function goToCompanySessions(page: Page): Promise<void> {
  await goTo(page, '/company/sessions');
}

/**
 * Navigate to the Config Items page.
 */
export async function goToConfigItems(page: Page): Promise<void> {
  await goTo(page, '/company/config-items');
}

/**
 * Navigate to the Workflow Builder for a company-level workflow.
 * @param workflowId - The ID of the workflow to open in the builder.
 */
export async function goToWorkflowBuilder(page: Page, workflowId: string): Promise<void> {
  await goTo(page, `/company/workflows/${workflowId}/builder`);
}

/**
 * Navigate to a Workflow Run page.
 * @param projectId - The ID of the project.
 * @param runId - The ID of the workflow run.
 */
export async function goToWorkflowRun(page: Page, projectId: string, runId: string): Promise<void> {
  await goTo(page, `/company/projects/${projectId}/workflow-runs/${runId}`);
}

/**
 * Navigate to the Session Artifacts page for a company session.
 * @param sessionId - The ID of the session.
 */
export async function goToSessionArtifacts(page: Page, sessionId: string): Promise<void> {
  await goTo(page, `/company/sessions/${sessionId}/artifacts`);
}

/**
 * Navigate to the Profile page.
 */
export async function goToProfile(page: Page): Promise<void> {
  await goTo(page, '/profile');
}
