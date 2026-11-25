# "Add machine": a short instruction

Status: proposed (task #286), revised twice after review (decisions of 2026-11-25). Extends `DESIGN.md` §6.3 (registration), §14.4 (distribution) and the
rows 12a and 12b of §15. It adds no protocol change: the wire, the tokens and the pins stay as they are.

Runners are not released yet (the flag is off on production, and there are no real users). This design therefore
handles no machine, command or runner version from before it: it describes the end state only.

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
| Nothing kept by default, a volume instead of a host directory | **Yes, with a runner change** (§3.2) | The image declares `VOLUME /var/lib/aixle-runner`, so Docker makes an anonymous volume and removes it with the container (`--rm`). The sidecar mounts subpaths of that volume through the official API. Without the host directory the macOS/Linux difference and `sudo mkdir` go away. A named volume and a directory on the machine are checkboxes. |
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
volume for it and removes it with the container (`--rm`). The image also sets `AIXLE_RUNNER_UNREGISTER_ON_STOP=1`
(§3.1), so the command runs in the foreground, and stopping it (Ctrl+C, `docker stop`) stops the runner, which
**unregisters itself** and removes its session containers (§3.1). If the runner is killed hard (`docker kill`,
a power loss), it cannot do either: the machine shows as not answering, and the guide shows how to clean up by
hand (§3.1, Cleanup).

The image tag is the dialog's `registration.version`, as today. On a Linux machine whose user is not in
the `docker` group the command needs `sudo` in front; the dialog says so in one line under the command
instead of adding a Linux choice (§6, decision 3). A second line states the Docker version rule (§3.2):
*"Needs Docker 26 or later. On older Docker, tick Keep it in a directory on this machine."*

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
| Docker | Keep the registration in a volume | `-v aixle-runner:/var/lib/aixle-runner`, `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`, and `-d --restart unless-stopped` (replacing `--rm`) |
| Docker | Keep it in a directory on this machine (also works on Docker older than 26) | `-v <path>:/var/lib/aixle-runner`, at any path the operator enters, `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`, and `-d --restart unless-stopped` (replacing `--rm`) |
| Linux service | Turn off self-update | `--no-auto-update` |

The two "keep" boxes are alternatives: ticking one clears the other (and `dockerCommand` takes one `keep` option, §3.5). The directory path is a field that shows
when its box is ticked, is quoted with `shellQuote`, and must be absolute. It can be any path: the same-path
rule of today (the directory has the same path on the machine and in the container) **goes**, because the
sidecar's binds are derived from the mount's `Source` (§3.2). Kept state means the registration survives a
restart, so the token is not needed again (§3.1). The setting that turns unregister-on-stop off is part of
each "keep" box, so a kept machine never unregisters on `docker stop`.

Tick state resets when the dialog opens, as `noAutoUpdate` does today.

### 2.3 What leaves the block

- **Removal.** A collapsed **Remove this machine** section in the dialog, and the user guide. For Docker:
  stop the command (the default unregisters itself), or, with a kept registration, Revoke or Delete on the
  runner page (the platform side) and then `docker rm -f aixle-runner` (and `docker volume rm aixle-runner` for the named volume).
  The `unregister` form (`docker run --rm --volumes-from aixle-runner … unregister` after `docker stop`) is
  listed as the optional, machine-side removal for a kept registration. For the service: `sudo aixle-runner unregister` and `service uninstall`.
  The guide also says how to turn unregister-on-stop off or on in an edited command (§3.1).
- **The private registry hint** becomes its checkbox.
- **The step-by-step binary sequence** (download, `sha256sum -c`, `configure`, `service install/start`)
  stays as a collapsed **Install step by step** section on the Linux service tab. Some operators do not pipe
  a script into a root shell, and the section is today's tested `installScript`, with its `linux-amd64` |
  `linux-arm64` choice moved inside it. It costs no new code beyond the move.

## 3. Changes

### 3.1 Runner: modes, register on first start, unregister on stop, cleanup

`runner/cmd/aixle-runner/main.go` and `runner/internal/cli/` (today `host.go`).

**`--mode` names the role, not where the runner runs.** The `host` mode is renamed **`machine`**: the modes are
`machine` (the runner of a machine), `proxy` (the callback proxy's sidecar) and the Kubernetes controller. The rename
is made everywhere: the code (`main.go`, `cli`, the `host` package, log fields), the docs (`DESIGN.md`, the user
guide, `PROTOCOL.md`), the systemd unit the `service install` command writes, and the tests.

**Register on first start:**

- `--mode machine` with **no credentials in the state directory** (today `credentials.ErrNotConfigured`, which
  `lockForHost` turns into `operatorError`) and with `AIXLE_RUNNER_URL`, `AIXLE_RUNNER_TOKEN` set runs the
  same code as `configure` first (with `AIXLE_RUNNER_NAME`, default the hostname, and
  `cli.SelfUpdateOff(AIXLE_RUNNER_NO_SELF_UPDATE)` as `configure` reads it today), then continues as the machine runner.
- **With credentials present the three variables are ignored.** A restart of the container or the
  machine never needs the token, and `docker start` of a registered container leaves the token spent. This
  is a test (§5), because it is the first guarantee of the task.
- The preflight failure message of `configure` is what the operator sees in the command's output (or
  `docker logs aixle-runner`). A refused or expired token exits non-zero without writing credentials; with
  `--rm` the container is gone, and with `--restart unless-stopped` Docker retries with its own back-off and the
  same refusal each time. The dialog's text under the command says to use a new command (a new token) if the
  output says the token is refused.
- No token in a log line, as `configure` already does.

**Unregister on stop is an explicit setting.** The flag `--unregister-on-stop` and its environment variable
`AIXLE_RUNNER_UNREGISTER_ON_STOP` (`1` or `0`; the flag wins). **Nothing is inferred** from the mount type,
from `AutoRemove` or from anything else the runner could inspect. With the setting on, SIGTERM or SIGINT runs the same
code as `unregister` (the platform marks the machine removed), after the sidecar teardown and the removal of the
session containers (Cleanup, below), before the exit. A failed unregister is logged and does not block the exit.
Unregister, teardown and exit are written to fit in `docker stop`'s default 10 s before SIGKILL: each step has its own
short deadline (the unregister call a few seconds, the teardown the rest), and the test of §5 runs them against a
slow fake gateway.

| Where | Setting | Why |
| --- | --- | --- |
| The Docker image | **on** (`ENV AIXLE_RUNNER_UNREGISTER_ON_STOP=1`) | The default command keeps nothing, so a stopped runner must not leave a registered machine that can never come back. The default command stays short. |
| The "keep" checkboxes | **off** (`-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`) | A kept registration is meant to survive `docker stop` and `docker start`. |
| The Linux service | **off** (the binary's default; the unit does not set it) | A service is meant to survive restarts. |
| An edited command | the operator's | Someone who edits the command (for example to `--restart always`) turns it off themselves. The user guide says how: add `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`. |

On SIGKILL or a power loss nothing runs, and the machine shows as not answering until it is Revoked or Deleted on
the runner page.

**Cleanup: only the runner's own containers.** The runner touches only the containers labelled with its own
machine key (`aixle.com/environment=<key>`, `runner/internal/docker/environment.go`), as it does today. It never touches an
unlabelled container or another runner's.

- **On a normal stop** it removes its session containers (the sidecar and the agent).
- **After a hard kill with kept state** (a volume or a directory) the restarted runner is the same machine, with the
  same key. It removes its leftovers at start, as it does today.
- **After a hard kill in the default mode** the next start is a **new machine with a new key**. It does not touch
  the old run's containers, because they are not its own, and it does not remove the old run's anonymous volume (the
  old sidecar may still hold it). The user guide shows how to list the leftovers by label
  (`docker ps -a --filter label=aixle.com/environment`, the label's value is the old machine's key) and remove them by
  hand with their anonymous volume (`docker rm -fv <id>`), and to Revoke or Delete the old machine on the runner page.
- There is **no cleanup of containers the runner cannot prove are its own.**

Image, `docker/runner/Dockerfile`:

- `ENTRYPOINT ["aixle-runner"]` and `CMD ["--mode", "machine", "--state-dir", "/var/lib/aixle-runner"]`,
  `VOLUME /var/lib/aixle-runner`, with `AIXLE_RUNNER_NO_SELF_UPDATE=1` as today. **The shell entrypoint and
  `AIXLE_RUNNER_DIR` are removed**: the runner does no setup in `sh`, and nothing decides a mode by looking at the
  filesystem.
- `ENV AIXLE_RUNNER_IN_CONTAINER=1` and `ENV AIXLE_RUNNER_UNREGISTER_ON_STOP=1`: the two things that differ in a
  container are set explicitly by the image (§3.2).
- **The Kubernetes controller is started with its own explicit command** in its pod spec (`command` and `args`, the
  controller's mode), so it does not use the image's `CMD`. The controller ignores `AIXLE_RUNNER_IN_CONTAINER` and
  `AIXLE_RUNNER_UNREGISTER_ON_STOP`, which only the machine mode reads. The pod's unused empty volume for the declared
  `VOLUME` is removed by Kubernetes with the pod.
- `USER 10001` stays: the controller runs the same image and must not be root by default. That is why
  `--user 0:0` stays in the command.

### 3.2 Runner: the sidecar's mounts through official Docker APIs only

Today the sidecar's bind sources (the runner's own binary, the session's relay socket directory and dial
directory) are host paths (`runner/internal/docker/proxy.go`, mounts at lines ~174–179), valid because the
runner's directory has the same path on the machine and in its container. That rule goes.

**The runner puts its own binary in the state directory, in Go.** At start, on a bare host and in a container
alike, it copies its own executable to `<state-dir>/bin/aixle-runner` (written to a temporary name and renamed,
mode 0755). The sidecar mounts that `bin` directory the same way as the session's socket directories, so
`SidecarBinary` is a path inside the mounted directory (`/aixle-bin/aixle-runner`). There is no `sh` step.

**Where the state directory lives on the machine.** On a bare host the state directory's path is already the
machine's path: the sidecar binds `<state-dir>/bin`, `<state-dir>/proxy/<session>`, … directly, and the runner
inspects nothing. In a container the image sets `AIXLE_RUNNER_IN_CONTAINER=1` (§3.1). **Only then** the runner inspects its
own container (`os.Hostname()` is the container id unless `--hostname` is set), finds the mount whose destination
is its state directory, and learns **only where that directory lives on the machine**. The inspection chooses no
behaviour. If the inspect fails, the runner stops at start with the reason.

1. **A volume, anonymous or named** (`Type: volume`): the runner takes the volume's name, and the sidecar gets
   **volume mounts with a `Subpath`** (`mount.VolumeOptions.Subpath`, Docker API 1.45, Engine 26.0) of that volume:
   `bin` (a directory, since a subpath is a directory) and the session's socket directory and dial directory.
2. **A directory** (the directory checkbox, `Type: bind`): the runner takes the mount's `Source`, and the sidecar
   gets binds of the same subdirectories under it (`<Source>/bin`, `<Source>/proxy/<session>`, …). The path inside the
   container and on the machine need not be the same.
3. **Never a path under Docker's data root.** The runner does not bind a volume's `Mountpoint`
   (for example `<data root>/volumes/<name>/_data`): that path is the daemon's internal layout and does not exist
   for a daemon on another host or inside a VM (Docker Desktop, OrbStack).
4. **The sidecar sees only its own session's directories**, never the credentials, as with the bind today.
5. **No ports, tokens, TLS or Docker attach** between the runner and the sidecar: the relay stays a Unix
   socket in a mounted directory, as today.
6. `checkBind` (`runner/internal/docker/container.go`) refuses an agent's bind that would show the state
   directory. With a volume the state directory has no host path an agent could name, and an agent's bind of a
   volume's `Mountpoint` is refused as a path under the data root (point 3 applies to agent binds too);
   with a directory the check compares against the mount's `Source`.

**The Docker version rule.** One rule, in the same words wherever it is written:

> **Needs Docker 26 or later. On older Docker, tick *Keep it in a directory on this machine*, or use the Linux service.**

It holds because the default command and the "keep in a volume" checkbox mount the sidecar's directories through
volume subpaths (Engine 26.0, API 1.45), while the directory checkbox uses plain binds and works on older Docker,
down to today's minimum. **The runner checks the API version only when its state directory is a volume.** With a
directory it starts on an older daemon as it does today. On an older daemon with a volume, the runner **stops at
start** with an error that names the version it found and the minimum (26.0), and then the three ways out: update
Docker, run the command with a directory on the machine (the checkbox), or use the Linux service. There is no
fallback mode.

The rule is written in these places, in these words: the dialog's line under the Docker command, the label of the
directory checkbox (which says that it also works on older Docker), the runner's error above, the user guide
("Running the runner in Docker"), and `DESIGN.md` §14.4. The Linux service tab keeps today's minimum.

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
  daemon's filesystem, and in a directory on the machine is on the machine's. It reports the figure **with the path measured**.
- Below **20 GiB** it logs a warning. It **never refuses** to start, and a failed measure is logged, not an error.
- The `aixle-runner-docker-root` volume is not in the command.
- **Nothing relies on the figure.** It is not sent as a gate, not a platform decision and not a scheduling input;
  the design and the user guide say it is informational.
- The preflight checks the **Docker Engine version** (26.0 or later) only when the state directory is a volume, and stops
  with the message of §3.2.

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

- `machineInstructions.ts`: `dockerScript` → `dockerCommand({ registration, name, privateRegistry, keep })`, where
  `keep` is one option, `none` (the default), `volume` or `{ directory: path }`, so the two "keep" boxes cannot both be
  set. A new `installCommand({ registration, name, noAutoUpdate })`; `installScript` stays for the step-by-step
  section. `DOCKER_PLATFORM` as a platform value, `runnerImage` for the Docker tab, `shellQuote` and the name checks
  stay. **`DockerHost` goes**, with the Docker host control: there is no macOS/Linux choice. Every platform value
  (URL, token, name, image, directory path) goes through `shellQuote`.
- `AddMachine.tsx`: a top-level `SegmentedControl` **Docker** | **Linux service**, Docker first and selected on
  open; the Docker host control and the per-platform control (outside the step-by-step section) go. The two
  checkbox groups above, the collapsed sections, the helper lines (`sudo` on Linux, `docker logs`, no
  self-update in Docker, the arm64 text kept short, and the Docker version rule of §3.2 in one line under the
  Docker command).
- `RunnerRegistration` keeps `binaries` (the step-by-step section reads it), so the controller, the resource and
  `Runners::MachineRegistration` do not change.

### 3.6 Docs

- `docs/user-guide/runners.md`: "Adding a machine" and "Running the runner in Docker" rewritten around the two
  tabs, the checkboxes, the Docker version rule (§3.2), the setting for unregister on stop in an edited command (§3.1), the cleanup after a hard kill (§3.1), the update of a Docker runner (`docker rm -f aixle-runner`, then the new
  command with the named volume checkbox ticked and without the three `-e` flags, since the volume holds the
  registration) and removal.
- `DESIGN.md` §6.3 (a "row 12c" paragraph), §14.4 ("`manual` in Docker": nothing kept by default, self-registration
  on first start, the explicit unregister-on-stop setting, the Docker version rule in the words of §3.2, the informational disk figure), §15 row 12c, `docs/index.md` entry.
  The `host` → `machine` mode rename (§3.1) touches every place the docs say `--mode host`.
- `docs/operations/releasing.md` only if its runner-release steps change; they do not.

## 4. Order

1. **Runner PR** (§3.1–3.3, the image entrypoint and `VOLUME`): Go changes and tests, then Alex tags `runner-v0.6.0`
   (a minor: new behaviour, no break). The mounts spike of §3.2 first.
2. **One platform PR** with the pin (`0.6.0` and its two digests in `config/settings.yml`, and
   `recommended_version: "0.6.0"`, as #277 did for `0.5.0`), the dialog, the install script and the docs
   (§3.4–3.6). The runner release comes first; this PR is opened after it. The pin is in the same PR, so the Docker
   command and the image it names arrive together.

## 5. Testing

- **Go** (`runner/…`, as the `Runner (Go)` job runs them):
  - `cli`: `--mode machine` with no credentials and the three variables registers once and runs; with credentials
    and the variables it registers nothing (a fake gateway fails the test on a `register` call); a refused
    token writes no credentials and exits non-zero; no token in any output.
  - `cli`: SIGTERM and SIGINT with `AIXLE_RUNNER_UNREGISTER_ON_STOP=1` unregister, whatever the mount (an anonymous
    volume, a named volume, a directory, no `--rm`); with `0` or unset they do not; the flag wins over the variable.
    Unregister, teardown and exit finish inside 10 s against a slow fake gateway.
  - `main`: the modes are `machine` and `proxy`; `host` is not accepted; the controller starts from its explicit command.
  - `docker`: the runner copies its binary to `<state-dir>/bin` at start, on a bare host and with `AIXLE_RUNNER_IN_CONTAINER=1`;
    on a bare host it inspects nothing; in a container the inspect only supplies the volume name or the `Source`;
    sidecar mounts for a volume state, anonymous and named (subpath mounts, `/aixle-bin/aixle-runner`) and for a
    directory (binds under the `Source`, any path); no mount under a volume's `Mountpoint`; `checkBind`.
  - `docker`: cleanup removes only containers labelled with its own key: a normal stop removes the sidecar and agent; a
    restart with kept state removes the leftovers of its own key; an unlabelled container and a container of another
    key are never touched, and a new key (the default mode after a hard kill) touches nothing of the old run.
  - `preflight`: the figure is reported with the path measured; below 20 GiB a warning and no refusal; a failed
    measure is not an error; the version check runs only for a volume: Docker below 26.0 with a volume stops the
    start with the version found, the minimum and the three ways out, and with a directory it starts.
  - `realdocker_test.go`: the subpath mount works on a real daemon (§3.2).
- **Image**: a test (or CI step) that the image's `ENTRYPOINT`, `CMD`, `VOLUME` and the two `ENV`s are as §3.1 says,
  and that it has no shell entrypoint.
- **Rails**: a controller test for `machine-install.sh` (public, `no-store`, the rendered version and both
  digests equal the pins, `404` with no recommended version, no value outside the pins in the body); a
  `shellcheck` run on the rendered output in CI if the repository's CI has it, otherwise `sh -n`, plus a
  test that runs the script under a fake `PATH` (stub `uname`, `curl`, `sha256sum`, `systemctl`, `aixle-runner`) for each architecture,
  a digest mismatch (nothing runs) and an unknown architecture.
- **Frontend**: `machineInstructions.test.ts` covers the default of each tab and every combination that changes
  a command (private registry, `keep: volume`, `keep: { directory }`, each with the registry box, no-auto-update; one `keep` option, so both cannot be set), the quoting of a name and a directory path with a quote, and
  that the Docker default has no `sudo`, `RUNNER_DIR`, `docker-root`, `configure`, `-d` or `-v` for the runner's state, and no `AIXLE_RUNNER_UNREGISTER_ON_STOP`. `AddMachine.test.tsx`: it
  opens on Docker, switching tabs, each checkbox and the collapsed sections, and that the state resets on reopen.
- **QA on staging** as the task lists: the Docker default on a Coder workspace with Docker registers, shows
  Online and runs a session (this exercises the sidecar through the volume subpath); stopping the default command unregisters the machine; the private-registry box
  gives the default plus that mount; the volume box gives `-v aixle-runner:…`, `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`,
  `-d --restart unless-stopped` and survives a container restart without the token; the directory box on a Docker older than 26,
  if one is at hand; the Linux service command on a Linux machine.

## 6. Decisions, assumptions and risks

Decisions (all from the task unless stated):

1. **Nothing kept by default, and volume subpaths for the sidecar.** Source: the decisions of 2026-11-25. The
   default is `docker run --rm` over an anonymous volume the image declares; the runner unregisters itself on a
   clean stop because the image turns the explicit setting on (§3.1). The sidecar's mounts use official APIs only (volume `Subpath`, or binds under a
   directory mount's `Source`), never a path under Docker's data root. A volume needs Docker 26.0; the directory
   checkbox works on older Docker, and there is no fallback mode (§3.2).
2. **`machine-install.sh`, rendered by the platform, with digests in the script.** Source: the task's guarantee
   that the script checks the digest of the architecture it picks.
3. **No Docker host choice and no `sudo` in the Docker command.** With no host directory the macOS/Linux difference is
   only `sudo` for a user outside the `docker` group, which a helper line covers. Alternative: a Linux/macOS
   second level, rejected because the task asks for one command where possible.
4. **Name: Linux service.** Source: the task allows picking the clearest name.
5. **No version guard in the platform.** The pin and the dialog ship in one PR after the runner release (§4), so the
   command and the image it names arrive together; a guard would add a second code path for a state that does not occur.
6. **`binaries` stays in the registration answer** for the step-by-step section.
7. **Nothing is guessed.** Unregister on stop, the container case and the mode are explicit settings or flags (§3.1,
   §3.2); no mount type, `AutoRemove` or `/proc` check decides them. The runner inspects its own container only to
   learn where its directory lives.
8. **Cleanup is limited to the runner's own labelled containers** (§3.1).

Risks and edge cases:

- **The token sits in the container's environment** (`docker inspect`, readable by whoever can use Docker, who
  is root on the machine anyway). It is single-use, expires in an hour and is ignored once the state holds credentials.
- **A crash between the register answer and writing the credentials** loses the token: the machine needs another
  one. This is the same window `configure` has now.
- **A subpath of a volume mounts what is there at the time**: the runner creates `bin` at start and the session
  directories before the sidecar (as it does for binds).
- **One session at a time.** The sidecars of two sessions on a machine would share the daemon's default network;
  today a machine runs one session, so this does not occur.
- **Removing a kept volume or directory deletes the credentials**: the machine must be revoked and added again. The guide says so.
- **A hard kill in the default mode leaves** a registered machine that no longer answers, and the session's sidecar and
  agent with the anonymous volume (`--rm` cannot remove a volume the sidecar still uses). The next start is a new
  machine and touches none of it (§3.1, Cleanup). The guide shows the removal by label; Revoke or Delete on the runner
  page removes the machine.
- **An edited command that keeps the container but not the setting**: for example `--restart always` with the image's
  unregister-on-stop still on, so `docker stop` unregisters a machine that `docker start` brings back without a
  registration. The setting is explicit, so the guide says to add `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0` for any
  command that keeps the container.
- **The disk figure can be wrong** (a volume on a remote daemon, a full data root elsewhere). It is informational
  only, so a wrong figure costs a misleading log line, never a refused start.
- **`curl | sh`**: public script, no secret in it, TLS as the trust root as for the digests today; the section
  **Install step by step** is the alternative.
- **Two commands on a machine**: only one machine runner per machine, the lock refuses the second, as today.
- **Rootless Docker, Podman, Windows**: not covered, as before.

## 7. Deferred

- **A network per session**, for when a machine runs more than one session at a time (today it runs one).
- A live "waiting for the machine" state in the dialog (it would use the runner's machines list).
- Removing `binaries` from the registration answer once the step-by-step section goes.
- A Windows or rootless Docker instruction.
- Self-update for the Docker runner (the tag is the version, `DESIGN.md` §14.4).
