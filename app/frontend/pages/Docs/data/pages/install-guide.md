# Installation guide

Aixle Flow runs entirely in Docker — no Ruby or Node required on the
host. This page covers system requirements and the one-command setup.
For the first-run walkthrough, see the Quick start page.

## System requirements

- **Docker** and **Docker Compose** (Desktop on macOS/Windows, or
  Docker Engine on Linux).
- **8 GB of RAM** allocated to Docker is enough for a single developer.
  More is better if you plan to run multiple parallel agent sessions.
- **git**.
- A working internet connection for pulling images on first run.

Ruby, Node, and all other language runtimes are **not** required on the
host — everything runs in containers.

## Disk space

First-run image build pulls approximately 3–5 GB of base images plus
the four agent runtime images. Allow 10–15 GB of free disk for a
comfortable install.

## Getting the code

```bash
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
```

## One-command setup

```bash
cp .env.example .env.development
make setup
```

`make setup` builds all images, installs dependencies inside the
containers, creates the database, runs migrations, seeds defaults, and
builds the four agent runtime images in parallel.

> **info** **First run is slow.** Most of the time is Docker pulling base images and building agent containers. Subsequent starts are seconds.

## Start the app

```bash
make up      # web, db, redis, traefik, temporal (terminal 1)
make worker  # Temporal worker — must stay attached (terminal 2)
```

Open **http://localhost:4000**.

## Updating

```bash
git pull
make deps      # reinstall gems and JS packages if Gemfile/package.json changed
make db-prepare  # run any new migrations
make up
```

If new agent images were added, also run `make build-agents`.
