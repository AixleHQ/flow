# Runners

A **runner** is where a session's agent container runs. By default sessions run
on the platform's own hosting; a runner sends them to a machine you control
instead. A runner belongs to the company (every project can use it) or to one
project, and lives on the company's **Settings → Runners** page or the
project's **Runners** page. A company admin manages company runners; a company
admin or the project's owner manages the project's own.

Runners are behind the `external_runners` feature flag: without it the pages
do not exist for your company.

This page covers adding machines to a `manual` runner, what the runner's status
means, what a session shows while it waits for a free machine, the reuse policy
and Return to service.

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

### If something goes wrong

- A token that was already used, or that is more than an hour old, is refused
  at `configure`. Press **Add machine** again.
- A revoked runner offers no **Add machine**, and the platform refuses to
  create a token for it (`runner_revoked`). Revoking a runner revokes every
  token and credential it has issued.
- On a self-hosted installation the machine must reach the runner gateway
  (`/runner/v1`) on the platform's host. If the gateway is served on a private
  address, the machine has to be inside that network or on its VPN.

---

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
