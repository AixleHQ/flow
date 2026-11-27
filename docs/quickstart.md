# Quickstart

Get a working Aixle Flow instance on your machine. Plan for **10–15
minutes** on first run (most of the time is Docker pulling images and
building agent containers); subsequent starts are seconds.

> **Goal: under 5 minutes.** We're not there yet. The agent image build
> is the slow step. Tracking it on the public roadmap ([ROADMAP.md](../ROADMAP.md)).

## Prerequisites

- **Docker** and **Docker Compose** (Desktop on macOS/Windows, or
  Docker Engine on Linux). 8 GB of RAM allocated to Docker is enough
  for a single developer.
- **git**, **make** and **jq**. `make setup` builds the agent images on the
  host, and the build script reads the list of runtimes with `jq`.
- Ruby and Node are *not* required on the host — everything else runs in
  containers.

## 1. Clone

```bash
git clone https://github.com/AixleHQ/flow.git
cd flow
```

## 2. Configure environment

`make setup` (step 3) creates `.env.development` from `.env.example` and
generates a random `ADMIN_PASSWORD`, the password of every seeded user. To set
values before the first boot, create the file yourself first:

```bash
cp .env.example .env.development
```

`make` generates the password only when `.env.development` does not exist yet,
so a copied file keeps the example's public placeholder: set `ADMIN_PASSWORD`
to a password of your own. You can leave most other values as-is to boot the
app. To enable OAuth sign-in, fill in the matching provider section:

| Want to enable…                  | Variables to set                                              |
| -------------------------------- | ------------------------------------------------------------- |
| Google sign-in                   | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`                    |
| GitHub App integration           | `GITHUB_APP_ID`, `GITHUB_APP_SLUG`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_WEBHOOK_SECRET` |
| GitHub, without an App           | nothing — paste a personal access token in-app (**Connect → GitHub → I'm a developer and just want to try it**) |
| GitLab integration               | a personal access token (added in-app) — set `GITLAB_ENDPOINT` only for self-managed |

The GitHub App is the production path and needs all four variables plus
someone who can install the app and a host github.com can reach — which
a local deployment usually is not. To attach a real repository and clone
it in an agent session locally, connect GitHub with a personal access
token instead: nothing to configure, no install, and no webhooks (CI
gates fall back to polling). See [Integrations](user-guide/integrations.md)
for that walkthrough and the rest of the provider setups.

## 3. Build and seed

```bash
make setup
```

This single command:

- Builds the web and worker images and pulls the Temporal dev server image.
- Installs Ruby gems (Bundler) and JS packages (Yarn) inside the web
  container.
- Creates the database, runs migrations, and seeds defaults.
- Builds the shared `aixle/agent-base-core` base image plus the eight agent
  runtime images (`aixle/claude-code`, `aixle/cursor-cli`, `aixle/codex`,
  `aixle/gemini-cli`, `aixle/antigravity-cli`, `aixle/grok`, `aixle/kiro-cli`,
  `aixle/copilot-cli`).

## 4. Run

```bash
make up
```

This starts every service in one terminal — web, worker, db, redis, traefik,
and Temporal. The entrypoint runs any pending migrations automatically on each
start.

Open **<http://localhost:4000>** and sign in with the seeded user —
`admin@example.com`, an admin of the seeded *Demo Company*, with the
`ADMIN_PASSWORD` from `.env.development`.

## 5. First workflow run

A new project has no board until you pick a layout for it, and no column
starts a workflow until a trigger binds one to it.

1. Create a project. Its **Tasks** page offers the layouts: pick **Simple Kanban**,
   **Dev Team** or **Full SDLC** with **Use this template**. The layout
   creates columns only.
2. Create a workflow — **Workflows → New Workflow**, or install one from
   **Templates** — and turn on **Auto-run available** in the Behavior section
   of each of its sessions, so it can start with nobody at the terminal.
3. On the workflow's **Triggers** tab, add a **Task enters column** trigger in
   **Auto** mode on the column that should start it — **Implementation** on
   the Dev Team board.
4. Drop a card in that column. The trigger starts a workflow run on a
   containerized agent.
5. Watch the run unfold in the right-hand pane: each step shows live
   stdout, token usage, and cost.

To try a workflow without a trigger, press **Run** on it instead.

If the run fails, see [Agents → Troubleshooting](user-guide/agents.md#troubleshooting).

## Updating

```bash
git pull
make up
```

The web container installs new gems and JS packages and runs pending
migrations every time it starts. When `config/agent_runtimes.json` changes
(a new runtime, or a new CLI version), rebuild the agent images with
`make build-agents`.

## Troubleshooting

### `EACCES: permission denied` under `tmp/`, `log/` or `node_modules/`

On Linux, Docker bind-mounts keep the host file owner. The Compose stack runs
`web` and `worker` as your user — `make` exports `UID` and `GID` — so everything
they write stays yours. Running `docker compose` directly, without `make`,
falls back to uid 1000; if yours differs, put `UID=` and `GID=` in `.env`.

A checkout that a root-run container once wrote to can hold root-owned files.
Hand them back once, with nothing deleted:

```bash
sudo chown -R "$(id -u):$(id -g)" .
```

The Yarn `YN0060` / `YN0086` peer-dependency warnings are unrelated and do
not fail setup.

## Common follow-ups

- **Connect a real Git repo** → [Integrations](user-guide/integrations.md)
- **Customize a workflow** → [Workflows](user-guide/workflows.md)
- **Bring your own agent runtime** → [Agents](user-guide/agents.md)
- **Configure environment variables** → [Configuration reference](reference/configuration.md)
