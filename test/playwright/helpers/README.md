# Playwright Helpers

Reusable helper functions for manual and automated testing of the application on the staging environment.

## Setup

Copy `.env.example` to `.env` in this directory and fill in the credentials:

```bash
cp test/playwright/helpers/.env.example test/playwright/helpers/.env
```

Then populate the values in `.env`. The helpers read all credentials and URLs from environment variables at runtime.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `STAGING_URL` | Base URL of the staging environment | `https://staging.palad.ai` |
| `STAGING_HTTP_USER` | HTTP Basic Auth username | `admin` |
| `STAGING_HTTP_PASSWORD` | HTTP Basic Auth password | _(required)_ |
| `STAGING_ADMIN_EMAIL` | Admin role email | `admin-agent@palad.ai` |
| `STAGING_ADMIN_PASSWORD` | Admin role password | _(required)_ |
| `STAGING_COMPANY_ADMIN_EMAIL` | Company Admin role email | `admin-atc@staging.palad.ai` |
| `STAGING_COMPANY_ADMIN_PASSWORD` | Company Admin role password | _(required)_ |
| `STAGING_EMPLOYEE_EMAIL` | Company Employee role email | `employee-atc@staging.palad.ai` |
| `STAGING_EMPLOYEE_PASSWORD` | Company Employee role password | _(required)_ |

## Authentication Helpers

Import from `test/playwright/helpers`:

```typescript
import { loginAsAdmin, loginAsCompanyAdmin, loginAsCompanyEmployee, login } from 'test/playwright/helpers';
```

### `loginAsAdmin(page)`

Logs in as the platform Admin.

```typescript
test('admin sees the dashboard', async ({ page }) => {
  await loginAsAdmin(page);
  await expect(page).not.toHaveURL(/\/login/);
});
```

### `loginAsCompanyAdmin(page)`

Logs in as the Company Admin.

```typescript
test('company admin can access members', async ({ page }) => {
  await loginAsCompanyAdmin(page);
  await goToCompanyMembers(page);
  await expect(page).toHaveURL(/\/company\/members/);
});
```

### `loginAsCompanyEmployee(page)`

Logs in as the Company Employee.

```typescript
test('employee can view integrations', async ({ page }) => {
  await loginAsCompanyEmployee(page);
  await goToIntegrations(page);
});
```

### `login(page, credentials)`

Generic login for any credentials:

```typescript
import { login } from 'test/playwright/helpers';

await login(page, { email: 'user@example.com', password: 'secret' });
```

## Navigation Helpers

Import from `test/playwright/helpers`:

```typescript
import { goToProjects, goToAgents, goToProject } from 'test/playwright/helpers';
```

### Static pages (no parameters)

| Helper | Target route |
|---|---|
| `goToLogin(page)` | `/login` |
| `goToProjects(page)` | `/company/projects` |
| `goToAgents(page)` | `/company/agents` |
| `goToSkills(page)` | `/company/skills` |
| `goToTools(page)` | `/company/tools` |
| `goToIntegrations(page)` | `/company/integrations` |
| `goToMcpServers(page)` | `/company/mcp-servers` |
| `goToRepositories(page)` | `/company/repositories` |
| `goToAssets(page)` | `/company/assets` |
| `goToCompanyMembers(page)` | `/company/members` |
| `goToCompanySessions(page)` | `/company/sessions` |
| `goToConfigItems(page)` | `/company/config-items` |
| `goToProfile(page)` | `/profile` |

### Dynamic pages (require IDs)

| Helper | Target route |
|---|---|
| `goToProject(page, projectId)` | `/company/projects/:id/overview` |
| `goToWorkflowBuilder(page, workflowId)` | `/company/workflows/:id/builder` |
| `goToWorkflowRun(page, projectId, runId)` | `/company/projects/:id/workflow-runs/:runId` |
| `goToSessionArtifacts(page, sessionId)` | `/company/sessions/:id/artifacts` |

## Full Example

```typescript
import { test, expect } from '@playwright/test';
import { loginAsAdmin, goToProjects, goToProject } from 'test/playwright/helpers';

test('admin can open a project', async ({ page }) => {
  await loginAsAdmin(page);
  await goToProjects(page);
  await expect(page).toHaveURL(/\/company\/projects/);

  const projectId = 'your-project-id';
  await goToProject(page, projectId);
  await expect(page).toHaveURL(new RegExp(`/company/projects/${projectId}`));
});
```
