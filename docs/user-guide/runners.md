# Runners

A **runner** is where a session's agent container runs. By default sessions run
on the platform's own hosting; a runner sends them to a machine you control
instead. A runner belongs to the company (every project can use it) or to one
project, and lives on the company's **Settings → Runners** page or the
project's **Runners** page. A company admin manages company runners; a company
admin or the project's owner manages the project's own.

Runners are behind the `external_runners` feature flag: without it the pages
do not exist for your company.

This page covers adding machines to a `manual` runner and reading the
machines list on its page, the reuse policy and Return to service. The rest of
the manual runner's guide (health) is not written yet.

---

## Adding a machine

A `manual` runner is a pool of machines that you register yourself, the way
GitHub self-hosted runners are registered. Each machine runs the `aixle-runner`
program and needs one **registration token**.

Open the runner's page and press **Add machine**. The button is shown to
whoever may manage that runner, and only while the runner is not revoked.

The platform creates a registration token and shows it in a copy-paste
sequence. The token is:

- **single use**: it registers one machine, and a machine that has registered
  does not need it again;
- **short-lived**: it expires an hour after it is created, used or not;
- **shown once**: the platform keeps only a digest of it. Close the window and
  it is gone; press **Add machine** again for a new token.

### The sequence

Choose a machine name and a platform (`linux-amd64` or `linux-arm64`), and
copy the sequence. Run it on a Linux machine with systemd and Docker, as a user
who can use `sudo`, with `curl` and `sha256sum` installed, that can reach the
platform. (Hosts without systemd are not covered by this sequence.) It does
three things:

1. **Downloads the binary and verifies it.** The binary is downloaded from the
   platform's own host (`/runner/v1/releases/<version>/<os>-<arch>`), at the
   version the platform recommends. The `sha256sum -c` line checks it against
   the SHA-256 the platform pins for that version and platform; if it fails,
   do not run the binary.
2. **Registers the machine.** `aixle-runner configure --url … --token … --name …`
   uses up the token and stores the machine's credentials on the machine, in
   `/var/lib/aixle-runner/credentials`.
3. **Runs it as a service.** `service install` and `service start` (both run as
   `./aixle-runner` from the directory you downloaded it to: `service install`
   puts no `aixle-runner` on the `PATH`) set up a
   systemd service that survives logout and reboot.

By default an idle machine updates itself to the version the platform
recommends. To turn that off, tick **Turn off self-update**, which adds
`--no-auto-update` to `configure`.

### Running the runner in Docker

Choose **Docker** instead of a platform when the machine has no systemd, when
you want no service user, or on macOS. The machine needs Docker and has to
reach the platform; it needs no `curl` or `sha256sum`. The sequence:

1. **Picks the runner's directory.** `/var/lib/aixle-runner` on Linux; on macOS
   `~/aixle-runner`, which Docker shares with its VM. The runner keeps its
   binary and credentials there, and the directory is mounted at the same path
   in the container: Docker starts the session's containers from files on the
   machine, not in the runner's container.
2. **Registers the machine.** A throwaway container of
   `ghcr.io/aixlehq/aixle-runner:<version>`, the version the platform
   recommends, runs `configure --url … --token … --name …` with the Docker
   socket and the `aixle-runner-docker-root` volume, because `configure` checks
   Docker and the disk before it registers. It uses up the token.
3. **Runs it.** A container with `--restart unless-stopped` and the Docker
   socket, so it starts again with Docker.

The container runs as root (`--user 0:0`): reaching the Docker socket already
gives root on the machine. A runner in Docker does not update itself: to update
it, remove the container and run the image of the new version with the same
directory.

The runner reads registry credentials from `~/.docker/config.json` of the user
it runs as, which in the container is the container's root, not yours. For agent
images in a private registry, add
`-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"` to the step 3
command. A file with a credential helper (`credsStore`) does not work in the
container: use a file with the credentials in it.

To remove the machine, stop and remove the container, run the same image with
`unregister` (it removes the machine on the platform), then delete the
directory and the `aixle-runner-docker-root` volume. The dialog lists the
commands after the sequence, commented out.

macOS works through Docker: OrbStack is checked, Docker Desktop as far as
checked. Rootless Docker and Podman (another socket path) and Windows are not
covered.

## The machines list

The page of a `manual` runner, in company settings and in the project alike,
has a **Machines** section: a read-only list with one row per machine. A
machine appears as soon as it has run `configure`. Each row shows:

- the machine's **name** (the `--name` it was configured with, the hostname by
  default) and its **key**;
- its **state**:
  - **Online**: the machine is connected and running a session;
  - **Idle**: the machine is connected and has no session;
  - **Offline**: the platform has not heard from the machine for 90 seconds, or
    never has. Stop `aixle-runner` on a machine, or lose its network, and it
    turns offline within about two minutes;
  - **Resetting**: a reset started by Return to service is running, and the
    machine takes no session;
  - **Failed**: the machine is out of rotation after a failed reset or three
    failed sessions in a row, with the reason shown and a **Return to service**
    button (see below);
  - **Gone**: the machine was unregistered;
- the runner **version** and the **OS / arch** it reported at `configure`
  (updated every time the runner starts);
- when it was **registered**;
- its **last seen**: the last time the platform heard from it. The runner's own
  "Last seen" in the overview is the latest of its machines'.

The list refreshes itself every 15 seconds while the page is open.

An **offline machine is given no new session**. While another machine of the
runner is free, a session goes there. If every machine of the runner is
offline, the session is refused at launch with a message naming the runner and
saying its machines are offline: start `aixle-runner` on one of them (a machine
returns to **Idle** on its next poll, within seconds), or pick another runner.
A machine that is busy running a long step is not treated as offline while that
step is within its time limit, even when it is silent.

### Machines on arm64

The agent images (`ghcr.io/aixlehq/flow-<image>`) are built for `linux/amd64`
and `linux/arm64`, so on an arm64 machine (Apple Silicon, or an ARM Linux
server, with the binary or with Docker) the runner pulls the arm64 image and the
agent runs natively. This needs `aixle-runner` 0.4.0 or later: 0.3.0 and
earlier always pull `linux/amd64`, so every agent runs under emulation. An image published before arm64 builds existed, or a runtime
whose CLI has no arm64 build, has `linux/amd64` only: the runner then pulls that
and the agent starts under amd64 emulation, which is slower. OrbStack and Docker
Desktop have emulation built in; on ARM Linux install it with binfmt (the
`tonistiigi/binfmt` image installs it). Without it, a session that needs it fails
to start with the Docker daemon's own message.

### If something goes wrong

- A token that was already used, or that is more than an hour old, is refused
  at `configure`. Press **Add machine** again.
- A revoked runner offers no **Add machine**, and the platform refuses to
  create a token for it (`runner_revoked`). Revoking a runner revokes every
  token and credential it has issued.
- On a self-hosted installation the machine must reach the runner gateway
  (`/runner/v1`) on the platform's host. If the gateway is served on a private
  address, the machine has to be inside that network or on its VPN.

## Reuse policy, scrub and Return to service

A `manual` runner's **reuse policy** decides what happens on a machine after
every session. There are two values:

| Policy | After every session | Stays on the machine |
| --- | --- | --- |
| **Reuse** (default) | A **scrub** | Repository checkouts, package caches and pulled images |
| **Reset** | A **reset** | Pulled images, and the machine itself |

A scrub removes the session's container, which takes the agent's home, its
credential files, the MCP config, the prompt and context files, `/tmp`, the
proxy CA and logs, and every process of the session. It also empties
`/workspace/outputs`. A check confirms that no container of the session is left.
The next session on the machine fetches the repository checkouts a scrub kept
instead of cloning them again.

A reset does what a scrub does and also removes the workspace volume and the
cache volumes, so the next session clones its repositories again. It does not
give you a new machine: it removes what Aixle put on the machine and nothing
else.

Two things apply whatever the policy:

- **A session that fails is followed by a reset**, even under Reuse, and so is a
  scrub that fails.
- **A machine is taken out of rotation** (state **Failed**, with the reason) when
  its reset fails, or when 3 sessions in a row fail on it.

**Who sees what a scrub keeps.** A company runner's machines are shared by every
project of the company. On a company runner with Reuse, the next session on a
machine may belong to another project, and it sees what the scrub kept: the
repository checkouts and the caches. Choose Reset, or use a project runner, to
keep projects apart. On a project runner, what is kept stays within that project.

**Writable host mounts are outside every policy.** A writable home mount, an
extra mount with `:rw` and a host-path cache mount let the agent write to the
machine outside Aixle's volumes. A scrub or a reset removes what Aixle wrote
there, not what the agent wrote.

### Return to service

A **Failed** machine takes no session and shows why, for example *build-01
failed to reset after session 12: reset_failed: …. Fix the machine and press
Return to service.* Fix what the reason names (start Docker, free a volume that
is in use), then press **Return to service** in the machine's row. The machine
shows **Resetting** and takes no session meanwhile. When the reset succeeds the
machine is **Idle** again. When it fails, the machine stays **Failed** with the
new reason. Pressing the button is available to whoever can edit or revoke the
runner: a company admin on a company runner, and a project admin or owner on a
project runner.

While every machine of a runner is Failed, a launch on it is refused with a
message that points to Return to service.

## Using your own agent image

A runner starts every session in the default image of the session's agent (see
below). To use
your own image (built `FROM` the Aixle base image), set **Image override** in
the runner's settings.

The override is one image for every session on the runner. A runner that serves
several agents puts `{agent}` in it, which is replaced when the session starts
with the image name of the session's agent (`claude-code`, `cursor-cli`,
`codex`, …). For example `ghcr.io/aixlehq/flow-{agent}:develop` starts a Claude
Code session in `ghcr.io/aixlehq/flow-claude-code:develop`. `{agent}` is the
only placeholder. The runner isn't saved if the override has another one, or
isn't an image reference once `{agent}` is replaced. As in Docker, the first
part of the path is a registry only when it has a `.` or a port, or is
`localhost`; any other part must be lowercase, so `UPPER/flow-{agent}` is refused.

---

## Which agent image a machine pulls

A session on a runner runs the platform's agent image for the session's agent
runtime, and the machine pulls it. By default that is the public image,
`ghcr.io/aixlehq/flow-<image>` (for example `ghcr.io/aixlehq/flow-claude-code`),
so the machine needs no registry login. The tag is `latest`, unless the
deployment sets `RUNNER_AGENT_IMAGE_TAG`. Hosted sessions are not affected: they
keep their own images.

To run another image on a runner's machines, set **`container.image_override`**
in the runner's settings. It wins over the default and must be built `FROM` the
platform's agent image. If that image is in a private registry, run
`docker login` for that registry on each machine as the user that runs
`aixle-runner`: the platform sends no registry credentials to a machine.

A self-hosted deployment changes the default for all its runners with
`RUNNER_AGENT_IMAGE_PREFIX`, `RUNNER_AGENT_IMAGE_TAG` (default `latest`) and the
per-runtime `RUNNER_AGENT_IMAGE_<RUNTIME>` variables (see the configuration
reference).
`latest` moves with every stable release, so pin `RUNNER_AGENT_IMAGE_TAG` to the
release the deployment runs in production.
