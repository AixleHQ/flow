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
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
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
| GitLab integration               | a personal access token (added in-app) — set `GITLAB_ENDPOINT` only for self-managed |

See [user-guide/integrations.md](user-guide/integrations.md) for the
provider setup walkthroughs.

## 3. Build and seed

```bash
make setup
```

This single command:

- Builds the web, worker, and Temporal images.
- Installs Ruby gems (Bundler) and JS packages (Yarn) inside the web
  container.
- Creates the database, runs migrations, and seeds defaults.
- Builds the five agent runtime images
  (`aixle/agent-base-core`, `aixle/claude-code`, `aixle/cursor-cli`,
  `aixle/codex`, `aixle/gemini-cli`, `aixle/grok`).

## 4. Run

Two terminals required — `make worker` needs to stay attached to a TTY:

```bash
# terminal 1 — web, db, redis, traefik, temporal
make up

# terminal 2 — Temporal worker
make worker
```

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

## Common follow-ups

- **Connect a real Git repo** → [user-guide/integrations.md](user-guide/integrations.md)
- **Customize a workflow** → [user-guide/workflows.md](user-guide/workflows.md)
- **Bring your own agent runtime** → [user-guide/agents.md](user-guide/agents.md)
- **Configure environment variables** → [reference/configuration.md](reference/configuration.md)
