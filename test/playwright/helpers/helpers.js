/* Aixle Playwright helpers for QA on staging. See README.md in this directory.
 *
 * Plain JavaScript with no imports, no TypeScript and no process.env, so it runs
 * as-is inside the Playwright MCP `browser_run_code` tool. Paste this whole file
 * at the top of the body of the `async (page) => { ... }` function, then call
 * the helpers below it.
 *
 * Every helper takes `page` and an `env` object:
 *   { baseUrl?: string, httpCredentials?: { username, password } }
 * `baseUrl` defaults to staging. `httpCredentials` is for HTTP Basic Auth and is
 * applied only when it is given (staging's public entry asks for it; from inside
 * the VPCs or over the VPN there is none). `loadCredentialsAsset(page)` returns
 * such an object, plus the role credentials, read from the QA credentials asset.
 *
 * Errors never include credentials.
 */
/* eslint-disable @typescript-eslint/no-unused-vars -- a paste-in snippet: every helper is used by the code pasted after it. */

const AIXLE_STAGING_URL = 'https://staging.flow.aixle.com';

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function aixleBaseUrl(env) {
  return ((env && env.baseUrl) || AIXLE_STAGING_URL).replace(/\/+$/, '');
}

// The browser_run_code sandbox has no global URL, so paths are cut out by hand.
function aixlePathname(href) {
  const match = String(href).match(/^[a-z][a-z0-9+.-]*:\/\/[^/?#]*([^?#]*)/i);
  return (match ? match[1] : String(href).split(/[?#]/)[0]) || '/';
}

// Accepts { email, password } or the `email:password` form the credentials
// asset uses. The password may itself contain ':'.
function aixleCredentials(credentials) {
  if (typeof credentials === 'string') {
    const separator = credentials.indexOf(':');
    if (separator < 1) throw new Error('Credentials must look like "email:password"');
    return { email: credentials.slice(0, separator), password: credentials.slice(separator + 1) };
  }
  if (!credentials || !credentials.email || !credentials.password) {
    throw new Error('Credentials need an email and a password');
  }
  return { email: credentials.email, password: credentials.password };
}

// Credentials that print as "[redacted]" if a snippet returns or logs them.
function aixleSecret(email, password) {
  return { email, password, toJSON: () => '[redacted]', toString: () => '[redacted]' };
}

async function aixleOpen(page, env, path) {
  const http = env && env.httpCredentials;
  if (http && http.username) {
    await page.context().setHTTPCredentials({ username: http.username, password: http.password || '' });
  }
  const response = await page.goto(aixleBaseUrl(env) + path, { waitUntil: 'domcontentloaded' });
  if (response && response.status() >= 400) throw new Error(`${path} answered HTTP ${response.status()}`);
  return response;
}

async function aixleLeave(page, isFormPath, what) {
  try {
    await page.waitForURL((url) => !isFormPath(url.pathname), { timeout: 30000 });
  } catch {
    throw new Error(`${what} did not complete: still on ${aixlePathname(page.url())}`);
  }
}

function aixleId(name, value) {
  if (value === undefined || value === null || value === '') throw new Error(`${name} is required`);
  return encodeURIComponent(String(value));
}

// ---------------------------------------------------------------------------
// Credentials
// ---------------------------------------------------------------------------

/**
 * Read the STAGING_CREDENTIALS_SECRETS.txt asset through the browser (file://),
 * so the secrets never appear in the code sent to browser_run_code. Lines are
 * KEY="value" (quotes optional):
 *   STAGING_URL                          base URL (optional, defaults to staging)
 *   STAGING_COMPANY_ADMIN_CREDENTIALS    email:password
 *   STAGING_COMPANY_EMPLOYEE_CREDENTIALS email:password
 *   STAGING_ADMIN_CREDENTIALS            email:password (super admin, optional)
 *   STAGING_HTTP_CREDENTIALS             user:password (Basic Auth, optional)
 * Returns an object usable as `env` that also carries companyAdmin,
 * companyEmployee and admin. Credential values print as "[redacted]".
 */
async function loadCredentialsAsset(page, path = '/workspace/assets/STAGING_CREDENTIALS_SECRETS.txt') {
  const reader = await page.context().newPage();
  let text;
  try {
    await reader.goto(`file://${path}`);
    text = await reader.evaluate(() => document.body.innerText);
  } catch {
    throw new Error(`Cannot read the credentials asset at ${path}`);
  } finally {
    await reader.close();
  }

  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*"?(.*?)"?\s*$/);
    if (match) values[match[1]] = match[2];
  }
  const secret = (key) => {
    if (!values[key]) return null;
    const { email, password } = aixleCredentials(values[key]);
    return aixleSecret(email, password);
  };
  const http = secret('STAGING_HTTP_CREDENTIALS');

  return {
    baseUrl: values.STAGING_URL || AIXLE_STAGING_URL,
    httpCredentials: http && { username: http.email, password: http.password, toJSON: () => '[redacted]' },
    companyAdmin: secret('STAGING_COMPANY_ADMIN_CREDENTIALS'),
    companyEmployee: secret('STAGING_COMPANY_EMPLOYEE_CREDENTIALS'),
    admin: secret('STAGING_ADMIN_CREDENTIALS'),
  };
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

/**
 * Sign in at /login: Email, Continue, Password, Sign in. Clears the context's
 * cookies first, so it always signs in as the given account. Resolves once the
 * browser has left /login.
 */
async function login(page, env, credentials) {
  const { email, password } = aixleCredentials(credentials);
  await page.context().clearCookies();
  await aixleOpen(page, env, '/login');

  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByRole('button', { name: 'Continue', exact: true }).click();

  const passwordField = page.getByLabel('Password', { exact: true });
  try {
    await passwordField.waitFor({ timeout: 15000 });
  } catch {
    throw new Error(`No password step after Continue (at ${aixlePathname(page.url())})`);
  }
  await passwordField.fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();

  await aixleLeave(page, (pathname) => pathname.startsWith('/login'), 'Sign-in');
}

/** Sign in as CompanyAdmin. Credentials default to env.companyAdmin (see loadCredentialsAsset). */
async function loginAsCompanyAdmin(page, env, credentials = env && env.companyAdmin) {
  await login(page, env, credentials);
}

/** Sign in as CompanyEmployee. Credentials default to env.companyEmployee. */
async function loginAsCompanyEmployee(page, env, credentials = env && env.companyEmployee) {
  await login(page, env, credentials);
}

/**
 * Sign in as the platform operator (super admin) at /admin/login: one form with
 * Email, Password and Sign in. Resolves once the browser has left /admin/login.
 * Credentials default to env.admin. Untested: the QA credentials asset has no
 * super-admin account.
 */
async function loginAsAdmin(page, env, credentials = env && env.admin) {
  const { email, password } = aixleCredentials(credentials);
  await page.context().clearCookies();
  await aixleOpen(page, env, '/admin/login');

  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Password', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();

  await aixleLeave(page, (pathname) => pathname.startsWith('/admin/login'), 'Administrator sign-in');
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/**
 * Open a path under baseUrl and make sure the browser stayed there. Throws on an
 * HTTP error, on a redirect to sign-in, and on any other redirect (a page the
 * role may not open sends the browser back, or to /).
 */
async function goTo(page, env, path) {
  await aixleOpen(page, env, path);
  const expected = aixlePathname(path);
  const pathname = aixlePathname(page.url());
  if (pathname === expected) return;
  if (pathname.startsWith('/login')) throw new Error(`${expected} redirected to sign-in`);
  throw new Error(`${expected} redirected to ${pathname}`);
}

async function goToLogin(page, env) {
  await goTo(page, env, '/login');
}

async function goToProfile(page, env) {
  await goTo(page, env, '/profile');
}

// Company-level pages

async function goToProjects(page, env) {
  await goTo(page, env, '/company/projects');
}

async function goToAssets(page, env) {
  await goTo(page, env, '/company/assets');
}

async function goToCompanyMembers(page, env) {
  await goTo(page, env, '/company/members');
}

async function goToCompanySessions(page, env) {
  await goTo(page, env, '/company/sessions');
}

async function goToSessionArtifacts(page, env, sessionId) {
  await goTo(page, env, `/company/sessions/${aixleId('sessionId', sessionId)}/artifacts`);
}

// Project-level pages. Agents, skills, tools, integrations, MCP servers,
// repositories, config items, workflows and runs all live under a project.

function aixleProjectPath(projectId, rest) {
  return `/company/projects/${aixleId('projectId', projectId)}${rest}`;
}

async function goToProject(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/overview'));
}

async function goToAgents(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/agents'));
}

async function goToSkills(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/skills'));
}

async function goToTools(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/tools'));
}

async function goToIntegrations(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/integrations'));
}

async function goToMcpServers(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/mcp_servers'));
}

async function goToRepositories(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/repositories'));
}

async function goToConfigItems(page, env, projectId) {
  await goTo(page, env, aixleProjectPath(projectId, '/config_items'));
}

async function goToWorkflowBuilder(page, env, projectId, workflowId) {
  await goTo(page, env, aixleProjectPath(projectId, `/workflows/${aixleId('workflowId', workflowId)}/builder`));
}

async function goToWorkflowRun(page, env, projectId, runId) {
  await goTo(page, env, aixleProjectPath(projectId, `/workflow_runs/${aixleId('runId', runId)}`));
}
