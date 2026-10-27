# Playwright helpers

Helpers for testing the application on staging through the Playwright MCP tool `browser_run_code`
(`browser_run_code_unsafe` in some MCP builds). They live in one file, [`helpers.js`](helpers.js).

## Why one plain-JavaScript snippet

`browser_run_code` takes a single self-contained `async (page) => { … }` function. It cannot import modules, has no
`process.env`, no TypeScript, and no global `URL`. So `helpers.js` is plain JavaScript with no imports, and it defines
every helper at once: paste the whole file at the top of the function body, then call the helpers below it. One snippet
is simpler to keep correct than a set of per-helper snippets that each repeat the shared internals.

Nothing in this repository runs or imports `helpers.js`. It is not a module and `@playwright/test` is not a dependency.

## Staging

|                 |                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| URL             | `https://staging.flow.aixle.com` (the default `baseUrl`)                                             |
| HTTP Basic Auth | Only on staging's public, internet-facing entry. From inside the VPCs or over the VPN there is none. |
| Viewport for QA | 1920×1080 (`await page.setViewportSize({ width: 1920, height: 1080 })`)                              |

The helpers apply Basic Auth only when `env.httpCredentials` is given. Leave it out when staging does not ask for it.

## Credentials

QA agents get credentials from the `STAGING_CREDENTIALS_SECRETS.txt` asset, at
`/workspace/assets/STAGING_CREDENTIALS_SECRETS.txt`. Its lines are `KEY="value"`:

| Key                                    | Value                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------ |
| `STAGING_URL`                          | Base URL (optional)                                                      |
| `STAGING_COMPANY_ADMIN_CREDENTIALS`    | `email:password` of the CompanyAdmin account                             |
| `STAGING_COMPANY_EMPLOYEE_CREDENTIALS` | `email:password` of the CompanyEmployee account                          |
| `STAGING_ADMIN_CREDENTIALS`            | `email:password` of a platform super admin (not in the QA asset today)   |
| `STAGING_HTTP_CREDENTIALS`             | `user:password` for HTTP Basic Auth (only when the public entry is used) |

[`.env.example`](.env.example) shows the same format with empty values.

Load them with `loadCredentialsAsset(page)`. It opens the asset in a second tab through `file://` and parses it inside the
browser, so the secrets never appear in the code you send to `browser_run_code` or in your messages. It returns an object
that works as `env` and carries the role credentials:

```js
const staging = await loadCredentialsAsset(page); // optional 2nd argument: another path
// staging.baseUrl, staging.httpCredentials (or null), staging.companyAdmin, staging.companyEmployee, staging.admin (or null)
```

Credential objects print as `"[redacted]"` if a snippet returns or logs them, and helper errors never include them.
Still, never print, screenshot, or copy credential values into comments, pull requests, or `/workspace/outputs`.

If the browser cannot read `file://` paths, read the asset with your file tools and pass the value inline, for example
`loginAsCompanyAdmin(page, env, 'email:password')`. Every login helper accepts `'email:password'` or
`{ email, password }`. That puts the secret into the tool call, so prefer `loadCredentialsAsset`.

## Worked example

Sign in as CompanyAdmin and open a project's agents page at 1920×1080. Paste the full contents of `helpers.js` where the
comment is:

```js
async (page) => {
  // ---- paste test/playwright/helpers/helpers.js here ----

  await page.setViewportSize({ width: 1920, height: 1080 });
  const staging = await loadCredentialsAsset(page);

  await loginAsCompanyAdmin(page, staging);
  await goToAgents(page, staging, 3); // project 3 is "QA Test Project" on staging

  return { url: page.url(), title: await page.title() };
};
```

On the public entry, add Basic Auth to the asset as `STAGING_HTTP_CREDENTIALS`, or pass it yourself:
`{ ...staging, httpCredentials: { username: '…', password: '…' } }`.

## Helper reference

Every helper is `async`, takes `page` first and `env` second, and throws with a readable message when it fails.

### Credentials and sign-in

| Helper                                                                 | What it does                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loadCredentialsAsset(page, path?)`                                    | Reads the credentials asset (see above).                                                                                                                                                                                          |
| `login(page, env, credentials)`                                        | Clears cookies, opens `/login`, fills **Email**, clicks **Continue** (`POST /login/identify`), fills **Password**, clicks **Sign in**, and waits until the browser leaves `/login`.                                               |
| `loginAsCompanyAdmin(page, env, credentials = env.companyAdmin)`       | `login` as CompanyAdmin. Lands on `/company/projects`.                                                                                                                                                                            |
| `loginAsCompanyEmployee(page, env, credentials = env.companyEmployee)` | `login` as CompanyEmployee. Lands on `/company/projects`.                                                                                                                                                                         |
| `loginAsAdmin(page, env, credentials = env.admin)`                     | Platform super admin: clears cookies, opens `/admin/login` (one form: **Email**, **Password**, **Sign in**), and waits until the browser leaves `/admin/login`. Not verified on staging: the QA asset has no super-admin account. |

Sign-in uses accessible locators (`getByLabel('Email')`, `getByLabel('Password')`, `getByRole('button', …)`), so it
follows the visible form, not field names.

### Navigation

Each `goTo*` helper opens its route and checks the browser stayed there. It throws on an HTTP error, on a redirect to
sign-in, and on any other redirect. A page a role may not open redirects back or to `/`.

| Helper                                                  | Route                                                 | Notes                                               |
| ------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------- |
| `goTo(page, env, path)`                                 | any path                                              | The generic form of the helpers below.              |
| `goToLogin(page, env)`                                  | `/login`                                              | Signed-out only: a signed-in browser is redirected. |
| `goToProfile(page, env)`                                | `/profile`                                            |                                                     |
| `goToProjects(page, env)`                               | `/company/projects`                                   |                                                     |
| `goToAssets(page, env)`                                 | `/company/assets`                                     | CompanyAdmin only.                                  |
| `goToCompanyMembers(page, env)`                         | `/company/members`                                    |                                                     |
| `goToCompanySessions(page, env)`                        | `/company/sessions`                                   | CompanyAdmin only.                                  |
| `goToSessionArtifacts(page, env, sessionId)`            | `/company/sessions/:id/artifacts`                     |                                                     |
| `goToProject(page, env, projectId)`                     | `/company/projects/:id/overview`                      |                                                     |
| `goToAgents(page, env, projectId)`                      | `/company/projects/:id/agents`                        |                                                     |
| `goToSkills(page, env, projectId)`                      | `/company/projects/:id/skills`                        |                                                     |
| `goToTools(page, env, projectId)`                       | `/company/projects/:id/tools`                         | Titled "Wrappers" in the UI.                        |
| `goToIntegrations(page, env, projectId)`                | `/company/projects/:id/integrations`                  |                                                     |
| `goToMcpServers(page, env, projectId)`                  | `/company/projects/:id/mcp_servers`                   | Titled "Connectors" in the UI.                      |
| `goToRepositories(page, env, projectId)`                | `/company/projects/:id/repositories`                  |                                                     |
| `goToConfigItems(page, env, projectId)`                 | `/company/projects/:id/config_items`                  | Titled "Secrets & Variables" in the UI.             |
| `goToWorkflowBuilder(page, env, projectId, workflowId)` | `/company/projects/:id/workflows/:workflowId/builder` |                                                     |
| `goToWorkflowRun(page, env, projectId, runId)`          | `/company/projects/:id/workflow_runs/:runId`          |                                                     |

Agents, skills, tools, integrations, MCP servers, repositories, config items, workflows and runs are project-scoped, so
those helpers take a project ID. To find IDs while signed in, read the Inertia page props, for example
`JSON.parse(document.querySelector('script[data-page="app"]').textContent).props.projects` on `/company/projects`.
