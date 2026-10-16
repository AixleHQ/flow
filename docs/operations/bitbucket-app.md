# Operating the Aixle Flow app for Bitbucket

Bitbucket Cloud connects to Aixle primarily through **Aixle Flow for Bitbucket**, a Forge app a
workspace admin installs on a Bitbucket workspace. The app has no Forge functions: every module
calls the deployment's remote endpoints under `/webhooks/bitbucket/forge/`, so the deployment
has to be reachable from Atlassian's cloud. Design:
[`docs/design/bitbucket-integration.md`](../design/bitbucket-integration.md); the app's
protocol, environments and deploy script: [`bitbucket-app/README.md`](../../bitbucket-app/README.md).

A deployment without the app still connects Bitbucket with tokens (Connect → Atlassian →
Bitbucket → Use a token); nothing below is needed for that.

## What is live

| | Production | Staging |
| --- | --- | --- |
| Forge environment | `production` | `staging` |
| Forge calls go to | `https://flow.aixle.com/webhooks/bitbucket/forge/…` | `https://webhooks-staging.flow.aixle.com/webhooks/bitbucket/forge/…` |
| Connect opens | `https://flow.aixle.com/integrations/bitbucket/connect` | `https://staging.flow.aixle.com/integrations/bitbucket/connect` (VPN) |
| Installed from | the sharing link in the Connect dialog | the staging sharing link, or `forge install -e staging` |

Both run the one registration in the *Dualboot Partners* developer space
(`ari:cloud:ecosystem::app/9fd780dc-506d-4f8a-b1b4-931a8a8231a2`). Sharing is enabled for both
environments under **Distribution** in the developer console; the app is not on Marketplace,
which is what keeps install links usable. Installing needs a Bitbucket workspace admin and a team
workspace — Forge does not install on personal workspaces.

Each deployment accepts invocations for exactly one environment of that app:

| Variable | Production | Staging |
| --- | --- | --- |
| `BITBUCKET_FORGE_APP_ID` | `ari:cloud:ecosystem::app/9fd780dc-506d-4f8a-b1b4-931a8a8231a2` | same |
| `BITBUCKET_FORGE_ENVIRONMENT_ID` | `d2cae4d1-9389-4f0d-8315-80b45451ab9e` | `b4abdfa3-53b4-4eb1-a5e5-8d247c87055b` |
| `BITBUCKET_FORGE_INSTALL_URL` | the production sharing link | the staging sharing link |

App mode appears in the connect dialog exactly when all three are set. Staging gets the
integration like production does: unlike Azure DevOps's single app registration, Forge keeps each
environment's installations and tokens apart, so staging never holds a credential for a
production customer.

## Shipping a new version of the app

From `bitbucket-app/`, in a container with the Forge CLI logged in (the app's README has the
`docker run` line), with `FORGE_APP_ID` set to the app id:

```sh
# staging first; check a staging workspace
AIXLE_BASE_URL=https://webhooks-staging.flow.aixle.com AIXLE_APP_URL=https://staging.flow.aixle.com \
  forge deploy -e staging --non-interactive
AIXLE_BASE_URL=https://flow.aixle.com AIXLE_APP_URL=https://flow.aixle.com \
  forge deploy -e production --non-interactive
```

Give both URLs on the command line every time. They are substituted into the manifest at deploy,
and one left over in the shell — a developer's tunnel — would send every production installation's
calls and tokens there. Two things to plan for:

- **A major version waits for every admin.** A changed scope, remote or egress address makes one;
  each installation keeps running the old version — heartbeats included — until a workspace admin
  approves the update in Bitbucket. `forge deploy` refuses it unless given
  `--approve MAJOR_VERSION_RULE`. Ask for read scopes before they are needed.
- **A deploy resets the heartbeat.** The next one comes about five minutes later; tokens already
  held last two hours or more.

A change to the Rails side ships with the normal release; the app needs a deploy only when
`bitbucket-app/` changes.

## What a healthy installation looks like

Measured against a live workspace (2026-10-16):

- **Install → lifecycle:** 3–4 minutes after an install, `POST …/lifecycle` creates the
  installation, unbound, with a token good for four hours.
- **Heartbeat:** `POST …/heartbeat` every five minutes. Forge reuses a token until it has about two
  hours left, so the stored expiry moves forward in steps.
- **Connect:** the admin's **Connect** on Workspace settings → Aixle Flow calls `…/ui/connect`;
  confirming in Aixle binds the workspace to the company and creates the project's connection.
- **Build status:** a status written to a commit reaches `POST …/events` within about a second,
  and the gate waiting on it resolves within seconds.
- **Uninstall:** `POST …/uninstall` arrives within seconds; the installation is marked
  uninstalled, its token dropped, and its connections go into **Error**.

In a Rails console on the deployment:

```ruby
BitbucketInstallation.live.order(:last_invocation_at)
                     .pluck(:workspace_slug, :company_id, :last_invocation_at, :token_expires_at)
```

`last_invocation_at` older than ten minutes means that installation's heartbeats stopped.
`token_expires_at` within thirty minutes means new clones of that workspace are about to fail with
*has not delivered a usable token*.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every Forge request is 401 in the log, with *issued for another app* or *another environment* | `BITBUCKET_FORGE_APP_ID` or `_ENVIRONMENT_ID` names another app or environment | Set both from the table above |
| No Forge request reaches the deployment | The environment was deployed with another `AIXLE_BASE_URL`, or the host is not public | Deploy that environment again with its URLs |
| An install never shows up | The lifecycle event is still on its way | Wait a few minutes; any later invocation — a heartbeat, opening the settings page — records it too |
| Heartbeats stopped for one workspace | The app was uninstalled, or a major version waits for the admin's approval | Ask the workspace admin |
| The admin's Connect says *Only a Bitbucket workspace administrator can connect…* | The account is a member, not an admin, of the workspace | A workspace admin connects |
| The Connect page says the link expired or was used | Links work once, for ten minutes | Press Connect in Bitbucket again |
| `forge deploy` refuses with `MAJOR_VERSION_RULE` | The change is a major version | Decide whether it should be; deploy with `--approve MAJOR_VERSION_RULE` if so |
| `forge lint --fix` "fixed" the manifest | It writes `${…}` variables back as literal values | Review the diff; keep the variables |

## Uninstalling and reinstalling

Uninstalling the app on a workspace sends `preUninstall`: the installation is marked uninstalled,
its token is dropped and every Aixle connection on it goes into **Error**. A reinstall arrives
under a new installation id, unbound; a workspace admin connects it again from the settings page,
and the company's existing Bitbucket connections move to the new installation with their
repositories.
