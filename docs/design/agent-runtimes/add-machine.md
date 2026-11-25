# "Add machine": a short instruction

Status: proposed (task #286). Extends `DESIGN.md` §6.3 (registration), §14.4 (distribution) and the
rows 12a and 12b of §15. It adds no protocol change: the wire, the tokens and the pins stay as they are.

## 1. Overview

"Add machine" today shows a sequence of 3 steps (binary) or 2 `docker run` commands with five flags each
(Docker), and it asks the operator to pick among `linux-amd64`, `linux-arm64` and Docker and, for Docker,
Linux or macOS. The goal: **one command per tab, the same for every machine of that tab, with the options
behind checkboxes.**

The sequence is built in `app/frontend/shared/resources/runners/machineInstructions.ts` and shown by
`AddMachine.tsx`. The user guide (`docs/user-guide/runners.md`) and §6.3 describe it.

## 2. Approach

Four ways were offered in the task. The choice per way, by the guarantees that must not change
(single-use token, SHA-256 check before running, `shellQuote` on every platform value, an image that does
not update itself):

| Way | Decision | Why |
| --- | --- | --- |
| A script the platform serves | **Yes, for the binary tab only** | It finds the architecture and checks the digest for the one it picks. For Docker a script adds nothing: the image is multi-arch and Docker verifies it. |
| Defaults in the runner and the image | **Yes, for Docker** | The container registers itself on its first start from three environment variables, so `configure` and `run` become one `docker run`. |
| A named volume instead of a host directory | **Yes, with a runner change** (§3.2) | The sidecar can mount a volume by name, with a subpath. Without the host directory the macOS/Linux difference and `sudo mkdir` go away. The host directory stays as an option. |
| No `aixle-runner-docker-root` volume | **Yes, with a runner change** (§3.3) | The disk check measures the state volume's filesystem when `DockerRootDir` is not visible. A named volume lives under the daemon's data root, so it is the same filesystem. |

Alternatives rejected:

- **Everything in one script, Docker included** (`curl … | sh` installing and running the container). It
  hides the `docker run` the operator is trusting, and it needs `curl` on a machine that today needs only Docker.
- **Keeping two commands and only trimming flags.** It keeps the token's two-step flow and the five-flag
  `configure` just for the preflight.
- **Baking the registration into the image tag or a file in the image.** The token is secret and per machine.

### 2.1 The commands

Docker tab (default). No `sudo`, no `RUNNER_DIR`, no platform or host choice:

```sh
docker run -d --name aixle-runner --restart unless-stopped --user 0:0 \
  -v aixle-runner:/var/lib/aixle-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e AIXLE_RUNNER_URL='<gateway url>' -e AIXLE_RUNNER_TOKEN='<token>' -e AIXLE_RUNNER_NAME='<name>' \
  'ghcr.io/aixlehq/aixle-runner:<version>'
```

The image tag is the dialog's `registration.version`, as today. On a Linux machine whose user is not in
the `docker` group the command needs `sudo` in front; the dialog says so in one line under the command
instead of adding a Linux choice (§6, decision 3).

Linux service tab (the working name "Binary" becomes **Linux service**: it says what the tab gives,
a systemd service, and not how it is built):

```sh
curl -fsSL '<gateway url>/runner/v1/machine-install.sh' | sudo sh -s -- --token '<token>' --name '<name>'
```

Both are single lines in the dialog, wrapped by the `Code` block, built with `shellQuote` for every
platform value. Linux service adds `--no-auto-update` for its checkbox.

### 2.2 Checkboxes (each off by default, each adds exactly its own flags)

| Tab | Checkbox | Adds |
| --- | --- | --- |
| Docker | Images from a private registry | `-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"` |
| Docker | Keep the runner's files in a directory on this machine (Docker before 26, or if you want to look at them) | replaces the volume flag with `-v "$HOME/aixle-runner:$HOME/aixle-runner" -e AIXLE_RUNNER_DIR="$HOME/aixle-runner"` |
| Linux service | Turn off self-update | `--no-auto-update` |

The directory box is the old behaviour in one flag pair, so it is also the way back if a daemon lacks
volume subpaths (§3.2). It uses `$HOME/aixle-runner` on both macOS and Linux (the macOS path that works
today; on Linux the user's own directory needs no `sudo mkdir`).

Tick state resets when the dialog opens, as `noAutoUpdate` does today.

### 2.3 What leaves the block

- **Removal.** A collapsed **Remove this machine** section in the dialog, and the user guide. For Docker:
  Revoke or Delete on the runner page (the platform side), then `docker rm -f aixle-runner && docker volume rm aixle-runner`.
  The `unregister` form (`docker run --rm --volumes-from aixle-runner … unregister` after `docker stop`) is
  listed as the optional, machine-side removal. For the service: `sudo aixle-runner unregister` and `service uninstall` as the guide says today.
- **The private registry hint** becomes its checkbox.
- **The step-by-step binary sequence** (download, `sha256sum -c`, `configure`, `service install/start`)
  stays as a collapsed **Install step by step** section on the Linux service tab. Some operators do not pipe
  a script into a root shell, and the section is today's tested `installScript`, with its `linux-amd64` |
  `linux-arm64` choice moved inside it. It costs no new code beyond the move.

## 3. Changes

### 3.1 Runner: register on first start (Docker)

`runner/cmd/aixle-runner/main.go` and `runner/internal/cli/host.go`:

- `--mode host` with **no credentials in the state directory** (today `credentials.ErrNotConfigured`, which
  `lockForHost` turns into `operatorError`) and with `AIXLE_RUNNER_URL`, `AIXLE_RUNNER_TOKEN` set runs the
  same code as `configure` first (with `AIXLE_RUNNER_NAME`, default the hostname, and
  `cli.SelfUpdateOff(AIXLE_RUNNER_NO_SELF_UPDATE)` as `configure` reads it today), then continues as the host runner.
- **With credentials present the three variables are ignored.** A restart of the container or the
  machine never needs the token, and `docker start` of a registered container leaves the token spent. This
  is a test (§5), because it is the first guarantee of the task.
- The preflight failure message of `configure` is what the operator sees in `docker logs aixle-runner`.
  A refused or expired token exits non-zero without writing credentials; `--restart unless-stopped` retries
  with Docker's own back-off and the same refusal each time. The dialog's text under the command says to
  look at `docker logs` and to use a new command (a new token) if it says the token is refused.
- No token in a log line, as `configure` already does.

Image, `docker/runner/Dockerfile` (entrypoint):

- Host-in-Docker mode (the `$dir/bin` copy, `state` directory, `--state-dir`) switches on when
  `AIXLE_RUNNER_DIR` is set (today) **or** `/var/lib/aixle-runner` is a mount point (`/proc/self/mountinfo`),
  with the directory defaulting to that path. The Kubernetes controller never mounts there, so its entrypoint
  stays the binary, as the Dockerfile comment promises.
- `USER 10001` stays: the controller runs the same image and must not be root by default. That is why
  `--user 0:0` stays in the command.

### 3.2 Runner: a volume for the state directory

Today the sidecar's bind sources (the runner's own binary, the session's relay socket directory and dial
directory) are host paths (`runner/internal/docker/proxy.go`, mounts at lines ~174–179), valid because the
runner's directory has the same path on the machine and in its container.

With a named volume the runner does not know a host path. The change:

1. At start the runner inspects **its own container** (`os.Hostname()` is the container id unless
   `--hostname` is set; on failure it falls back to today's behaviour) and finds the mount whose
   destination is its state directory.
2. If that mount is `Type: volume`, the sidecar gets **volume mounts with a `Subpath`**
   (`mount.VolumeOptions.Subpath`, Docker API 1.45, Engine 26, 2024): the volume at `bin` (a directory, since
   a subpath is a directory) and at `state/proxy/<session>` and the dial directory. `SidecarBinary` becomes a
   path inside the mounted `bin` directory, `/aixle-bin/aixle-runner`. Only the subpaths the sidecar needs are
   visible to it, never the credentials, as with the bind today.
3. If it is a bind (a directory on the machine, the existing machines and the checkbox), nothing changes.
4. If it is a volume and the daemon's API is below 1.45, the runner stops at start with: "this Docker
   cannot mount part of a volume; run the runner with a directory on this machine (the checkbox in Add
   machine)". The dialog's checkbox label carries the same condition.
5. `checkBind` (`runner/internal/docker/container.go`) refuses an agent's bind that would show the state
   directory. In volume mode it compares against the volume's `Mountpoint` from the inspect result
   (for example `<data root>/volumes/aixle-runner/_data`) so the rule keeps holding.

Open for the implementer to confirm with `realdocker_test.go` on a real daemon, **before** the rest is
built, because the whole Docker half rests on it: a `Subpath` of a directory under a named volume mounts
read-only into a container created by the API on the daemon of Docker 26+ and on Docker Desktop/OrbStack.
If it does not, the fallback is §6, question 1 and the Docker default keeps a host directory.

### 3.3 Runner: the disk check without the `docker-root` volume

`runner/internal/preflight/preflight.go` measures `info.DockerRootDir` through `FreeBytes`. In a container that
path does not exist (hence the volume today). The change: when measuring `DockerRootDir` fails with
`fs.ErrNotExist`, measure the state directory instead and report it as the measure. In volume mode the state
directory is on a volume under the daemon's data root, so the figure is the daemon's. Under a host directory
mount with the old `docker-root` volume the first measure succeeds, so existing machines are unchanged.
The error text still names the path measured. Any other error stays a failure.

### 3.4 Platform: the install script (Linux service)

- Route in `config/routes/runner_gateway.rb`: `get "machine-install.sh"`, public like `releases`
  (the operator has no credential yet), `format: false`, `Cache-Control: no-store`. A new
  `RunnerGateway::V1::MachineInstallsController` next to `ReleasesController`, reusing its
  `no-store` and no-protocol-header handling. The path is not `install.sh`: §6.2 reserves that for the
  Coder bootstrap, a different script (a user service under `~/.aixle-runner`).
- The script is a template rendered at request time from `Runners::Release.pins.recommended_version`,
  the gateway URL (`"#{Settings.protocol}://#{Settings.domain}"`, the same value `RunnerRegistrationTokens#gateway_url`
  uses; put it where both can call it) and, for each pinned platform, `Runners::Release.binary(version, platform).sha256`.
  Everything rendered is a pinned value, written with Ruby's shell escaping, and none of it is user input.
  No recommended version: `404 not_found`, as `releases#show` answers an unpinned version.
- Template at `app/views/runner_gateway/v1/machine_installs/show.sh.erb` (plain text `text/x-shellscript`),
  POSIX `sh`, `set -eu`, and it:
  1. refuses a non-Linux machine, a machine without `systemctl`, `curl` or `sha256sum`, and not being root, each with
     a one-line message saying what to install or to run `sudo`;
  2. maps `uname -m` (`x86_64` | `amd64` → `linux-amd64`, `aarch64` | `arm64` → `linux-arm64`, anything else
     refuses) and takes that platform's digest from the rendered table;
  3. downloads the binary from the platform's release URL
     (`<gateway>/runner/v1/releases/<version>/<platform>`, a redirect to the asset) into a temp directory,
     checks `sha256sum -c` and **does not run it on a mismatch**;
  4. runs `./aixle-runner configure --url … --token … --name …` (+ `--no-auto-update`) with its own arguments
     passed through, then `service install` and `service start`, and removes the temp directory (`trap`);
  5. parses `--token`, `--name`, `--no-auto-update` only, and rejects anything else; `--name` is checked against the same
     pattern as the dialog's `MACHINE_NAME_PATTERN`.
- The token travels as an argument, as in today's `configure` line. It is single-use and expires in an hour.

The script is a convenience around today's steps: the digest comes from the same platform pins and the
same host as before, only the copy by hand goes. The collapsed step-by-step section keeps the
copy-and-compare path.

### 3.5 Platform: dialog and instructions

- `machineInstructions.ts`: `dockerScript` → `dockerCommand({ registration, name, privateRegistry, hostDirectory })`;
  a new `installCommand({ registration, name, noAutoUpdate })`; `installScript` stays for the step-by-step
  section. `DockerHost`, `DOCKER_PLATFORM` as a platform value, `runnerImage` for the Docker tab, `shellQuote`
  and the name checks stay. Every platform value (URL, token, name, image) goes through `shellQuote`.
- `AddMachine.tsx`: a top-level `SegmentedControl` **Docker** | **Linux service**, Docker first and selected on
  open; the Docker host control and the per-platform control (outside the step-by-step section) go. The two
  checkbox groups above, the collapsed sections, the helper lines (`sudo` on Linux, `docker logs`, no
  self-update in Docker, the arm64 text kept short).
- `RunnerRegistration` keeps `binaries` (the step-by-step section reads it), so the controller, the resource and
  `Runners::MachineRegistration` do not change.

### 3.6 Docs

- `docs/user-guide/runners.md`: "Adding a machine" and "Running the runner in Docker" rewritten around the two
  tabs, the checkboxes, the update of a Docker runner (run the same command with the new tag and without the
  three `-e` flags) and removal.
- `DESIGN.md` §6.3 (a "row 12c" paragraph), §14.4 ("`manual` in Docker": the state volume, self-registration
  on first start, the disk measure), §15 row 12c, `docs/index.md` entry.
- `docs/operations/releasing.md` only if its runner-release steps change; they do not.

## 4. Order

1. **Runner PR** (§3.1–3.3, the image entrypoint): Go changes and tests, then Alex tags `runner-v0.6.0`
   (a minor: new behaviour, no break). The mounts spike of §3.2 first.
2. **Pin PR**: `0.6.0` and its two digests in `config/settings.yml`, and `recommended_version: "0.6.0"`, as #277 did
   for `0.5.0`. Machines already registered keep working: their binary updates itself when idle, and a Docker
   machine keeps its tag.
3. **Platform PR** (§3.4, §3.5, §3.6). It **must not merge before step 2 is deployed**: its Docker command
   relies on the recommended image registering itself, and an older image would fail on "not configured".
   `Runners::MachineRegistration` has no check of this and the design adds none (§6, decision 5); the order is
   the guard, and the PR description states it.

## 5. Testing

- **Go** (`runner/…`, as the `Runner (Go)` job runs them):
  - `cli`: host mode with no credentials and the three variables registers once and runs; with credentials
    and the variables it registers nothing (a fake gateway fails the test on a `register` call); a refused
    token writes no credentials and exits non-zero; no token in any output.
  - `preflight`: `DockerRootDir` missing, so the state directory is measured; present, so it is the one measured; another error fails.
  - `docker`: sidecar mounts for a volume state (subpath mounts, `/aixle-bin/aixle-runner`) and for a bind
    state (unchanged); the API below 1.45 with a volume stops the start; `checkBind` in volume mode.
  - `realdocker_test.go`: the subpath mount works on a real daemon (§3.2).
  - Entrypoint: a shell test of the host-in-Docker switch (env set, mount point, neither).
- **Rails**: a controller test for `machine-install.sh` (public, `no-store`, the rendered version and both
  digests equal the pins, `404` with no recommended version, no value outside the pins in the body); a
  `shellcheck` run on the rendered output in CI if the repository's CI has it, otherwise `sh -n`, plus a
  test that runs the script under a fake `PATH` (stub `uname`, `curl`, `sha256sum`, `systemctl`, `aixle-runner`) for each architecture,
  a digest mismatch (nothing runs) and an unknown architecture.
- **Frontend**: `machineInstructions.test.ts` covers the default of each tab and every combination that changes
  a command (private registry, host directory, both, no-auto-update), the quoting of a name with a quote, and
  that the Docker default has no `sudo`, `RUNNER_DIR`, `docker-root` or `configure`. `AddMachine.test.tsx`: it
  opens on Docker, switching tabs, each checkbox and the collapsed sections, and that the state resets on reopen.
- **QA on staging** as the task lists: the Docker default on a Coder workspace with Docker registers, shows
  Online and runs a session (this exercises the sidecar through the volume subpath); the private-registry box
  gives the default plus that mount; the Linux service command on a Linux machine; and a machine registered with
  the **old** two-command sequence and image tag `0.5.0` still runs after the pin moves to `0.6.0`.

## 6. Decisions, assumptions and risks

Decisions (all from the task unless stated):

1. **The volume subpath approach, and Docker 26+ for it.** Source: the task's own condition ("that has to
   keep working; otherwise the mount stays, as an option"). The directory checkbox keeps the option, and §3.2
   says what is checked first. If the spike fails, the Docker default keeps the host directory with the same
   self-registration and one `docker run`, with the macOS/Linux choice back or `$HOME/aixle-runner` for both.
2. **`machine-install.sh`, rendered by the platform, with digests in the script.** Source: the task's guarantee
   that the script checks the digest of the architecture it picks.
3. **No Docker host choice and no `sudo` in the Docker command.** With the volume the macOS/Linux difference is
   only `sudo` for a user outside the `docker` group, which a helper line covers. Alternative: a Linux/macOS
   second level, rejected because the task asks for one command where possible.
4. **Name: Linux service.** Source: the task allows picking the clearest name.
5. **No version guard in the platform.** The order in §4 is the control; a guard would add a second code path (a
   legacy two-command variant) for a state that does not occur after step 2.
6. **`binaries` stays in the registration answer** for the step-by-step section.

Risks and edge cases:

- **The token sits in the container's environment** (`docker inspect`, readable by whoever can use Docker, who
  is root on the machine anyway). It is single-use, expires in an hour and is ignored once the state holds credentials.
- **A crash between the register answer and writing the credentials** loses the token: the machine needs another
  one. This is the same window `configure` has now.
- **A subpath of a volume mounts what is there at the time**: the entrypoint creates `bin` and `state` before
  the runner starts, and the runner creates the session directory before the sidecar (as it does for binds).
- **Removing the volume deletes the credentials**: the machine must be revoked and added again. The guide says so.
- **`curl | sh`**: public script, no secret in it, TLS as the trust root as for the digests today; the section
  **Install step by step** is the alternative.
- **Two commands on a machine**: only one host runner per machine, the lock refuses the second, as today.
- **Rootless Docker, Podman, Windows**: not covered, as before.

## 7. Deferred

- A live "waiting for the machine" state in the dialog (it would use the runner's machines list).
- Removing `binaries` from the registration answer once the step-by-step section goes.
- A Windows or rootless Docker instruction.
- Self-update for the Docker runner (the tag is the version, `DESIGN.md` §14.4).
