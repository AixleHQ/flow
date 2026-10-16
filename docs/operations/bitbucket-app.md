# Operating the Aixle Flow app for Bitbucket

The Bitbucket integration's primary connection is a Forge app, **Aixle Flow for Bitbucket**,
that a workspace admin installs on a Bitbucket Cloud workspace. The app has no Forge functions:
every module calls this deployment's remote endpoints, so the deployment has to be reachable from
Atlassian's cloud. Design: [`docs/design/bitbucket-integration.md`](../design/bitbucket-integration.md);
the app's own protocol and build steps: [`bitbucket-app/README.md`](../../bitbucket-app/README.md).

A deployment without the app still connects Bitbucket with tokens (Connect → Atlassian → Bitbucket
→ Use a token); nothing below is needed for that.

## One registration, three environments

Aixle's deployments share one registration in the **Dualboot Partners** developer space, with the
three environments `forge register` creates:

| Forge environment | Remote (`AIXLE_BASE_URL`) | Installs |
| --- | --- | --- |
| `production` | `https://flow.aixle.com` | customers' workspaces, through the sharing link |
| `staging` | the staging host | our test workspaces |
| `development` | a developer's tunnel | a developer's test workspace |

Each environment has its own installations and its own environment id, and each deployment
accepts invocations for exactly one: `BITBUCKET_FORGE_APP_ID` + `BITBUCKET_FORGE_ENVIRONMENT_ID`.
A staging deployment never receives a token for a workspace installed on production.

A self-hosted deployment registers its own app the same way, with its own base URL, or uses
tokens only.

## Deploying a version

From `bitbucket-app/`, in a container (never a host-global Forge CLI), logged in through
`FORGE_EMAIL` / `FORGE_API_TOKEN` (an Atlassian API token *without* scopes):

```sh
export FORGE_APP_ID=ari:cloud:ecosystem::app/<uuid> AIXLE_BASE_URL=https://flow.aixle.com
npm ci
forge lint
forge deploy -e production --non-interactive
```

- `forge lint` must be clean. Module keys are one namespace across triggers, endpoints and UI
  modules.
- **Changing a scope, a remote or an endpoint is a major version.** Every installation keeps
  running the old version — heartbeats included — until a workspace admin approves the new one.
  Plan scope changes; add read scopes before they are needed.
- A deploy resets the scheduled trigger: the next heartbeat comes about five minutes later. Tokens
  already held last two hours or more, so nothing notices.

Then set or check the deployment's variables (`docs/reference/configuration.md`):

| Variable | Where it comes from |
| --- | --- |
| `BITBUCKET_FORGE_APP_ID` | `app.id` after `forge register` |
| `BITBUCKET_FORGE_ENVIRONMENT_ID` | `forge environments list` |
| `BITBUCKET_FORGE_INSTALL_URL` | Developer console → the app → **Distribution** → enable sharing → install link |

App mode is offered in the connect dialog only when all three are set.

## What a healthy installation looks like

Observed against a live workspace (2026-10-16):

- **Install → lifecycle event:** about 3–4 minutes after the install, `POST
  /webhooks/bitbucket/forge/lifecycle` creates the installation, unbound, with a token good for
  four hours.
- **Heartbeat:** `POST /webhooks/bitbucket/forge/heartbeat` every five minutes. Forge reuses a
  token until it has about two hours left, so the stored expiry moves forward in steps rather than
  on every tick.
- **Build status:** a status written to a commit reaches `POST /webhooks/bitbucket/forge/events`
  within about a second, and the gate waiting on it resolves within seconds.
- **Settings page:** `POST /webhooks/bitbucket/forge/ui/<action>` when a workspace admin opens
  **Workspace settings → Aixle Flow**.

In the Rails console:

```ruby
BitbucketInstallation.live.order(:last_invocation_at).pluck(:workspace_slug, :company_id, :last_invocation_at, :token_expires_at)
```

`last_invocation_at` older than ten minutes means the heartbeats stopped. `token_expires_at`
within thirty minutes means new clones of that workspace are about to fail with *has not
delivered a usable token*.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every Forge request is 401 in the log | `BITBUCKET_FORGE_APP_ID` or `_ENVIRONMENT_ID` names another app or environment, or is unset | Set both from `forge environments list` |
| No Forge request reaches the deployment at all | `AIXLE_BASE_URL` at deploy time pointed elsewhere, or the host is not reachable from the internet | Redeploy with the right base URL |
| An install never shows up | The lifecycle event is still on its way (minutes) | Wait; any later invocation — a heartbeat, opening the settings page — records it too |
| Heartbeats stopped for one workspace | The app was uninstalled, or a major version waits for approval | Ask the workspace admin |
| `forge deploy` says the manifest is invalid after an upgrade of the CLI | Forge CLI changes manifest rules | `forge lint --fix`, then review the diff — it substitutes `${…}` variables with literal values |

## Uninstalling and reinstalling

Uninstalling the app on a workspace sends `preUninstall`: the installation is marked uninstalled,
its token is dropped and every Aixle connection on it goes into **Error**. A reinstall arrives
under a new installation id, unbound; a workspace admin connects it again from the settings page,
and the company's existing Bitbucket connections move to the new installation with their
repositories.
