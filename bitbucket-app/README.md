# Aixle Flow — Bitbucket Cloud app

The Bitbucket side of Aixle's Bitbucket integration: a Forge app a workspace administrator installs
on a Bitbucket Cloud workspace. It is the GitHub App equivalent — agents get a bot identity on the
workspace and short-lived tokens, and nobody pastes a credential. Design:
[`docs/design/bitbucket-integration.md`](../docs/design/bitbucket-integration.md) §5.

Bitbucket Cloud only, and team workspaces only (Forge cannot be installed on a personal workspace).

## What it does

- **Hands Aixle the app token.** Forge pushes the app's system token with every invocation and
  offers no way to ask for one, so a five-minute scheduled trigger calls Aixle directly: each tick
  brings a token with at least two hours of life. Aixle keeps whichever token it holds that expires
  later.
- **Connect.** Workspace settings → Aixle Flow shows a workspace administrator what the workspace
  is connected to and starts Connect: Aixle opens in a new tab with a single-use link, where a
  signed-in Aixle user chooses the project.
- **Disconnect.** The same page unbinds the workspace from its Aixle company. Uninstalling the app
  ends everything.
- **Events.** Build statuses (Aixle CI gates resolve on them) and repository renames and deletions.

There are no Forge functions: every module routes to the Aixle deployment (`remotes.aixle`), so
nothing the app does is metered as Forge compute, and all logic lives in Aixle.

## Layout

| Path | What |
|---|---|
| `manifest.yml` | modules, endpoints, the `aixle` remote, scopes, environment variables |
| `src/frontend/connect.jsx` | the settings page (UI Kit, `render: native`); Forge bundles it at deploy |
| `package.json`, `package-lock.json` | the page's dependencies, pinned |

## Protocol with Aixle

Every request carries a Forge Invocation Token (`authorization: Bearer <FIT>`), which Aixle
verifies against Forge's published keys before anything else: RS256 only, `iss`
`forge/invocation-token`, `aud` = the app id, `app.environment.id` = the environment this
deployment serves (`BITBUCKET_FORGE_APP_ID`, `BITBUCKET_FORGE_ENVIRONMENT_ID`). The installation,
the workspace and the viewing user come from the token's claims, never from a body. Every endpoint
is declared with `appSystemToken`, so every request also carries `x-forge-oauth-system`.

| Module | Aixle endpoint | Aixle does |
|---|---|---|
| `trigger` lifecycle (installed, upgraded) | `POST /webhooks/bitbucket/forge/lifecycle` | records the installation (unbound) and its installer; stores the token |
| `scheduledTrigger` (`fiveMinute`) | `POST /webhooks/bitbucket/forge/heartbeat` | stores the token |
| `trigger` repository events | `POST /webhooks/bitbucket/forge/events` | build status → re-checks the CI gates on that repository and commit; repository updated → re-reads its name; deleted → logged |
| `preUninstall` | `POST /webhooks/bitbucket/forge/uninstall` | marks the installation uninstalled, drops its token, puts its connections in error |
| settings page | `POST /webhooks/bitbucket/forge/ui/{status,connect,disconnect}` | see below |

Events and schedules answer `{"ok": true}` within Forge's five seconds; anything slow is queued.
Nothing redirects (Forge counts a 3xx as a failure). An installation already uninstalled stays
that way: a late delivery does not bring it back. A reinstall arrives under a new installation id
and retires the workspace's previous one.

### The settings page

The page calls `ui/status` on open, `ui/connect` and `ui/disconnect` on its buttons. Aixle checks
that the viewing account administers the workspace (`GET /2.0/workspaces/{uuid}/permissions`,
permission `owner`) on every one. Refusals answer **200** with `{"ok": false, "error", "message"}`,
because `invokeRemote` rejects a non-2xx response before the page can read why.

- `status` → `{ok, bound, workspace: {slug, name}, company, projects, bound_by, bound_at}`.
- `connect` → `{ok, url}`: `<Aixle>/integrations/bitbucket/connect#pairing=<id>.<secret>`. The
  page opens it with `router.open`. The pairing is single use, lives ten minutes, is bound to the
  installation and the administrator, and only its secret's digest is stored. The secret travels
  in the fragment, so no server log on the way sees it.
- `disconnect` → the new status. The workspace is unbound from its company and every connection on
  it goes into error until it is connected again.

In Aixle, the connect page reads the fragment, shows the workspace, and a signed-in user who may
manage a project's integrations confirms it. The first confirmation binds the workspace to that
user's company — one company per workspace. A workspace bound to another company is refused
until its administrator disconnects it here. Further projects of the same company connect from
their Integrations page by naming the workspace, with no trip to Bitbucket.

## Developing

Forge commands run with the Forge CLI, logged in as an Atlassian account that administers a test
workspace. Never on a shared machine's global install — use a container:

```sh
docker run --rm -it -v "$PWD":/app -w /app \
  -e FORGE_EMAIL -e FORGE_API_TOKEN -e FORGE_APP_ID -e AIXLE_BASE_URL \
  node:22 sh -c 'npm ci && npx @forge/cli@latest <command>'
```

`FORGE_APP_ID` and `AIXLE_BASE_URL` are manifest environment variables
(`environment.variables`): the CLI substitutes them from the shell, and `AIXLE_BASE_URL` defaults
to `https://flow.aixle.com`.

1. **Register** your own app once: `forge register "Aixle Flow (dev)"`. It prints the app id
   (`ari:cloud:ecosystem::app/<uuid>`); export it as `FORGE_APP_ID`.
2. **Point it at a reachable Aixle.** Forge calls the remote from Atlassian's cloud, so a local
   stack needs a public tunnel: `export AIXLE_BASE_URL=https://<tunnel-host>`.
3. **Lint and deploy:** `forge lint`, then `forge deploy -e development` (or `staging`,
   `production`). Changing a scope, a remote or an endpoint makes a major version, which every
   installation has to approve again; changing the scheduled trigger resets it, and the first
   tick comes about five minutes after deploy.
4. **Install:** `forge install -e development` and choose Bitbucket and the workspace when asked,
   or share the install link from the developer console (Distribution → Sharing) for another
   workspace.
5. **Configure Aixle** with the app id, the environment id (`forge environments list`, or the
   `app.environment.id` of the first invocation Aixle refuses in its log) and the install link:
   `BITBUCKET_FORGE_APP_ID`, `BITBUCKET_FORGE_ENVIRONMENT_ID`, `BITBUCKET_FORGE_INSTALL_URL`
   (docs/reference/configuration.md).

Our deployments use one registration with three Forge environments — `production` →
`https://flow.aixle.com`, `staging` → the staging host, `development` → a developer's tunnel —
each with its own installations. A staging deployment never sees a token for a workspace
installed on production.

## Self-hosting

A self-hosted Aixle either connects Bitbucket with a token (Integrations → Connect → Bitbucket →
Use a token; nothing to register) or runs its own app: steps 1–5 above with `AIXLE_BASE_URL` set
to the deployment, which must be reachable from the internet. One app serves one deployment: the
remote's base URL is fixed at deploy, and the deployment refuses invocations issued for any other
app or environment.

## Security notes

- The app token reaches every repository of the workspace the app's bot can reach, for up to
  four hours. Aixle hands it to a session's git credential helper for the repositories that
  session holds; it is never written to disk in the container. A workspace that needs
  per-repository isolation connects with repository access tokens instead.
- Never log `authorization`, `x-forge-oauth-system` or `x-forge-oauth-user`. Aixle drops them
  from error reports.
- The pairing link is the administrator's own: opened by their click, valid once, for ten
  minutes. The settings page always shows which Aixle company and projects the workspace serves,
  so a wrong binding is visible to the people who own the workspace, and Disconnect undoes it.
