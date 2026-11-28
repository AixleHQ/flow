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
machines list on its page, what the runner's status means, what a session shows
while it waits for a free machine, the reuse policy and what a failed machine needs, what
you take on with a `manual` machine, what it reaches outbound and its known
limits, and interactive sessions.

---

## Adding a machine

A `manual` runner is a pool of machines that you register yourself, the way
GitHub self-hosted runners are registered. Each machine runs the `aixle-runner`
program and needs one **registration token**.

Open the runner's page and press **Add machine**. The button is shown to
whoever may manage that runner, and only while the runner is not revoked.

The platform creates a registration token and shows it inside one command. The
token is:

- **single use**: it registers one machine, and a machine that has registered
  does not need it again;
- **short-lived**: it expires an hour after it is created, used or not;
- **shown once**: the platform keeps only a digest of it. Close the window and
  it is gone; press **Add machine** again for a new token.

The dialog opens on **Docker**. Choose a machine name, pick **Docker** or
**Linux service**, tick the boxes you need, and copy the command. The command
is the same for every machine of its tab: only the name and the token change.

### Docker

Run it on any machine that has Docker and can reach the platform. It needs no
`curl`, no `sha256sum` and no systemd. By default the command is one
`docker run` that stays in the foreground:

```sh
docker run --rm --name aixle-runner -v /var/run/docker.sock:/var/run/docker.sock \
  -e AIXLE_RUNNER_URL='…' -e AIXLE_RUNNER_TOKEN='…' -e AIXLE_RUNNER_NAME='…' \
  'ghcr.io/aixlehq/aixle-runner:<version>'
```

(The dialog shows it on one line.) The container registers the machine on its
first start, using the three variables, and then runs it. The Docker socket
lets the runner start the sessions' containers. On a Linux machine whose user
is not in the `docker` group, put `sudo` in front.

By default **nothing is kept**. The registration lives in a volume that goes
away with the container (`--rm`), and stopping the command (Ctrl+C, closing the
terminal, or `docker stop aixle-runner` from another terminal) stops the
runner: it removes its session containers and **unregisters the machine**.
Start the command again and you get a new machine, with a new token from a new
**Add machine**.

The runner in the container runs as root, because access to the Docker socket
is already root on the machine. It does not update itself: the image's tag is
its version.

**Docker version.** Needs Docker 26 or later. On older Docker, tick **Keep it
in a directory on this machine**, or use the Linux service.

#### The boxes

Each box adds exactly its own flags to the command.

| Box | What it adds |
| --- | --- |
| **Images from a private registry** | `-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"`. The runner reads registry credentials from `~/.docker/config.json` of the user it runs as, which in the container is the container's root, not yours. A file with a credential helper (`credsStore`) does not work in the container: use a file with the credentials in it. |
| **Keep the registration in a volume** | `-v aixle-runner:/var/lib/aixle-runner`, `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0`, and `-d --restart unless-stopped` instead of `--rm`. The container runs in the background and starts again with Docker. The machine survives a container restart without the token. Needs Docker 26 or later. |
| **Keep it in a directory on this machine** | The same, with `-v <directory>:/var/lib/aixle-runner` and a path you enter, any absolute path. Also works on Docker older than 26. |

The two "keep" boxes exclude each other. With either one, stopping the
container does not remove the machine, and `docker start aixle-runner` brings
it back without the token. Removing the volume or the directory deletes the
machine's credentials: Revoke the machine and add it again.

#### Unregister on stop in an edited command

The image unregisters the machine when it stops, unless
`AIXLE_RUNNER_UNREGISTER_ON_STOP` is `0`. The keep boxes set it to `0`. If you
edit the command so that the container is kept (for example `--restart always`
or no `--rm`), add `-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0` yourself, or
`docker stop` will unregister a machine that `docker start` brings back without
a registration.

#### If the runner is killed

`docker kill` or a power loss gives the runner no chance to clean up. The
machine shows as not answering on the runner's page: press **Revoke** or
**Delete** on its row. In the default mode the next start is a new machine and
does not touch what the old run left, so remove the leftovers by hand. List the
containers and volumes the old runner created (they carry its machine key in a
label) and remove the containers together with their anonymous volumes, then
the volumes:

```sh
docker ps -a --filter label=aixle.com/environment
docker rm -fv <container id>
docker volume ls --filter label=aixle.com/environment
docker volume rm <volume name>
```

A runner that unregisters itself (a stop with unregister-on-stop on, or the
`unregister` command) removes its own workspace and cache volumes, so only a
hard kill leaves them.

With a kept registration the restarted runner is the same machine, and it
removes its own leftovers at start.

#### Updating a Docker runner

A runner in Docker does not update itself. To update it, remove the container
and run the new command of **Add machine** with the **Keep the registration in
a volume** box ticked (or the directory box, with the same path) and without the
three `-e AIXLE_RUNNER_URL`, `_TOKEN` and `_NAME` flags. The volume or directory
holds the registration, so those variables would be ignored and the old token is not needed. Remove the container with
`docker rm -f aixle-runner` first, then run the new command; it names the image
of the new version.

#### Removing a Docker machine

- **Default command:** stop it. The machine unregisters itself.
- **Kept registration:** press **Revoke** or **Delete** on the machine's row,
  then run `docker rm -f aixle-runner` (and `docker volume rm aixle-runner` for
  the volume, or delete the directory). To remove it from the machine's side
  instead, stop it and run the same image with `unregister` on the kept state:
  `docker stop aixle-runner && docker run --rm --volumes-from aixle-runner
  'ghcr.io/aixlehq/aixle-runner:<version>' unregister`.

The dialog shows these commands in its collapsed **Remove this machine**
section.

#### Free disk

The runner reports the free disk space where it keeps its files and logs a
warning below 20 GiB. The figure is for information only: it never stops the
runner from starting, and the platform does not use it.

macOS works through Docker: OrbStack is checked, Docker Desktop as far as
checked. Rootless Docker and Podman (another socket path) and Windows are not
covered.

### Linux service

Run it on a Linux machine with systemd and Docker, with `curl` and `sha256sum`
installed, as a user who can use `sudo`, that can reach the platform. (Hosts
without systemd are not covered; use Docker.) The command is one line:

```sh
curl -fsSL '<platform>/runner/v1/machine-install.sh' | sudo sh -s -- --token '…' --name '…'
```

The platform serves the script and renders it from its own pins, so the
version and the SHA-256 it checks are the ones the platform pins. The script:

1. **Checks the machine.** It stops, with a message, on a machine that is not
   Linux, that has no `systemctl`, `curl` or `sha256sum`, or when it is not run
   as root.
2. **Downloads the binary and verifies it.** It picks `linux-amd64` or
   `linux-arm64` from `uname -m`, downloads the binary from the platform's own
   host (`/runner/v1/releases/<version>/<os>-<arch>`) at the version the
   platform recommends, and checks it against the SHA-256 the platform pins for
   that version and architecture. It does not run the binary if they differ.
3. **Registers the machine and runs it as a service.** `aixle-runner configure`
   uses up the token and stores the machine's credentials in
   `/var/lib/aixle-runner/credentials`; `service install` and `service start`
   set up a systemd service that survives logout and reboot.

The script accepts only `--token`, `--name` and `--no-auto-update`.

By default an idle machine updates itself to the version the platform
recommends. To turn that off, tick **Turn off self-update**, which adds
`--no-auto-update`.

To remove the machine, run `sudo aixle-runner unregister` and
`sudo aixle-runner service uninstall` on it, or press **Revoke** or **Delete**
on its row.

#### Install step by step

If you would rather not pipe a script into a root shell, the dialog's
collapsed **Install step by step** section (on the Linux service tab) has the
same steps to run one at a time: download the binary, compare its SHA-256 with
the one the platform shows, run `configure`, then `service install` and
`service start`. Choose `linux-amd64` or `linux-arm64` inside it.

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
  - **Failed**: the machine is out of rotation after a failed reset, with the
    reason shown. It stays so until you revoke it (see below);
  - **Gone**: the machine was unregistered or revoked, and the line under it says which;
- the runner **version** and the **OS / arch** it reported at `configure`
  (updated every time the runner starts);
- the **first-seen IP**, the address the machine registered from, and **added
  by**, the user who created the registration token with **Add machine**. A
  machine registered before these were recorded shows a dash for both;
- when it was **registered**;
- its **last seen**: the last time the platform heard from it. The runner's own
  "Last seen" in the overview is the latest of its machines'.

The list refreshes itself every 15 seconds while the page is open. The runners
list shows, for a manual runner, **machines busy/total**: the machines holding a
session out of those registered and not gone.

An **offline machine is given no new session**. While another machine of the
runner is free, a session goes there. If every machine of the runner is
offline, the session is refused at launch with a message naming the runner and
saying its machines are offline: start `aixle-runner` on one of them (a machine
returns to **Idle** on its next poll, within seconds), or pick another runner.
A machine that is busy running a long step is not treated as offline while that
step is within its time limit, even when it is silent.

A session that is already **waiting for a machine** when its machines go offline
keeps waiting: the session page says it waits for a machine that is offline and
names it, and the session starts when a machine is back and free. It fails with
the "has no machine online" message once no machine of the runner has been heard
for 15 minutes. If every machine of the runner has failed, the session fails at
once.

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

## What the runner's status means

The runner's page and the runners list show a status, with the reason under it.
For a `manual` runner the platform works it out from its machines once a minute,
so it can be up to a minute behind what a machine is doing. It reads what the
machines last reported and calls nothing on them.

A machine is **online** or **idle** while the platform heard from it in the last
90 seconds. A machine that is running a long step, such as pulling an image for
several minutes, keeps reporting while it runs, so it stays online. A machine
whose `aixle-runner` is older than the version that reports during a step shows
**offline** during a long step until it updates itself.

| Status | What it means |
| --- | --- |
| Pending | No machine has registered yet. It becomes Connected within about a minute of the first machine reporting. |
| Connected | Every registered machine was heard in the last 90 seconds, and none has failed. |
| Degraded | Some registered machines are offline or failed. The reason names them. Sessions still start on the machines that are online. |
| Unreachable | No registered machine has been heard for more than 3 minutes, every machine has failed, or no machine is registered (every one was unregistered). The reason says which. |
| Disabled, Revoked | Set by a person. The check does not change them. |

The status is for you: it refuses nothing. Whether a session may start on a
runner is decided by its machines at that moment. A runner with no machine that
can take a session refuses the launch, and the message says why: every machine
is offline, none is registered, or every one failed.

## Waiting for a free machine

A machine takes one session at a time. When a session needs a runner whose
machines are all busy, the session waits and starts as soon as a machine is
free. The session page says **Waiting for a free machine**, and under it names
the runner and how many of its machines are busy:
`Waiting for a free machine on runner "Build farm" (1 of 1 busy).` Machines that
are offline or failed are not counted. A session that waits for a hosted
cluster still says **Waiting for cluster capacity**.

## Reuse policy and scrub

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
- **A machine is taken out of rotation** (state **Failed**, with the reason) only
  for its own failure: its reset fails, or its runner reports that Docker or the
  disk is not fit to run sessions. A session that fails, however many in a row,
  does not fail the machine once its reset succeeds.

**Who sees what a scrub keeps.** A company runner's machines are shared by every
project of the company. On a company runner with Reuse, the next session on a
machine may belong to another project, and it sees what the scrub kept: the
repository checkouts and the caches. Choose Reset, or use a project runner, to
keep projects apart. On a project runner, what is kept stays within that project.

**Writable host mounts are outside every policy.** A writable home mount, an
extra mount with `:rw` and a host-path cache mount let the agent write to the
machine outside Aixle's volumes. A scrub or a reset removes what Aixle wrote
there, not what the agent wrote.

The runner's form asks you to confirm each one. For every writable host mount
(a writable home mount, an extra mount with `:rw`, a cache mount that is a path
on the machine) it shows a checkbox, *I understand the agent can write to
`<path>` on this machine*, and saves the choice in
`container.acknowledged_writable_mounts`. A runner with a writable host mount
that is not ticked is refused at the field.

### Revoking a machine

**Revoke** in a machine's row removes a machine for good: a lost or compromised
machine, or one you no longer want on the runner. It works on a machine in any
state but Gone. It is available to whoever can revoke the runner: a company admin
on a company runner, and a project admin or owner on a project runner.

- The machine shows **Gone**, marked **Revoked**, and stays in the list. Its credentials are revoked,
  so `aixle-runner` on it is refused (`401`) on its next request and stops. The
  other machines of the runner keep working.
- If the machine held a session, the session ends at once with a message that
  names the machine, and its slot is released. A session waiting for a machine on
  the runner goes on waiting for its other machines.
- **Aixle does not clean the machine.** Remove the Aixle containers and volumes
  it left, and its service (`aixle-runner service uninstall`), yourself.
  `aixle-runner unregister` on the machine does the same as Revoke.

### What Revoke and Delete do to a runner's sessions

Revoking a runner, and deleting it, which revokes it, ends its sessions: a
session running on it fails with a message that says the runner was revoked, and
one waiting for one of its machines ends with the message a launch gives for a
revoked runner. Nothing stays in Finishing or waiting because its runner was
revoked.

### A failed machine

A **Failed** machine takes no session and shows why, for example *build-01
failed to reset after session 12: reset_failed: …*. Failed is final: the
machine's credentials stop working, and nothing returns it to rotation. Fix what
the reason names (start Docker, free a volume that is in use), then **Revoke**
the machine and register the host again with **Add machine**. Return to service
was removed.

While every machine of a runner is Failed, a launch on it is refused with a
message that says to revoke the machine and add it again, or to pick another
runner.

## A machine that stops answering

A session keeps running on a machine that loses its network or whose
`aixle-runner` stops, because the agent belongs to the runner on the machine.
The machine shows **Offline** after 90 seconds, and the platform asks it
nothing while it is offline.

- **The machine is back within 15 minutes.** If the agent is still running, the
  session goes on and can finish. If the agent exited meanwhile, the session
  fails within a few minutes of the machine's return, as a session whose
  container died does.
- **The machine is away for 15 minutes.** The session fails with *Runner
  environment lost contact for 15 minutes.* A session that has already finished
  keeps its outcome.
- **The slot stays with the machine.** The failed session still holds the
  machine, so no other session takes it and the session's slot is not
  released. When the machine is heard again, the platform stops the session's
  leftover container, resets the machine, and releases the slot. The machine
  shows **Idle**, and a session waiting for it starts. To give the slot up
  without waiting, revoke the machine.
- **A revoked or deleted runner** never hears its machines again, so its session
  fails after the 15 minutes and its slot is released then.

## Interactive sessions

An interactive session can run on a runner, and its page works as a hosted
session's does: the terminal, the read-only view other people get, the file
panel, uploads and the IDE. Pick the runner in **Runs on** on the new-session
form, in either mode.

How it works: the machine opens a connection out to the platform's relay while
it holds a session, and the browser's requests to the session's terminal, IDE,
file panel and upload ride that connection. Nothing is opened inbound on the
machine. The connection exists only while the machine holds a session.

- **The terminal, the IDE and uploads are for the session's owner.** Anyone else
  who can see the session gets the read-only terminal.
- **The surfaces start a few seconds after the container does.** The IDE takes
  the longest. If the page shows an error in that window, reload it.
- **A machine needs runner 0.5.0 or later.** Earlier versions have no tunnel.
  A session started on one runs, but its terminal does not open: the page shows
  an "unavailable" (503) answer from the relay. Update the runner (self-update does it while
  the machine is idle) and start the session again.
- **The connection ends with the session.** Ending the session, or revoking the
  machine, closes it. A restart of the relay drops it until the machine has
  dialed again (up to a minute or two). The terminal retries by itself for about
  two minutes; after that, use its Reconnect button.

## What you take on with a `manual` machine

The platform holds no credential into your machine, so what happens on it is
yours to run and secure. Know this before you add one:

- **The machine keeps the sessions' work between sessions.** Each session runs
  in a new container, removed when the session ends together with its
  credentials, agent home, MCP config, prompt and `/tmp`. Under **Reuse** (the
  default) the workspace volume with the repository checkouts, the cache
  volumes and the pulled images stay on the machine's disk. So the code of every
  repository a session worked on stays there, readable by anyone with root or
  `docker` access on the machine, and the next session starts from those
  checkouts and caches. **Reset** wipes the workspace and cache volumes after
  every session, at the cost of a fresh clone each time. A session that fails
  gets a reset under either policy (see
  [Reuse policy and scrub](#reuse-policy-and-scrub)).
- **The launching user's agent login reaches the machine.** The session runs
  with the credentials of the user who started it, as on every runner.
- **On a company runner the machine is reused across projects.** What a scrub
  keeps is there for the next session, whichever project it belongs to. A
  project runner keeps it within the project. The reuse section says what a
  scrub keeps.
- **The `docker` group is root-equivalent.** `service install` puts the
  `aixle-runner` user in it, because the runner starts containers. Anyone who
  controls that user controls the machine.
- **Sessions share the machine's kernel.** A container does not stop a kernel
  exploit, and a session runs whatever the repository and its dependencies
  contain. Keep the kernel patched, and block kernel modules that load on demand
  if you don't use them. SCTP is one: any process in a container makes the
  kernel load it by opening an SCTP socket, Docker's seccomp profile does not
  stop that, and SCTP has had privilege-escalation bugs. To block it, run
  `echo 'install sctp /bin/false' | sudo tee /etc/modprobe.d/disable-sctp.conf`.
  If `lsmod | grep sctp` already lists the module, reboot afterwards.
- **The runner updates its own binary.** It replaces the binary, which the
  `aixle-runner` user owns, with one whose SHA-256 the platform pins. To allow
  no software change you did not make, run `configure` with `--no-auto-update`
  (the **Turn off self-update** box in **Add machine**), or set
  `config.auto_update: false` to turn it off for the whole runner.
- **Use a dedicated machine,** not a shared developer box.

## What the machine reaches outbound

Nothing inbound is opened: the machine connects out, and the platform never
connects in. If you filter egress, allow at least the following. The list is
documentation of what the runner and the agent use, and it can grow.

- the platform host, on port 443;
- `github.com` and `objects.githubusercontent.com`, for runner binaries;
- `ghcr.io`, for the agent images and the runner image;
- the git hosts of the repositories the sessions use;
- the model provider, or your Bedrock when the agent uses it;
- whatever the agent's own work needs, such as package registries.

## Known limits

- **A bind source can't be under the machine's `/tmp` or `/var/tmp`** when the
  runner runs as the service. The unit has `PrivateTmp=true`, so the runner does
  not see those directories and refuses the bind with `forbidden_mount`. Mount a
  directory elsewhere.
- **With `network: host`, a session's proxy port can collide.** The port is
  `20000 + session id mod 10000`. When another session or service on the
  machine holds it, the session fails with `proxy_port_in_use`, and the platform
  does not retry it on that machine. The listener is on the machine's own
  `127.0.0.1`, so any local user or process can reach it. A session key is still
  required.

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
