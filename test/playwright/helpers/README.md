# Playwright helpers

Helpers for testing the application on staging through the Playwright MCP tool `browser_run_code`
(`browser_run_code_unsafe` in some MCP builds). They live in one file, [`helpers.js`](helpers.js).

## Why one plain-JavaScript snippet

`browser_run_code` takes a single self-contained `async (page) => { … }` function. It cannot import modules, has no
`process.env`, no TypeScript, and no global `URL`. So `helpers.js` is plain JavaScript with no imports, and it defines
every helper at once: paste the whole file at the top of the function body, then call the helpers below it. One snippet
is simpler to keep correct than a set of per-helper snippets that each repeat the shared internals.

| Missing in the sandbox                 | Use instead                                                            |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `require`, `import()`                  | paste `helpers.js` in full                                             |
| `process`, `process.env`               | `loadCredentialsAsset(page)` for credentials                           |
| `setTimeout`                           | `await page.waitForTimeout(ms)`                                        |
| `URL`, `URLSearchParams`               | the helpers cut paths out by hand (`aixlePathname`, `aixleFormEncode`) |
| `Buffer`, `TextEncoder`                | index the buffers Playwright returns (`shot` reads the PNG header so)  |
| an in-page `fetch` that sees redirects | `page.request` (`appRequest`): it shares the context's cookies         |

A tool call has to return within a few minutes: one that stays silent for 30 minutes gets its session killed. Every
request in these helpers times out after 30 seconds.

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
`/workspace/assets/STAGING_CREDENTIALS_SECRETS.txt`. Its lines are `KEY="value"` (single quotes, no quotes and an
`export ` prefix are accepted too):

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

If neither `STAGING_COMPANY_ADMIN_CREDENTIALS` nor `STAGING_COMPANY_EMPLOYEE_CREDENTIALS` is in the file,
`loadCredentialsAsset` throws and lists the key names it did find (never the values), so a format change is visible
without printing the file.

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

  const signIn = await ensureSignedInAs(page, staging, 'companyAdmin'); // signs in only if needed
  await goToAgents(page, staging, 3); // project 3 is "QA Test Project" on staging

  return { signIn, url: page.url(), title: await page.title() };
};
```

The calls of one QA round share the browser page and its cookies, so the session from one call is still there in the
next. Start every call with `ensureSignedInAs` rather than `signOut` plus `loginAs…`: it signs in only when the browser
is signed out or signed in as another account.

## Sign-in limit

Staging allows **10 sign-ins per hour for one account from one IP** (the `login/combo` throttle in
`config/initializers/rack_attack.rb`, counting `POST /login`). Past it, sign-in answers `429` and the round stalls until
the hour is up.

- Start each call with `ensureSignedInAs(page, staging, role)`. A call that finds the session already signed in as that
  role sends no `POST /login`.
- Group the cases of one role together. Every role switch is a sign-in.
- Use `signOut` only for checks that need a signed-out session.
- Use `loginAs…` only for a case that needs a fresh sign-in: they always clear the cookies and sign in again.

On the public entry, add Basic Auth to the asset as `STAGING_HTTP_CREDENTIALS`; `loadCredentialsAsset` then returns it
as `staging.httpCredentials`. Do not write it into the snippet: the MCP echoes the code it runs.

## Helper reference

Every helper is `async`, takes `page` first and `env` (or an options object, from the requests section on) second, and
throws with a readable message when it fails.

### Credentials and sign-in

| Helper                                                                 | What it does                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loadCredentialsAsset(page, path?)`                                    | Reads the credentials asset (see above).                                                                                                                                                                                          |
| `login(page, env, credentials)`                                        | Clears cookies, opens `/login`, fills **Email**, clicks **Continue** (`POST /login/identify`), fills **Password**, clicks **Sign in**, and waits until the browser leaves `/login`.                                               |
| `loginAsCompanyAdmin(page, env, credentials = env.companyAdmin)`       | `login` as CompanyAdmin. Lands on `/company/projects`.                                                                                                                                                                            |
| `loginAsCompanyEmployee(page, env, credentials = env.companyEmployee)` | `login` as CompanyEmployee. Lands on `/company/projects`.                                                                                                                                                                         |
| `loginAsAdmin(page, env, credentials = env.admin)`                     | Platform super admin: clears cookies, opens `/admin/login` (one form: **Email**, **Password**, **Sign in**), and waits until the browser leaves `/admin/login`. Not verified on staging: the QA asset has no super-admin account. |
| `ensureSignedInAs(page, env, role)`                                    | Signs in as `role` only when the browser is not already signed in as that account. See below.                                                                                                                                     |

#### `ensureSignedInAs(page, env, role)`

`role` is `'companyAdmin'` or `'companyEmployee'`, the keys of `loadCredentialsAsset`, and `env` is what
`loadCredentialsAsset` returns. Returns `{ role, reused }`.

- It sends one `GET /profile` without following redirects. A `302` to `/login` means signed out. A `200` carries the
  shared `currentUser` prop in its Inertia payload: if that is the role's account, it returns `{ role, reused: true }`
  without submitting the sign-in form.
- When the session is signed out or is another account, it signs in with `login`, reads `/profile` again to confirm the
  account, and returns `{ role, reused: false }`. It throws if the session still is not that account.
- Any other answer from `/profile` (no response, another status or redirect, a page without a readable `currentUser`)
  throws, naming the path and the status, and does not sign in or clear the cookies. A transient staging error then
  costs no sign-in; run the call again.
- It does not navigate when the session is reused: the page stays where the last call left it. Open the page you need
  with `goTo…` before you interact with it or take a screenshot. (After a sign-in, the page is where `login` landed.)
- The email is compared inside the helper. It is not returned, and errors do not include it.

```js
await ensureSignedInAs(page, staging, 'companyAdmin'); // { role: 'companyAdmin', reused: false } (signed in)
await ensureSignedInAs(page, staging, 'companyAdmin'); // { role: 'companyAdmin', reused: true }  (no POST /login)
await ensureSignedInAs(page, staging, 'companyEmployee'); // { role: 'companyEmployee', reused: false }
```

Sign-in uses accessible locators (`getByLabel('Email')`, `getByLabel('Password')`, `getByRole('button', …)`), so it
follows the visible form, not field names.

### Navigation

Each `goTo*` helper opens its route and checks the browser stayed there. It throws on an HTTP error, on a redirect to
sign-in, and on any other redirect. A page a role may not open redirects back or to `/`. Before checking, it waits up
to 5 seconds for the network to go idle, so a redirect the frontend makes right after mount (an Inertia `router.visit`
in an effect, a guard component) is caught too. A client-side redirect later than that is not.

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

### Requests, page payloads, screenshots and route probes

These five take `page` and one options object, not `env`. A relative `path` resolves against `options.baseUrl` when it
is given, else staging (`https://staging.flow.aixle.com`), as `env.baseUrl` does for the helpers above. The origin of
the open page is never used: after an external link or an OAuth redirect it can be a foreign host. When the credentials
asset sets `STAGING_URL`, pass `baseUrl: staging.baseUrl`, as in the worked example.

Requests go through `page.request`, so they carry the browser context's cookies (and its HTTP Basic Auth, set by
`login`/`signOut` from `env.httpCredentials`). Each request times out after 30 seconds.

#### `appRequest(page, options)`

Sends one HTTP request as the signed-in browser and returns `{ status, location, contentType, json, text }`.

| Option         | Default | Meaning                                                                                                                 |
| -------------- | ------- | ----------------------------------------------------------------------------------------------------------------------- |
| `method`       | `'GET'` | Any HTTP method.                                                                                                        |
| `path`         |         | `'/company/projects'` or an absolute URL. Required.                                                                     |
| `json`         |         | Body sent as `application/json` (and `Accept: application/json` unless `headers` sets one).                             |
| `form`         |         | Fields sent URL-encoded, with `authenticity_token` added. For `PATCH`/`PUT`/`DELETE` it POSTs them with `_method`.      |
| `csrf`         | `true`  | Sends the session's CSRF token on non-GET requests (`X-CSRF-Token`, and in `form`). `false` sends none: expect `422`.   |
| `maxRedirects` | `0`     | `0` reports a `302` and its `Location` instead of following it. An in-page `fetch` would see only an opaque status `0`. |
| `headers`      | `{}`    | Extra request headers.                                                                                                  |
| `textLimit`    | `2000`  | Characters of a non-JSON body kept in `text`, so an HTML page does not flood the context.                               |
| `baseUrl`      |         | See above.                                                                                                              |

- `json` is the parsed body when the response is JSON, and then `text` is `null`. Otherwise `json` is `null`.
- `location` is shortened to a path (`'/login'`) when it points at the base URL.
- The CSRF token comes from the `XSRF-TOKEN` cookie that inertia_rails sets on every response, then from
  `meta[name="csrf-token"]`, then from `input[name="authenticity_token"]` on the open page, then from the HTML of
  `/login`. The cookie comes first because an Inertia visit (the one after sign-in) does not reload `<head>`, so the meta
  tag can still hold the token from before sign-in. The token is never returned.

```js
await loginAsCompanyEmployee(page, staging);
await appRequest(page, { path: '/company/assets' }); // { status: 302, location: '/', … }
await appRequest(page, { method: 'DELETE', path: '/logout', form: {}, csrf: false }); // { status: 422, … }
await appRequest(page, { method: 'DELETE', path: '/logout', form: {} }); // { status: 302, location: '/login', … }
```

#### `readInertiaPage(page, { path, pick = [], baseUrl } = {})`

Fetches a page's HTML with the session cookies, following redirects, and parses the Inertia payload in
`<script data-page="app" type="application/json">`. It returns `{ url, status, component, version, appVersion, props }`.

- Do not read the `#app[data-page]` attribute: with `use_script_element_for_initial_page` the payload is in the script
  element. Do not read the DOM after load either, since hydration removes the element. This helper reads the HTML.
- `path` defaults to the page the browser is on, when that page is on the base URL; otherwise pass `path`.
- `url` is the path the request ended on after redirects, so a redirect to `/login` shows there.
- `appVersion` is `props.settings.appVersion`: the deployed commit. Read it at the start and at the end of a round.
- `pick` takes dotted paths (`'projects.0.id'`) and returns only those props, keyed by path. A path that does not
  resolve gives `null`. Use it on pages with large props.
- Throws `No Inertia page payload at <path> (HTTP <status>)` on a response that is not an Inertia page.

```js
await readInertiaPage(page, { path: '/company/projects', pick: ['settings.appVersion', 'projects.0.id'] });
// { url: '/company/projects', status: 200, component: 'Projects/IndexPage', version: null,
//   appVersion: '10dd9779…', props: { 'settings.appVersion': '10dd9779…', 'projects.0.id': 3 } }
```

#### `shot(page, { round, name, banner, baseUrl })`

Screenshots the viewport to `/workspace/outputs/screenshots_<round>/<name>.png` and returns `{ path, width, height }`.

- It sets the viewport to 1920×1080 first if it differs.
- It reads the size from the PNG header of the returned buffer, and throws unless it is 1920×1080. The capture uses
  CSS pixels, so a device scale factor does not change the size.
- `round` and `name` may hold letters, digits, `.`, `_` and `-` only. `name` may end in `.png`.
- `banner` (`{ role, value, appVersion }`, all optional) overlays a strip at the bottom with the role, the page URL,
  `appVersion` and the value under test, and removes it after the capture. `appVersion` is read with `readInertiaPage`
  (against `baseUrl`) when it is not given. Never put a credential in a banner.

```js
await shot(page, {
  round: 3,
  name: 'employee-assets-redirect',
  banner: { role: 'CompanyEmployee', value: '/company/assets → /' },
});
// { path: '/workspace/outputs/screenshots_3/employee-assets-redirect.png', width: 1920, height: 1080 }
```

#### `probeRoutes(page, { requests, baseUrl })`

Sends each request (`{ method = 'GET', path, csrf = true }`) through `appRequest` with `maxRedirects: 0`, one after
another, and returns one row per request: `[{ method, path, status, location }]`. A request that gets no response gives
`status: null` and an `error`, and the remaining rows still run. Keep a call to a few dozen requests. For anonymous rows,
call `signOut` first. The CSRF token is resolved for every row, so a row that resets the session (`DELETE /logout`, a
sign-in) does not leave the rows after it with a stale token and false `422`s.

```js
await loginAsCompanyEmployee(page, staging);
await probeRoutes(page, {
  requests: [{ path: '/company/assets' }, { method: 'DELETE', path: '/logout', csrf: false }],
});
// [{ method: 'GET', path: '/company/assets', status: 302, location: '/' },
//  { method: 'DELETE', path: '/logout', status: 422, location: null }]
```

Baseline on staging (checked 2026-10-27, appVersion `10dd9779`; `—` means not checked). These are expected, so do not
report them as bugs:

| Route                                                                      | Anonymous            | CompanyEmployee      | CompanyAdmin         |
| -------------------------------------------------------------------------- | -------------------- | -------------------- | -------------------- |
| `/`                                                                        | 200                  | 200                  | 200                  |
| `/login`                                                                   | 200                  | —                    | —                    |
| `/profile`, `/company/projects`, `/company/members`                        | 302 → `/login`       | 200                  | 200                  |
| `/company/assets`, `/company/sessions`                                     | 302 → `/login`       | 302 → `/`            | 200                  |
| `/company/projects/3/{overview,agents,skills,tools}`                       | —                    | 200                  | 200                  |
| `/company/projects/3/{integrations,mcp_servers,repositories,config_items}` | —                    | 200                  | 200                  |
| `/admin`                                                                   | 302 → `/admin/login` | 302 → `/admin/login` | 302 → `/admin/login` |
| any non-GET with `csrf: false`                                             | 422                  | 422                  | 422                  |

#### `signOut(page, { baseUrl } = {})`

Clears the context's cookies and the origin's local and session storage, loads `/login`, and confirms the session is
gone: the browser stays on `/login` and `GET /company/projects` answers `302 → /login`. Returns
`{ signedOut, landedOn }`. It accepts the `env` from `loadCredentialsAsset` too, and then applies its `httpCredentials`.
Use it only before checks that need a signed-out session. To switch roles, call `ensureSignedInAs` with the other role:
it signs in as that account without signing out first.

```js
await signOut(page, staging); // { signedOut: true, landedOn: '/login' }
```

### Agent sessions

These four start an agent session on staging, follow it, finish it and read its log through
`/api/v1/terminal_sessions`, as the signed-in user. Like `appRequest` they take `page` and one options object, and each
accepts `baseUrl`. `show`, `finish` and `destroy` only find sessions the signed-in user owns, so follow a session as the
role that started it. `id` may be the numeric id or the route token in every helper. The API's `finish` takes the
numeric id only, so `finishSession` resolves a route token with `GET /api/v1/terminal_sessions/:id` first.

**Finish every session you start**, so no container is left running. `DELETE /api/v1/terminal_sessions/:id` is no
substitute: it refuses an active session with `400 Cannot delete active session`.

Session states are `not_started`, `queued`, `running`, `ready`, `finishing`, `finished`, `failed` and `cancelled`. The
last three are terminal.

#### `startSession(page, { projectId, agentType, mode = 'non_interactive', sessionType = 'agent_session', prompt, baseUrl })`

Sends `POST /api/v1/terminal_sessions` with the session cookie and the CSRF token, and the body
`{ terminal_session: { project_id, session_type, agent_type, mode, initial_prompt } }`. Returns
`{ id, state, routeToken }`.

- `projectId` and `agentType` (a runtime id from `config/agent_runtimes.json`, such as `claude_code`) are required.
  `prompt` is required for a `non_interactive` session.
- Throws with the API's message unless it answers `201`: `422` with validation errors or a preflight failure (no
  credential for the runtime), `403` for a viewer.
- Staging has no credentials for some runtimes (Gemini, a Codex subscription, xAI, Kiro). Use one that works there, and
  say which one in the result.

```js
const session = await startSession(page, { projectId: 3, agentType: 'claude_code', prompt: 'Reply with OK and stop.' });
// { id: 28731, state: 'not_started', routeToken: 'k3…' }
```

#### `waitForSession(page, { id, until = ['ready', 'finished', 'failed'], timeoutMs = 240000, intervalMs = 8000, baseUrl })`

Polls `GET /api/v1/terminal_sessions/:id` every `intervalMs` and returns `{ id, final, timedOut, timeline }`.

- It stops when the state is one of `until`, and also on any terminal state (`finished`, `failed`, `cancelled`), since
  nothing leaves those.
- `timeline` has one row `{ t, state, containerId, errorMessage }` (`t` is an ISO time) each time any of those three
  fields changes. That is the state table for the result comment.
- After `timeoutMs` it returns with `timedOut: true` and `final` set to the last state seen. Call it again to keep
  waiting; do not raise `timeoutMs` to wait longer in one call. `timeoutMs` is capped at 10 minutes, so a call never
  comes near the 30-minute silence limit.
- Throws when the first poll fails, for example `404` for a session the signed-in user does not own.
- A later poll that fails (a `5xx` during a deploy, no response) is retried up to twice, `intervalMs` apart and within
  `timeoutMs`. If it still fails, the helper returns `{ id, final, timedOut: false, error, timeline }`, with `final`
  the last state seen and the timeline so far, instead of throwing. Check `error`, then call it again.

```js
const wait = await waitForSession(page, { id: session.id });
// { id: 28731, final: 'ready', timedOut: false,
//   timeline: [{ t: '2026-10-27T17:40:02.114Z', state: 'queued', containerId: null, errorMessage: null },
//              { t: '2026-10-27T17:40:34.871Z', state: 'running', containerId: 'f1c2…', errorMessage: null }, …] }
```

#### `finishSession(page, { id, baseUrl })`

Calls `POST /api/v1/terminal_sessions/:id/finish` and returns `{ status, state, error }`.

- On `200` the session is usually `finishing`, not yet `finished`. Follow with
  `waitForSession(page, { id, until: ['finished'] })`.
- A session that cannot be finished, for example one already `finished`, answers
  `400 Cannot finish session in state: …`. The helper does not throw: `status` is `400`, `error` carries the message,
  and `state` is read with `GET /api/v1/terminal_sessions/:id`.
- Any other status (`404`, `403`, `422`, `5xx`) throws with the API's message, so a failed finish never looks like a
  result. A route token that `show` cannot resolve throws too.

```js
await finishSession(page, { id: session.id }); // { status: 200, state: 'finishing', error: null }
await waitForSession(page, { id: session.id, until: ['finished'] }); // { final: 'finished', … }
```

#### `sessionLog(page, { id, tailLines = 200, grep, baseUrl })`

Fetches `GET /api/v1/terminal_sessions/:id/terminal_log`, strips ANSI escape codes, and returns
`{ bytes, truncated, totalLines, lines }`.

- **The log exists only for a `finished` or `failed` session** (and only when it wrote a `terminal_output.log`). Any
  other state answers `404`, and the helper throws. Finish the session and wait for `finished` before reading it.
- `lines` is the last `tailLines` lines. With `grep` (a `RegExp`, or a string matched as a plain substring) it is the
  last `tailLines` lines that match. Whole logs of 1–2 MB never reach the context.
- The log is the raw terminal stream, so lines are rebuilt from it: cursor-forward codes become spaces (a TUI writes
  them instead of spaces), a column jump becomes one space, and a carriage return, a newline or a move to another row
  ends the line. Blank lines are dropped. A TUI redraws its screen, so some lines repeat; `grep` is the way to find a
  line.
- `bytes` is the size of the log as served. The server serves at most the last 2 MB, and `truncated` is `true` when it
  cut the log (`X-Log-Truncated: true`). `totalLines` counts the lines after cleaning.

```js
await sessionLog(page, { id: session.id, tailLines: 20 });
// { bytes: 48213, truncated: false, totalLines: 611, lines: ['…', …] }
await sessionLog(page, { id: session.id, grep: /error|fail/i });
```

#### Worked example: one session, start to finish

A single wait returns after at most `timeoutMs`. If it comes back with `timedOut: true`, run another
`browser_run_code_unsafe` call that waits on the same `id` rather than one long call.

```js
async (page) => {
  // ---- paste test/playwright/helpers/helpers.js here ----

  const staging = await loadCredentialsAsset(page);
  const { baseUrl } = staging;
  await ensureSignedInAs(page, staging, 'companyAdmin');

  const session = await startSession(page, {
    projectId: 3,
    agentType: 'claude_code',
    prompt: 'Reply with OK and stop.',
    baseUrl,
  });
  const up = await waitForSession(page, { id: session.id, baseUrl });
  // Finish every session you start; then wait for `finished`, since the log exists only then.
  const finish = up.final === 'finished' ? null : await finishSession(page, { id: session.id, baseUrl });
  const done = await waitForSession(page, { id: session.id, until: ['finished'], baseUrl });
  const tail = await sessionLog(page, { id: session.id, tailLines: 20, baseUrl });
  const grep = await sessionLog(page, { id: session.id, grep: 'OK', baseUrl });
  return { session, timeline: [...up.timeline, ...done.timeline], finish, tail, grep };
};
```

### Worked example: a round

```js
async (page) => {
  // ---- paste test/playwright/helpers/helpers.js here ----

  const staging = await loadCredentialsAsset(page);
  const signIn = await ensureSignedInAs(page, staging, 'companyEmployee');
  const { baseUrl } = staging;
  const start = await readInertiaPage(page, { path: '/company/projects', pick: ['settings.appVersion'], baseUrl });
  const rows = await probeRoutes(page, {
    requests: [{ path: '/company/assets' }, { path: '/company/sessions' }],
    baseUrl,
  });
  // A reused session does not navigate, so open the page before the screenshot.
  await goToProjects(page, staging);
  const evidence = await shot(page, {
    round: 1,
    name: 'employee-projects',
    banner: { role: 'CompanyEmployee' },
    baseUrl,
  });
  // Last: the anonymous check. The next call's ensureSignedInAs signs in again.
  const anonymous = await signOut(page, staging);
  return { signIn, appVersion: start.appVersion, rows, evidence, anonymous };
};
```
