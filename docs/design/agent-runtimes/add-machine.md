# "Add machine": a short instruction

Status: proposed (task #286), revised after review (decision of 2026-11-25). Extends `DESIGN.md` §6.3 (registration), §14.4 (distribution) and the
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
| Nothing kept by default, a volume instead of a host directory | **Yes, with a runner change** (§3.2) | The image declares `VOLUME /var/lib/aixle-runner`, so Docker makes an anonymous volume and removes it with the container (`--rm`). The sidecar mounts subpaths of that volume through the official API. Without the host directory the macOS/Linux difference and `sudo mkdir` go away. A named volume and a host directory are checkboxes. |
| No `aixle-runner-docker-root` volume | **Yes, with a runner change** (§3.3) | The disk check becomes information only: the runner reports the free space where it can measure and warns below 20 GiB. Nothing relies on it, so the volume has no job. |

Alternatives rejected:

- **Everything in one script, Docker included** (`curl … | sh` installing and running the container). It
  hides the `docker run` the operator is trusting, and it needs `curl` on a machine that today needs only Docker.
- **Keeping two commands and only trimming flags.** It keeps the token's two-step flow and the five-flag
  `configure` just for the preflight.
- **Baking the registration into the image tag or a file in the image.** The token is secret and per machine.

### 2.1 The commands

Docker tab (default). No `sudo`, no `RUNNER_DIR`, no platform or host choice, and no `-v` for the runner's state:

```sh
docker run --rm --name aixle-runner --user 0:0 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e AIXLE_RUNNER_URL='<gateway url>' -e AIXLE_RUNNER_TOKEN='<token>' -e AIXLE_RUNNER_NAME='<name>' \
  'ghcr.io/aixlehq/aixle-runner:<version>'
```

By default **nothing is kept**. The image declares `VOLUME /var/lib/aixle-runner`; Docker creates an anonymous
volume for it and removes it with the container (`--rm`). The command runs in the foreground, and stopping it
(Ctrl+C, `docker stop`) stops the runner, which **unregisters itself** (§3.1) and leaves nothing behind. If the
runner is killed hard (`docker kill`, a power loss), it cannot unregister, and the machine shows as not
answering, as a killed runner does today.

The image tag is the dialog's `registration.version`, as today. On a Linux machine whose user is not in
the `docker` group the command needs `sudo` in front; the dialog says so in one line under the command
instead of adding a Linux choice (§6, decision 3). A second line says the Docker runner needs **Docker Engine
26.0 or later** (§3.2) and points to the Linux service tab for an older one.

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
| Docker | Keep the registration in a volume | `-v aixle-runner:/var/lib/aixle-runner`, and `-d --restart unless-stopped` (replacing `--rm`) |
| Docker | Keep it in a directory on this machine | `-v <path>:/var/lib/aixle-runner`, at any path the operator enters, and `-d --restart unless-stopped` (replacing `--rm`) |
| Linux service | Turn off self-update | `--no-auto-update` |

The two "keep" boxes are alternatives: ticking one clears the other. The directory path is a field that shows
when its box is ticked, is quoted with `shellQuote`, and must be absolute. It can be any path: the same-path
rule of today (the directory has the same path on the machine and in the container) **goes**, because the
sidecar's binds are derived from the mount's `Source` (§3.2). Kept state means the registration survives a
restart, so the token is not needed again (§3.1).

Tick state resets when the dialog opens, as `noAutoUpdate` does today.

### 2.3 What leaves the block

- **Removal.** A collapsed **Remove this machine** section in the dialog, and the user guide. For Docker:
  stop the command (the default unregisters itself), or, with a kept registration, Revoke or Delete on the
  runner page (the platform side) and then `docker rm -f aixle-runner` (and `docker volume rm aixle-runner` for the named volume).
  The `unregister` form (`docker run --rm --volumes-from aixle-runner … unregister` after `docker stop`) is
  listed as the optional, machine-side removal for a kept registration. For the service: `sudo aixle-runner unregister` and `service uninstall` as the guide says today.
- **The private registry hint** becomes its checkbox.
- **The step-by-step binary sequence** (download, `sha256sum -c`, `configure`, `service install/start`)
  stays as a collapsed **Install step by step** section on the Linux service tab. Some operators do not pipe
  a script into a root shell, and the section is today's tested `installScript`, with its `linux-amd64` |
  `linux-arm64` choice moved inside it. It costs no new code beyond the move.

## 3. Changes

### 3.1 Runner: register on first start, unregister on stop (Docker)

`runner/cmd/aixle-runner/main.go` and `runner/internal/cli/host.go`:

- `--mode host` with **no credentials in the state directory** (today `credentials.ErrNotConfigured`, which
  `lockForHost` turns into `operatorError`) and with `AIXLE_RUNNER_URL`, `AIXLE_RUNNER_TOKEN` set runs the
  same code as `configure` first (with `AIXLE_RUNNER_NAME`, default the hostname, and
  `cli.SelfUpdateOff(AIXLE_RUNNER_NO_SELF_UPDATE)` as `configure` reads it today), then continues as the host runner.
- **With credentials present the three variables are ignored.** A restart of the container or the
  machine never needs the token, and `docker start` of a registered container leaves the token spent. This
  is a test (§5), because it is the first guarantee of the task.
- **No kept state means unregister on stop.** The runner decides "kept" from its own mount (the inspect of
  §3.2): a bind or a **named** volume is kept; an **anonymous** volume (Docker labels it
  `com.docker.volume.anonymous`) is not. When it is not kept and the runner receives SIGTERM or SIGINT, it runs
  the same code as `unregister` (the platform marks the machine removed) before it exits. A failed
  unregister is logged and does not block the exit. On SIGKILL or a power loss nothing runs, and the machine
  shows as not answering until it is Revoked or Deleted on the runner page, as a killed runner does today.
  A kept registration never unregisters on a signal: a `docker stop` then `docker start` is a restart.
- The preflight failure message of `configure` is what the operator sees in the command's output (or
  `docker logs aixle-runner`). A refused or expired token exits non-zero without writing credentials; with
  `--rm` the container is gone, and with `--restart unless-stopped` Docker retries with its own back-off and the
  same refusal each time. The dialog's text under the command says to use a new command (a new token) if the
  output says the token is refused.
- No token in a log line, as `configure` already does.

Image, `docker/runner/Dockerfile` (entrypoint):

- `VOLUME /var/lib/aixle-runner` is declared, so a run without `-v` gets an anonymous volume. Host-in-Docker mode
  (the `$dir/bin` copy, `state` directory, `--state-dir`) switches on when `AIXLE_RUNNER_DIR` is set (today)
  **or** `/var/lib/aixle-runner` is a mount point (`/proc/self/mountinfo`), with the directory defaulting to that
  path. The Kubernetes controller never mounts there, so its entrypoint stays the binary, as the Dockerfile
  comment promises. The declared volume gives the controller's pods an unused empty volume, which Kubernetes removes with the pod; the implementer confirms it changes nothing there.
- `USER 10001` stays: the controller runs the same image and must not be root by default. That is why
  `--user 0:0` stays in the command.

### 3.2 Runner: the sidecar's mounts through official Docker APIs only

Today the sidecar's bind sources (the runner's own binary, the session's relay socket directory and dial
directory) are host paths (`runner/internal/docker/proxy.go`, mounts at lines ~174–179), valid because the
runner's directory has the same path on the machine and in its container. That rule goes.

The change: at start the runner inspects **its own container** (`os.Hostname()` is the container id unless
`--hostname` is set) and finds the mount whose destination is its state directory. There is no fallback to
the old behaviour: if the inspect fails the runner stops at start with the reason.

1. **A volume, anonymous or named** (`Type: volume`): the sidecar gets **volume mounts with a `Subpath`**
   (`mount.VolumeOptions.Subpath`, Docker API 1.45, Engine 26.0) of that volume, by its name: `bin` (a
   directory, since a subpath is a directory), `state/proxy/<session>` for the session's socket directory and the
   session's dial directory. `SidecarBinary` becomes a path inside the mounted `bin` directory,
   `/aixle-bin/aixle-runner`.
2. **A bind** (the directory checkbox): binds of the same subdirectories under the mount's `Source`
   (`<Source>/bin`, `<Source>/state/proxy/<session>`, …), at any path. The path inside the container and on the
   machine need not be the same.
3. **Never a path under Docker's data root.** The runner does not bind a volume's `Mountpoint`
   (for example `<data root>/volumes/<name>/_data`): that path is the daemon's internal layout and does not exist
   for a daemon on another host or inside a VM (Docker Desktop, OrbStack).
4. **The sidecar sees only its own session's directories**, never the credentials, as with the bind today.
5. **No ports, tokens, TLS or Docker attach** between the runner and the sidecar: the relay stays a Unix
   socket in a mounted directory, as today.
6. `checkBind` (`runner/internal/docker/container.go`) refuses an agent's bind that would show the state
   directory. In volume mode the state directory has no host path an agent could name, and an agent's bind of a
   volume's `Mountpoint` is refused as a path under the data root (§3.2 point 3 applies to agent binds too);
   in bind mode the check compares against the mount's `Source`.

**Docker Engine 26.0 or later (API 1.45) for the runner in Docker**, in every variant of the Docker tab. On an
older daemon the runner **stops at start** with a clear message: the version it found, the minimum, and a pointer
to the Linux service tab. There is no fallback mode. The requirement is written in the user guide, in the Add
machine dialog (a line under the Docker command), in `DESIGN.md` §14.4 and in the runner's preflight (§3.3).
The Linux service tab keeps today's minimum.

Open for the implementer to confirm with `realdocker_test.go` on a real daemon, **before** the rest is
built, because the whole Docker half rests on it: a `Subpath` of a directory under an anonymous and a named
volume mounts into a container created by the API on a daemon of Docker 26+ and on Docker Desktop/OrbStack,
and a bind of a subdirectory of a bind source does too. If it does not, the design returns to the owner; there is
no silent fallback.

### 3.3 Runner: the disk check is for information only

`runner/internal/preflight/preflight.go` today measures `info.DockerRootDir` through `FreeBytes` and can refuse
the start. In a container that path does not exist, which is why the `aixle-runner-docker-root` volume exists.
The change:

- The runner measures free space **where it can**: its own state directory, which in a volume is on the
  daemon's filesystem, and in a bind is on the machine's. It reports the figure **with the path measured**.
- Below **20 GiB** it logs a warning. It **never refuses** to start, and a failed measure is logged, not an error.
- The `aixle-runner-docker-root` volume goes from the command. A machine registered with the old two-command
  sequence still has it and keeps working: the measure is only a log.
- **Nothing relies on the figure.** It is not sent as a gate, not a platform decision and not a scheduling input;
  the design and the user guide say it is informational.
- The preflight also checks the **Docker Engine version** (26.0 or later) when running in Docker, and stops with the
  message of §3.2.

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
  tabs, the checkboxes, the Docker Engine 26.0 requirement, the update of a Docker runner (`docker rm -f aixle-runner`, then the new
  command with the named volume checkbox ticked and without the three `-e` flags, since the volume holds the
  registration) and removal.
- `DESIGN.md` §6.3 (a "row 12c" paragraph), §14.4 ("`manual` in Docker": nothing kept by default, self-registration
  on first start, unregister on stop, the Docker Engine 26.0 minimum, the informational disk figure), §15 row 12c, `docs/index.md` entry.
- `docs/operations/releasing.md` only if its runner-release steps change; they do not.

## 4. Order

1. **Runner PR** (§3.1–3.3, the image entrypoint and `VOLUME`): Go changes and tests, then Alex tags `runner-v0.6.0`
   (a minor: new behaviour, no break). The mounts spike of §3.2 first.
2. **One platform PR** with the pin (`0.6.0` and its two digests in `config/settings.yml`, and
   `recommended_version: "0.6.0"`, as #277 did for `0.5.0`), the dialog, the install script and the docs
   (§3.4–3.6). The runner release comes first; this PR is opened after it. The rule that the platform PR must not
   merge before the pin is deployed goes: the pin is in the same PR, so the Docker command and the image it names
   arrive together. Machines already registered keep working: their binary updates itself when idle, and a Docker
   machine keeps its tag.

## 5. Testing

- **Go** (`runner/…`, as the `Runner (Go)` job runs them):
  - `cli`: host mode with no credentials and the three variables registers once and runs; with credentials
    and the variables it registers nothing (a fake gateway fails the test on a `register` call); a refused
    token writes no credentials and exits non-zero; no token in any output.
  - `cli`: SIGTERM and SIGINT with an anonymous volume unregister; with a named volume or a bind they do not.
  - `preflight`: the figure is reported with the path measured; below 20 GiB a warning and no refusal; a failed
    measure is not an error; Docker below 26.0 stops the start with the version found, the minimum and the pointer.
  - `docker`: sidecar mounts for a volume state, anonymous and named (subpath mounts, `/aixle-bin/aixle-runner`) and for a bind
    state (binds under the `Source`, any path); no mount under a volume's `Mountpoint`; the API below 1.45 stops the start; `checkBind`.
  - `realdocker_test.go`: the subpath mount works on a real daemon (§3.2).
  - Entrypoint: a shell test of the host-in-Docker switch (env set, mount point, neither).
- **Rails**: a controller test for `machine-install.sh` (public, `no-store`, the rendered version and both
  digests equal the pins, `404` with no recommended version, no value outside the pins in the body); a
  `shellcheck` run on the rendered output in CI if the repository's CI has it, otherwise `sh -n`, plus a
  test that runs the script under a fake `PATH` (stub `uname`, `curl`, `sha256sum`, `systemctl`, `aixle-runner`) for each architecture,
  a digest mismatch (nothing runs) and an unknown architecture.
- **Frontend**: `machineInstructions.test.ts` covers the default of each tab and every combination that changes
  a command (private registry, named volume, directory, each with the registry box, no-auto-update; the two keep boxes exclude each other), the quoting of a name with a quote, and
  that the Docker default has no `sudo`, `RUNNER_DIR`, `docker-root`, `configure`, `-d` or `-v` for the runner's state. `AddMachine.test.tsx`: it
  opens on Docker, switching tabs, each checkbox and the collapsed sections, and that the state resets on reopen.
- **QA on staging** as the task lists: the Docker default on a Coder workspace with Docker registers, shows
  Online and runs a session (this exercises the sidecar through the volume subpath); stopping the default command unregisters the machine; the private-registry box
  gives the default plus that mount; the volume box gives `-v aixle-runner:…`, `-d --restart unless-stopped`
  and survives a container restart without the token; the Linux service command on a Linux machine; and a machine registered with
  the **old** two-command sequence and image tag `0.5.0` still runs after the pin moves to `0.6.0`.

## 6. Decisions, assumptions and risks

Decisions (all from the task unless stated):

1. **Nothing kept by default, and volume subpaths for the sidecar.** Source: the decision of 2026-11-25. The
   default is `docker run --rm` over an anonymous volume the image declares; the runner unregisters itself on a
   clean stop. The sidecar's mounts use official APIs only (volume `Subpath`, or binds under a bind mount's
   `Source`), never a path under Docker's data root. There is no fallback mode: Docker before 26.0 stops with a
   message (§3.2). The previous idea of the directory as the way back for old daemons is dropped.
2. **`machine-install.sh`, rendered by the platform, with digests in the script.** Source: the task's guarantee
   that the script checks the digest of the architecture it picks.
3. **No Docker host choice and no `sudo` in the Docker command.** With no host directory the macOS/Linux difference is
   only `sudo` for a user outside the `docker` group, which a helper line covers. Alternative: a Linux/macOS
   second level, rejected because the task asks for one command where possible.
4. **Name: Linux service.** Source: the task allows picking the clearest name.
5. **No version guard in the platform.** The pin and the dialog ship in one PR after the runner release (§4), so the
   command and the image it names arrive together; a guard would add a second code path for a state that does not occur.
6. **`binaries` stays in the registration answer** for the step-by-step section.

Risks and edge cases:

- **The token sits in the container's environment** (`docker inspect`, readable by whoever can use Docker, who
  is root on the machine anyway). It is single-use, expires in an hour and is ignored once the state holds credentials.
- **A crash between the register answer and writing the credentials** loses the token: the machine needs another
  one. This is the same window `configure` has now.
- **A subpath of a volume mounts what is there at the time**: the entrypoint creates `bin` and `state` before
  the runner starts, and the runner creates the session directory before the sidecar (as it does for binds).
- **One session at a time.** The sidecars of two sessions on a machine would share the daemon's default network;
  today a machine runs one session, so this does not occur.
- **Removing a kept volume or directory deletes the credentials**: the machine must be revoked and added again. The guide says so.
- **A hard kill leaves a registered machine** that no longer answers (§3.1); Revoke or Delete on the runner page removes it.
- **The disk figure can be wrong** (a volume on a remote daemon, a full data root elsewhere). It is informational
  only, so a wrong figure costs a misleading log line, never a refused start.
- **`curl | sh`**: public script, no secret in it, TLS as the trust root as for the digests today; the section
  **Install step by step** is the alternative.
- **Two commands on a machine**: only one host runner per machine, the lock refuses the second, as today.
- **Rootless Docker, Podman, Windows**: not covered, as before.

## 7. Deferred

- **A network per session**, for when a machine runs more than one session at a time (today it runs one).
- A live "waiting for the machine" state in the dialog (it would use the runner's machines list).
- Removing `binaries` from the registration answer once the step-by-step section goes.
- A Windows or rootless Docker instruction.
- Self-update for the Docker runner (the tag is the version, `DESIGN.md` §14.4).
