# Runners

A **runner** is where a session's agent container runs. By default sessions run
on the platform's own hosting; a runner sends them to a machine you control
instead. A runner belongs to the company (every project can use it) or to one
project, and lives on the company's **Settings → Runners** page or the
project's **Runners** page. A company admin manages company runners; a company
admin or the project's owner manages the project's own.

Runners are behind the `external_runners` feature flag: without it the pages
do not exist for your company.

This page covers adding machines to a `manual` runner. The rest of the manual
runner's guide (machines table, health, reuse policy) is not written yet.

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

### Machines on arm64

The agent images (`ghcr.io/aixlehq/flow-<image>`) are built for `linux/amd64`
only, so on an arm64 machine (Apple Silicon, or an ARM Linux server, with the
binary or with Docker) the runner starts them under amd64 emulation. OrbStack
and Docker Desktop have it built in; on ARM Linux install it with binfmt (the
`tonistiigi/binfmt` image installs it). Without it, the session fails to start
with the Docker daemon's own message. Sessions are slower under emulation until
the images are built for arm64.

### If something goes wrong

- A token that was already used, or that is more than an hour old, is refused
  at `configure`. Press **Add machine** again.
- A revoked runner offers no **Add machine**, and the platform refuses to
  create a token for it (`runner_revoked`). Revoking a runner revokes every
  token and credential it has issued.
- On a self-hosted installation the machine must reach the runner gateway
  (`/runner/v1`) on the platform's host. If the gateway is served on a private
  address, the machine has to be inside that network or on its VPN.

## Using your own agent image

A runner starts every session in the stock image of the session's agent. To use
your own image (built `FROM` the Aixle base image), set **Image override** in
the runner's settings.

The override is one image for every session on the runner. A runner that serves
several agents puts `{agent}` in it, which is replaced when the session starts
with the image name of the session's agent (`claude-code`, `cursor-cli`,
`codex`, …). For example `ghcr.io/aixlehq/flow-{agent}:develop` starts a Claude
Code session in `ghcr.io/aixlehq/flow-claude-code:develop`. `{agent}` is the
only placeholder. The runner isn't saved if the override has another one, or
isn't an image reference once `{agent}` is replaced.
