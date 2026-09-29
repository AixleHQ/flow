# Quickstart

Get a working Aixle Flow instance on your machine. Plan for **10–15
minutes** on first run (most of the time is Docker pulling images and
building agent containers); subsequent starts are seconds.

> **Goal: under 5 minutes.** We're not there yet. The agent image build
> is the slow step. Tracking on [ROADMAP.md](../ROADMAP.md).

## Prerequisites

- **Docker** and **Docker Compose** (Desktop on macOS/Windows, or
  Docker Engine on Linux). 8 GB of RAM allocated to Docker is enough
  for a single developer.
- **git**.
- That's it. Ruby and Node are *not* required on the host — everything
  runs in containers.

## 1. Clone

```bash
git clone https://github.com/AixleHQ/flow.git
cd flow
```

## 2. Configure environment

```bash
cp .env.example .env.development
```

You can leave most values as-is to boot the app. To enable OAuth sign-in,
fill in the matching provider section:

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
gates fall back to polling). See
[user-guide/integrations.md](user-guide/integrations.md) for that
walkthrough and the rest of the provider setups.

## 3. Build and seed

```bash
make setup
```

This single command:

- Builds the web, worker, and Temporal images.
- Installs Ruby gems (Bundler) and JS packages (Yarn) inside the web
  container.
- Creates the database, runs migrations, and seeds defaults.
- Builds the shared `aixle/agent-base-core` base image plus the seven agent
  runtime images (`aixle/claude-code`, `aixle/cursor-cli`, `aixle/codex`,
  `aixle/gemini-cli`, `aixle/antigravity-cli`, `aixle/grok`, `aixle/kiro-cli`).

## 4. Run

```bash
make up
```

This starts every service in one terminal — web, worker, db, redis, traefik,
and Temporal. The entrypoint runs any pending migrations automatically on each
start.

Open **<http://localhost:4000>** and sign in with the seeded user (or
register a new one if registration is enabled in your `.env`).

## 5. First workflow run

1. Create a project. Aixle Flow comes with three presets: `simple_kanban`,
   `dev_team`, `full_sdlc` — pick `dev_team` for a board with workflow
   bindings already wired up.
2. Drop a card in the **In Progress** column. The column's binding
   triggers a workflow run on a containerized agent.
3. Watch the run unfold in the right-hand pane: each step shows live
   stdout, token usage, and cost.

If the run fails, see [user-guide/agents.md](user-guide/agents.md#troubleshooting).

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

The Yarn `YN0060` / `YN0086` peer-dependency warnings and the
`websocket-client-simple` gem notice are unrelated and do not fail setup.

## Common follow-ups

- **Connect a real Git repo** → [user-guide/integrations.md](user-guide/integrations.md)
- **Customize a workflow** → [user-guide/workflows.md](user-guide/workflows.md)
- **Bring your own agent runtime** → [user-guide/agents.md](user-guide/agents.md)
- **Configure environment variables** → [reference/configuration.md](reference/configuration.md)
