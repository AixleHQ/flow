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
| `bin/forge-deploy` | deploys one Forge environment with that environment's Aixle URLs |

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

## Environments

Aixle runs one registration, **Aixle Flow for Bitbucket** (`ari:cloud:ecosystem::app/9fd780dc-506d-4f8a-b1b4-931a8a8231a2`,
developer space *Dualboot Partners*), in three Forge environments. Each has its own installations,
so a staging deployment never sees a token for a workspace installed on production.

| Forge environment | Environment id | `AIXLE_BASE_URL` (Forge calls) | `AIXLE_APP_URL` (Connect opens) | Installed by |
| --- | --- | --- | --- | --- |
| `production` | `d2cae4d1-9389-4f0d-8315-80b45451ab9e` | `https://flow.aixle.com` | `https://flow.aixle.com` | customers, from the sharing link in the Connect dialog |
| `staging` | `b4abdfa3-53b4-4eb1-a5e5-8d247c87055b` | `https://webhooks-staging.flow.aixle.com` | `https://staging.flow.aixle.com` | our test workspaces |
| `development` | `174ab1f9-d2e2-4134-8b68-d14be8770572` | a developer's tunnel | the same tunnel | a developer's test workspace |

Staging's own host is private (VPN), so Forge reaches it through the public webhooks host, whose
ingress routes `/webhooks/*` — where every endpoint of this app lives. The Connect link still
opens `staging.flow.aixle.com`, so the person confirming it needs the VPN.

## Deploying

Forge commands run with the Forge CLI, logged in through `FORGE_EMAIL` and `FORGE_API_TOKEN` (an
Atlassian API token *without* scopes) of an account in the developer space. Never from a shared
machine's global install — use a container:

```sh
docker run --rm -it -v "$PWD":/app -w /app \
  -e FORGE_EMAIL -e FORGE_API_TOKEN -e FORGE_APP_ID=ari:cloud:ecosystem::app/9fd780dc-506d-4f8a-b1b4-931a8a8231a2 \
  node:22 sh -c 'npm ci && npm install -g @forge/cli@14.2.0 && bin/forge-deploy staging'
```

`bin/forge-deploy <environment>` sets the two URLs for that environment, runs `forge lint` and deploys.
`AIXLE_BASE_URL`, `AIXLE_APP_URL` and `FORGE_APP_ID` are manifest environment variables
(`environment.variables`) the CLI substitutes at deploy time, which is why the script exists: a
production deploy pointed at a tunnel is one forgotten `export` away otherwise. For `development`
it takes your tunnel from `AIXLE_BASE_URL`.

- **Major versions.** Changing a scope, a remote or an egress address is a major version: every
  installation keeps the old one — heartbeats included — until a workspace admin approves the new
  one. `forge deploy` refuses it until asked explicitly; pass `--approve MAJOR_VERSION_RULE` to
  `bin/forge-deploy` only when that is intended.
- Module keys are one namespace across triggers, endpoints and UI modules; `forge lint` refuses a
  key used twice.
- A deploy resets the five-minute scheduled trigger: the next heartbeat comes about five minutes
  later. Tokens already held last two hours or more, so nothing notices.

Install on a test workspace with `forge install -e <environment> -p Bitbucket -s
https://bitbucket.org/<workspace>`, or open the environment's sharing link. Production's link is
the one Aixle shows in the Connect dialog (`BITBUCKET_FORGE_INSTALL_URL`).

## Registering an app of your own

Self-hosted deployments and forks register their own app — one app serves one set of deployments:

1. The CLI validates the manifest before it registers, so it needs some `FORGE_APP_ID` to
   substitute, and it then writes the new id over `app.id`:

   ```sh
   FORGE_APP_ID=ari:cloud:ecosystem::app/00000000-0000-4000-8000-000000000000 \
     forge register "Aixle Flow for Bitbucket" --developer-space-id <id> --accept-terms
   ```

   `forge developer-spaces list` names the spaces you can register in. Read the new id from the
   rewritten `app.id`, put `${FORGE_APP_ID}` back, and keep the id. Forge creates the
   `development`, `staging` and `production` environments.
2. Deploy with your own URLs: `AIXLE_BASE_URL=… AIXLE_APP_URL=… forge deploy -e production`
   (`bin/forge-deploy` carries Aixle's URLs).
3. Developer console → the app → **Distribution** → enable sharing, and copy the install link.
4. Configure the deployment: `BITBUCKET_FORGE_APP_ID`, `BITBUCKET_FORGE_ENVIRONMENT_ID`
   (`forge environments list`) and `BITBUCKET_FORGE_INSTALL_URL`
   (docs/reference/configuration.md).

## Self-hosting

A self-hosted Aixle either connects Bitbucket with a token (Integrations → Connect → Atlassian →
Bitbucket → Use a token; nothing to register) or runs its own app, registered as above, with
`AIXLE_BASE_URL` reachable from the internet. One app serves one deployment: the
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
