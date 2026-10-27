/* Aixle Playwright helpers for QA on staging. See README.md in this directory.
 *
 * Plain JavaScript with no imports, no TypeScript and no process.env, so it runs
 * as-is inside the Playwright MCP `browser_run_code` tool. Paste this whole file
 * at the top of the body of the `async (page) => { ... }` function, then call
 * the helpers below it.
 *
 * The sign-in and navigation helpers take `page` and an `env` object:
 *   { baseUrl?: string, httpCredentials?: { username, password } }
 * `baseUrl` defaults to staging. `httpCredentials` is for HTTP Basic Auth and is
 * applied only when it is given (staging's public entry asks for it; from inside
 * the VPCs or over the VPN there is none). `loadCredentialsAsset(page)` returns
 * such an object, plus the role credentials, read from the QA credentials asset.
 * appRequest, readInertiaPage, shot, probeRoutes and signOut take `page` and an
 * options object instead; see the section that defines them.
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
 * KEY="value" (double, single or no quotes; an `export ` prefix is allowed):
 *   STAGING_URL                          base URL (optional, defaults to staging)
 *   STAGING_COMPANY_ADMIN_CREDENTIALS    email:password
 *   STAGING_COMPANY_EMPLOYEE_CREDENTIALS email:password
 *   STAGING_ADMIN_CREDENTIALS            email:password (super admin, optional)
 *   STAGING_HTTP_CREDENTIALS             user:password (Basic Auth, optional)
 * Returns an object usable as `env` that also carries companyAdmin,
 * companyEmployee and admin. Credential values print as "[redacted]".
 * Throws, naming the keys it found (never the values), when neither role key
 * is present.
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

  // KEY=value, KEY="value" or KEY='value', with an optional `export ` prefix.
  // One pair of matching quotes is stripped; anything else is kept as is.
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!match) continue;
    const quoted = match[2].match(/^(["'])(.*)\1$/);
    values[match[1]] = quoted ? quoted[2] : match[2];
  }
  const roleKeys = ['STAGING_COMPANY_ADMIN_CREDENTIALS', 'STAGING_COMPANY_EMPLOYEE_CREDENTIALS'];
  if (!roleKeys.some((key) => values[key])) {
    // Name the keys, never the values: the file holds secrets.
    const found = Object.keys(values);
    throw new Error(
      `Credentials asset at ${path} has none of the expected keys: ${roleKeys.join(', ')}. ` +
        `Keys found: ${found.length ? found.join(', ') : 'none (expected KEY="email:password" lines)'}`,
    );
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
 * role may not open sends the browser back, or to /). Waits up to 5 s for the
 * network to go idle before checking, so a redirect the frontend makes right
 * after mount is caught too; a later one is not.
 */
async function goTo(page, env, path) {
  await aixleOpen(page, env, path);
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
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

// ---------------------------------------------------------------------------
// Requests, page payloads, screenshots and route probes
// ---------------------------------------------------------------------------
//
// These helpers take `page` and one options object. Relative paths resolve
// against `options.baseUrl` when it is given, else the origin of the page the
// browser is on, else staging (see aixleRequestBase). Passing the `env` from
// loadCredentialsAsset as the options of signOut works, since it has baseUrl.

// The origin (scheme://host[:port]) of an http(s) URL, or null.
function aixleOrigin(href) {
  const match = String(href || '').match(/^(https?:\/\/[^/?#]+)/i);
  return match ? match[1] : null;
}

function aixleRequestBase(page, options) {
  if (options && options.baseUrl) return aixleBaseUrl(options);
  return aixleOrigin(page.url()) || AIXLE_STAGING_URL;
}

function aixleAbsolute(base, path) {
  if (!path) throw new Error('path is required');
  if (/^https?:\/\//i.test(path)) return path;
  return base + (String(path).startsWith('/') ? '' : '/') + path;
}

// A Location header (or any URL) on `base`, shortened to its path and query.
function aixleRelative(base, href) {
  if (!href) return null;
  return href.startsWith(base) ? href.slice(base.length) || '/' : href;
}

// application/x-www-form-urlencoded without URLSearchParams, which the sandbox
// lacks. Arrays become repeated `key[]` pairs; null and undefined are skipped.
function aixleFormEncode(fields) {
  const pairs = [];
  for (const key of Object.keys(fields)) {
    const value = fields[key];
    if (value === undefined || value === null) continue;
    const name = Array.isArray(value) && !key.endsWith('[]') ? `${key}[]` : key;
    for (const item of Array.isArray(value) ? value : [value]) {
      pairs.push(`${encodeURIComponent(name)}=${encodeURIComponent(String(item))}`);
    }
  }
  return pairs.join('&').replace(/%20/g, '+');
}

function aixleCsrfFromHtml(html) {
  const meta = html.match(/<meta\b[^>]*\bname="csrf-token"[^>]*>/i);
  const input = html.match(/<input\b[^>]*\bname="authenticity_token"[^>]*>/i);
  const tag = (meta && meta[0]) || (input && input[0]);
  const value = tag && tag.match(meta ? /\bcontent="([^"]*)"/i : /\bvalue="([^"]*)"/i);
  return value
    ? value[1]
        .replace(/&amp;/g, '&')
        .replace(/&#x2F;/gi, '/')
        .replace(/&#43;/g, '+')
    : null;
}

// The CSRF token of the current session, never returned. In order:
// 1. the XSRF-TOKEN cookie, which inertia_rails rewrites on every response.
//    An Inertia visit (the one after sign-in, say) does not reload <head>, so
//    the meta tag can still hold the token of the session before sign-in;
//    app/frontend/shared/lib/apiFetch.ts reads the cookie first for that reason;
// 2. meta[name="csrf-token"], then a form's authenticity_token, on the open
//    page when it is on `base`;
// 3. the same tags in the HTML of /login, fetched with the session cookies.
async function aixleCsrfToken(page, base) {
  const cookies = await page
    .context()
    .cookies(base)
    .catch(() => []);
  const xsrf = cookies.find((cookie) => cookie.name === 'XSRF-TOKEN');
  if (xsrf && xsrf.value) return decodeURIComponent(xsrf.value);

  if (aixleOrigin(page.url()) === base) {
    const token = await page
      .evaluate(() => {
        const meta = document.querySelector('meta[name="csrf-token"]');
        const input = document.querySelector('input[name="authenticity_token"]');
        return (meta && meta.getAttribute('content')) || (input && input.value) || null;
      })
      .catch(() => null);
    if (token) return token;
  }
  const response = await page.request.get(`${base}/login`, { failOnStatusCode: false, timeout: 30000 });
  const token = aixleCsrfFromHtml(await response.text());
  if (!token) throw new Error(`No CSRF token on ${aixlePathname(response.url())} (HTTP ${response.status()})`);
  return token;
}

// One request through page.request, with the browser context's cookies.
// `csrfToken` is passed in by callers that send several requests.
async function aixleSend(page, base, options, csrfToken) {
  const {
    method = 'GET',
    path,
    json,
    form,
    csrf = true,
    maxRedirects = 0,
    headers = {},
    textLimit = 2000,
  } = options || {};
  const verb = String(method).toUpperCase();
  const url = aixleAbsolute(base, path);
  const sendHeaders = { ...headers };
  const safe = verb === 'GET' || verb === 'HEAD';
  const token = csrf && !safe ? csrfToken || (await aixleCsrfToken(page, base)) : null;
  if (token) sendHeaders['X-CSRF-Token'] = token;

  let wireMethod = verb;
  let data;
  if (form !== undefined) {
    // Rails reads PATCH, PUT and DELETE from a POSTed `_method`, as a form does.
    const fields = { ...form };
    if (!safe && verb !== 'POST' && fields._method === undefined) fields._method = verb.toLowerCase();
    if (fields._method !== undefined) wireMethod = 'POST';
    if (token) fields.authenticity_token = token;
    data = aixleFormEncode(fields);
    sendHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
  } else if (json !== undefined) {
    data = JSON.stringify(json);
    sendHeaders['Content-Type'] = 'application/json';
    if (!Object.keys(sendHeaders).some((name) => name.toLowerCase() === 'accept')) {
      sendHeaders.Accept = 'application/json';
    }
  }

  let response;
  try {
    response = await page.request.fetch(url, {
      method: wireMethod,
      headers: sendHeaders,
      data,
      maxRedirects,
      failOnStatusCode: false,
      timeout: 30000,
    });
  } catch (error) {
    // Playwright's message can echo request headers, so it is not passed on.
    throw new Error(`${verb} ${aixlePathname(url)} failed: no response (${error && error.name})`);
  }

  const responseHeaders = response.headers();
  const contentType = responseHeaders['content-type'] || null;
  const body = verb === 'HEAD' ? '' : await response.text();
  let parsed = null;
  if (contentType && /\bjson\b/i.test(contentType) && body) {
    try {
      parsed = JSON.parse(body);
    } catch {
      parsed = null;
    }
  }
  const text = parsed !== null ? null : body.length > textLimit ? `${body.slice(0, textLimit)}…` : body;
  return {
    status: response.status(),
    location: aixleRelative(base, responseHeaders.location || null),
    contentType,
    json: parsed,
    text,
  };
}

/**
 * Send one HTTP request with the session cookies of the browser context and
 * return { status, location, contentType, json, text }.
 *   method       'GET' (default), 'POST', 'PATCH', 'PUT', 'DELETE', …
 *   path         '/company/projects', or an absolute URL
 *   json         body sent as application/json
 *   form         fields sent as application/x-www-form-urlencoded, with
 *                authenticity_token added and, for PATCH/PUT/DELETE, a POSTed
 *                `_method` (pass form._method yourself to override)
 *   csrf         true (default) sends the CSRF token on non-GET requests, as
 *                X-CSRF-Token and in `form`; false sends none (expect 422)
 *   maxRedirects 0 (default) reports a 302 and its Location instead of following
 *   headers      extra request headers
 *   textLimit    characters of a non-JSON body kept in `text` (default 2000)
 *   baseUrl      see aixleRequestBase
 * `json` is the parsed body when the response is JSON (then `text` is null);
 * `location` is shortened to a path when it points at baseUrl.
 */
async function appRequest(page, options = {}) {
  return aixleSend(page, aixleRequestBase(page, options), options);
}

// Picks dotted paths ('settings.appVersion', 'projects.0.id') out of an object.
// A path that does not resolve maps to null.
function aixlePick(source, paths) {
  const picked = {};
  for (const path of paths) {
    let value = source;
    for (const key of String(path).split('.')) {
      value = value !== null && typeof value === 'object' && key in value ? value[key] : undefined;
      if (value === undefined) break;
    }
    picked[path] = value === undefined ? null : value;
  }
  return picked;
}

/**
 * Fetch a page's HTML with the session cookies (following redirects) and parse
 * the Inertia payload in <script data-page="app" type="application/json">.
 * Hydration removes that element from the DOM, so it is read from the HTML,
 * not from the open page. `path` defaults to the page the browser is on.
 * `pick` (dotted paths) returns only those props, keyed by path.
 * Returns { url, status, component, version, appVersion, props }: `url` is
 * the final path after redirects, `appVersion` is props.settings.appVersion.
 */
async function readInertiaPage(page, { path, pick = [], baseUrl } = {}) {
  const base = aixleRequestBase(page, { baseUrl });
  const target = path || (aixleOrigin(page.url()) ? page.url() : null);
  if (!target) throw new Error('readInertiaPage needs a path: the browser is not on an app page');
  const url = aixleAbsolute(base, target);
  let response;
  try {
    response = await page.request.get(url, {
      headers: { Accept: 'text/html' },
      failOnStatusCode: false,
      timeout: 30000,
    });
  } catch (error) {
    throw new Error(`GET ${aixlePathname(url)} failed: no response (${error && error.name})`);
  }
  const html = await response.text();
  const landed = aixleRelative(aixleOrigin(response.url()) || base, response.url());
  const script = html.match(
    /<script\b(?=[^>]*\bdata-page="app")(?=[^>]*\btype="application\/json")[^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!script) {
    throw new Error(`No Inertia page payload at ${aixlePathname(landed)} (HTTP ${response.status()})`);
  }
  let data;
  try {
    data = JSON.parse(script[1]);
  } catch {
    throw new Error(`The Inertia page payload at ${aixlePathname(landed)} is not valid JSON`);
  }
  const props = data.props || {};
  const settings = props.settings || {};
  return {
    url: landed,
    status: response.status(),
    component: data.component || null,
    version: data.version || null,
    appVersion: settings.appVersion === undefined ? null : settings.appVersion,
    props: pick && pick.length ? aixlePick(props, pick) : props,
  };
}

const AIXLE_SHOT_WIDTH = 1920;
const AIXLE_SHOT_HEIGHT = 1080;

function aixleFileSegment(name, value) {
  const text = String(value === undefined || value === null ? '' : value);
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text)) {
    throw new Error(`${name} must be letters, digits, '.', '_' or '-' (got ${JSON.stringify(text).slice(0, 40)})`);
  }
  return text;
}

// Width and height from the IHDR chunk of a PNG buffer (bytes 16-23, big-endian).
function aixlePngSize(buffer) {
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (!buffer || buffer.length < 24 || png.some((byte, index) => buffer[index] !== byte)) {
    throw new Error('The screenshot is not a PNG');
  }
  const word = (offset) =>
    ((buffer[offset] << 24) | (buffer[offset + 1] << 16) | (buffer[offset + 2] << 8) | buffer[offset + 3]) >>> 0;
  return { width: word(16), height: word(20) };
}

/**
 * Screenshot the viewport at 1920×1080 to
 * /workspace/outputs/screenshots_<round>/<name>.png and return
 * { path, width, height }, read from the PNG header. Sets the viewport first if
 * it differs, and throws unless the PNG is 1920×1080. `name` may omit '.png'.
 * `banner` ({ role, value, appVersion }) overlays the role, the page URL,
 * appVersion (read with readInertiaPage when not given) and the value under
 * test at the bottom of the page, and removes it after the capture. Never put
 * credentials in a banner.
 */
async function shot(page, { round, name, banner } = {}) {
  const dir = `screenshots_${aixleFileSegment('round', round)}`;
  const file = aixleFileSegment('name', String(name || '').replace(/\.png$/i, ''));
  const path = `/workspace/outputs/${dir}/${file}.png`;

  const viewport = page.viewportSize();
  if (!viewport || viewport.width !== AIXLE_SHOT_WIDTH || viewport.height !== AIXLE_SHOT_HEIGHT) {
    await page.setViewportSize({ width: AIXLE_SHOT_WIDTH, height: AIXLE_SHOT_HEIGHT });
  }

  let overlaid = false;
  if (banner) {
    let appVersion = banner.appVersion;
    if (appVersion === undefined) {
      appVersion = await readInertiaPage(page, { pick: ['settings.appVersion'] })
        .then((result) => result.appVersion)
        .catch(() => null);
    }
    const lines = [
      banner.role ? `Role: ${banner.role}` : null,
      `URL: ${page.url()}`,
      `appVersion: ${appVersion === null || appVersion === undefined ? 'unknown' : appVersion}`,
      banner.value !== undefined && banner.value !== null ? `Value: ${banner.value}` : null,
    ].filter(Boolean);
    await page.evaluate((text) => {
      const box = document.createElement('div');
      box.id = 'aixle-qa-banner';
      box.textContent = text; // textContent, so a value is never parsed as HTML
      box.setAttribute(
        'style',
        'position:fixed;left:0;right:0;bottom:0;z-index:2147483647;pointer-events:none;white-space:pre;' +
          'padding:6px 12px;font:13px/1.4 monospace;color:#fff;background:rgba(170,20,20,0.88);',
      );
      document.body.appendChild(box);
    }, lines.join('\n'));
    overlaid = true;
  }

  let buffer;
  try {
    buffer = await page.screenshot({ path, type: 'png', scale: 'css', timeout: 30000 });
  } finally {
    if (overlaid) {
      await page
        .evaluate(() => {
          const box = document.getElementById('aixle-qa-banner');
          if (box) box.remove();
        })
        .catch(() => {});
    }
  }

  const { width, height } = aixlePngSize(buffer);
  if (width !== AIXLE_SHOT_WIDTH || height !== AIXLE_SHOT_HEIGHT) {
    throw new Error(`${path} is ${width}×${height}, not ${AIXLE_SHOT_WIDTH}×${AIXLE_SHOT_HEIGHT}`);
  }
  return { path, width, height };
}

/**
 * Send each request through appRequest with maxRedirects: 0 and return one row
 * per request: [{ method, path, status, location }]. A request that gets no
 * response gives status null and an `error`, and the other rows still run.
 * Requests run one after another; keep a call to a few dozen of them.
 * For anonymous rows, call signOut first.
 */
async function probeRoutes(page, { requests = [], baseUrl } = {}) {
  const base = aixleRequestBase(page, { baseUrl });
  let token = null;
  const rows = [];
  for (const request of requests) {
    const { method = 'GET', path, csrf = true } = request || {};
    const verb = String(method).toUpperCase();
    try {
      if (csrf && verb !== 'GET' && verb !== 'HEAD' && !token) token = await aixleCsrfToken(page, base);
      const result = await aixleSend(page, base, { method: verb, path, csrf, maxRedirects: 0 }, token);
      rows.push({ method: verb, path, status: result.status, location: result.location });
    } catch (error) {
      rows.push({ method: verb, path, status: null, location: null, error: error.message });
    }
  }
  return rows;
}

/**
 * Sign out by clearing the browser context's cookies and the origin's local
 * and session storage, then load /login and confirm the session is gone:
 * the browser stays on /login and GET /company/projects redirects to /login.
 * Returns { signedOut, landedOn } (landedOn is the path the browser ended on).
 * Accepts { baseUrl } or the env from loadCredentialsAsset (its
 * httpCredentials are applied as in login).
 */
async function signOut(page, options = {}) {
  const base = aixleRequestBase(page, options);
  const clearStorage = () =>
    page
      .evaluate(() => {
        window.localStorage.clear();
        window.sessionStorage.clear();
      })
      .catch(() => {});

  if (aixleOrigin(page.url()) === base) await clearStorage();
  await page.context().clearCookies();
  await aixleOpen(page, { ...options, baseUrl: base }, '/login');
  await clearStorage();
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});

  const landedOn = aixlePathname(page.url());
  const probe = await aixleSend(page, base, { path: '/company/projects', maxRedirects: 0 });
  const toLogin = probe.status >= 300 && probe.status < 400 && aixlePathname(probe.location || '').startsWith('/login');
  return { signedOut: landedOn.startsWith('/login') && toLogin, landedOn };
}
