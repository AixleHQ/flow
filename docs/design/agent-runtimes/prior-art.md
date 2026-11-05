# Prior art: where comparable self-hosted runners run a job's pieces

**Task:** #205, research for DESIGN.md §6.9 · **Read on:** 2026-11-05 · **Status:** research,
no decision of its own

This document records how services with self-hosted runners, and AI-agent sandboxes, solve the
problems DESIGN.md §6.9 has to settle for `aixle-runner`: where a session's commands run, how the
live log leaves the environment, where helpers such as our callback proxy live, how an
interactive terminal reaches a running job, how the runner's own credentials stay out of the
job, and what a runner restart does to a running job.

Each section answers the same seven questions, from the service's documentation and, where the
source is public, from the code. The comparison table and the patterns that DESIGN.md §6.9 cites
follow the sections. Links are at the end of each section.

**What was read, and its limits.** The documentation pages and source files are the ones linked
below, as published on 2026-11-05. Two projects have reorganised their public repositories since
their best-known versions: Daytona's repository now holds only a README, and OpenHands moved its
runtime into the Software Agent SDK. For those two, this document relies on the documentation.
Where a statement is our reading of code rather than a documented guarantee, the section says so.

---

## 1. GitHub Actions: the self-hosted runner (`actions/runner`)

- **Where commands run.** The runner (the `Runner.Listener` service and a `Runner.Worker`
  process per job) runs on the host. For a container job it creates the job container itself
  with `docker create`, with `tail -f /dev/null` as the entrypoint so the container stays up and
  does nothing on its own, and runs every step inside it with `docker exec`. Commands are
  executed **from outside, through the container runtime**; nothing of the runner is the
  container's PID 1. `DockerCommandManager` wraps the Docker CLI (`create`, `start`, `exec`,
  `logs`, `network create`, `rm`).
- **Output and the live log.** The worker reads each `docker exec`'s stdout and stderr and sends
  the lines to the service: a live console feed while the step runs, and the step's log file
  uploaded when it ends. The job container's own log is not used for step output.
- **Helpers.** Service containers run on a per-job Docker network the runner creates, and the job
  container reaches them by their label as a hostname. Checkout, artifacts and the cache are
  actions, so they run in the job container like any other step, using the Node.js the runner
  mounts into it from its `externals` directory, and a job-scoped token for the service APIs.
  There is no helper container.
- **Interactive terminal.** None built in. Third-party actions open an outbound tmate or SSH
  session from inside the job.
- **The runner's credentials.** The runner's registration (`.runner`, `.credentials`) stays in
  the runner's directory on the host and is never mounted into the job container. The job gets
  job-scoped tokens (`GITHUB_TOKEN`, and the runtime token the artifact and cache actions use),
  which expire with the job. Our reading of `ContainerOperationProvider` is that the job
  container also gets the host's Docker socket mounted, so a container job on a self-hosted
  runner is root-equivalent on the machine.
- **Runner restart or lost connection.** The runner holds a lease on the job and renews it while
  the job runs. A runner that restarts or stops renewing loses the job; the service fails it
  when the lease runs out. Nothing resumes a step.
- **Docker vs Kubernetes.** On Kubernetes the same runner delegates container operations to the
  container hooks (section 2).
- **Transport.** Outbound HTTPS long-poll from the listener to the service; the host opens no
  port. This is the model DESIGN.md §6.1 already follows.

Sources:
[Running jobs in a container](https://docs.github.com/en/actions/writing-workflows/choosing-where-your-workflow-runs/running-jobs-in-a-container),
[About service containers](https://docs.github.com/en/actions/use-cases-and-examples/using-containerized-services/about-service-containers),
[`DockerCommandManager.cs`](https://github.com/actions/runner/blob/main/src/Runner.Worker/Container/DockerCommandManager.cs),
[`ContainerOperationProvider.cs`](https://github.com/actions/runner/blob/main/src/Runner.Worker/ContainerOperationProvider.cs),
[`Runner.Worker/Handlers/StepHost.cs`](https://github.com/actions/runner/blob/main/src/Runner.Worker/Handlers/StepHost.cs).

## 2. GitHub Actions: runner container hooks and Actions Runner Controller in Kubernetes mode

- **Where commands run.** `ACTIONS_RUNNER_CONTAINER_HOOKS` points the runner at a script that
  replaces its Docker calls with four hooks: `prepare_job`, `run_script_step`,
  `run_container_step` and `cleanup_job`. The Kubernetes implementation creates a separate
  workflow pod for the job container and its service containers, and `run_script_step` runs each
  step **through the Kubernetes exec API** into that pod. Container actions run as Kubernetes
  Jobs. The runner itself is a pod of its own.
- **Output and the live log.** The exec's output streams back to the runner pod, which sends it
  on as in section 1. The pod log API (`pods/log`) is used for container actions.
- **Helpers.** Service containers are containers of the workflow pod, so the job reaches them on
  `localhost`. The runner's work directory is shared with the workflow pod through a persistent
  volume claim the runner pod mounts (`ACTIONS_RUNNER_CLAIM_NAME`).
- **Interactive terminal.** None.
- **The runner's credentials.** They stay in the runner pod. The workflow pod is a different pod
  and does not mount them.
- **RBAC.** The runner's service account needs `pods` (`get`, `list`, `create`, `delete`),
  `pods/exec` (`get`, `create`), `pods/log` and `secrets` in its namespace. Executing from
  outside costs `pods/exec`.
- **Runner restart or lost connection.** The exec streams belong to the runner pod; if it goes,
  the job goes. ARC runners are usually ephemeral, one job each.
- **Docker vs Kubernetes.** The same runner binary; only the hook script differs. Job containers
  are mandatory in Kubernetes mode, Docker `create` options are not supported, and a container
  action must state its entrypoint, because the hook overrides it.

Sources:
[Customizing the containers used by jobs](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/customizing-the-containers-used-by-jobs),
[`runner-container-hooks`](https://github.com/actions/runner-container-hooks),
[`packages/k8s/README.md`](https://github.com/actions/runner-container-hooks/blob/main/packages/k8s/README.md),
[`packages/k8s/src/hooks/prepare-job.ts`](https://github.com/actions/runner-container-hooks/blob/main/packages/k8s/src/hooks/prepare-job.ts).

## 3. GitLab Runner: the Docker executor

- **Where commands run.** The runner creates the containers through the Docker Engine API and
  feeds each stage's generated script to a shell in the container through the attached stdin.
  The user's script runs in the **build container** (the job's image). Getting sources,
  restoring and saving the cache, and downloading and uploading artifacts run in the **helper
  container** (`gitlab-runner-helper`), which carries the runner's own tools. Both mount the same
  builds and cache volumes.
- **Output and the live log.** The runner reads the attached output and sends it to GitLab as
  incremental trace updates (`PATCH /api/v4/jobs/:id/trace` with a `Content-Range`), so the
  server can append by offset.
- **Helpers.** Services are separate containers, reached by alias on a network (a per-build
  network with `FF_NETWORK_PER_BUILD`). Git, artifacts and the cache are the helper container's
  job, so the build image needs none of those tools.
- **Interactive terminal.** Through the runner's session server (section 5).
- **The runner's credentials.** The runner's authentication token stays in `config.toml` on the
  host. The job and the helper get the job-scoped `CI_JOB_TOKEN`.
- **Runner restart or lost connection.** Jobs do not survive the runner process. A graceful stop
  (`SIGQUIT`) waits for running jobs to finish before exiting.

Sources:
[Docker executor](https://docs.gitlab.com/runner/executors/docker/),
[Advanced configuration](https://docs.gitlab.com/runner/configuration/advanced-configuration/),
[Commands: signals](https://docs.gitlab.com/runner/commands/#signals).

## 4. GitLab Runner: the Kubernetes executor

- **Where commands run.** The runner calls the Kubernetes API and creates one pod per job, with a
  `build` container, a `helper` container and one container per service. Commands reach the
  build container **through the Kubernetes API**, by attach in the default strategy and by exec
  in the legacy one (`FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY`).
- **Output and the live log.** In the attach strategy the script's output is also written to a
  log file on a volume shared by the pod's containers, and the runner reads it by running
  `gitlab-runner-helper read-logs` in the helper container. The helper resumes from an offset,
  so a broken stream to the API server costs a reconnect, not the log. GitLab introduced this
  after the exec strategy lost output and exit statuses on broken connections (merge request
  2038).
- **Helpers.** The helper container, as on Docker. Services and the build container share the
  pod's network namespace, so services are on `localhost` (or their DNS alias).
- **Interactive terminal.** Through the session server, by an exec into the build container.
- **The runner's credentials.** The runner holds its GitLab token and its Kubernetes access: a
  service account when it runs in the cluster, or a kubeconfig, host and client certificates when
  it runs outside it. A runner outside the cluster is outside-in in the full sense.
- **RBAC.** `pods` (`create`, `delete`, `get`, and `list`/`watch` for some features),
  `pods/exec`, `pods/attach`, `pods/log`, `secrets`, `configmaps` and `services`, in the job
  namespace.
- **Runner restart or lost connection.** The job's pod outlives a dropped stream, and the
  attach strategy's log file lets the runner pick the output up again. A runner that loses the
  job altogether leaves the pod to its cleanup.
- **Docker vs Kubernetes.** The same three roles (build, helper, services), as containers on a
  Docker network or as containers of one pod.

Sources:
[Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/),
[MR 2038: the attach strategy's `read-logs`](https://gitlab.com/gitlab-org/gitlab-runner/-/merge_requests/2038),
[MR 2824: the attach strategy when the log file is deleted](https://gitlab.com/gitlab-org/gitlab-runner/-/merge_requests/2824).

## 5. GitLab Runner: the interactive web terminal

- **How it works.** The runner runs a session server (`[session_server]` in `config.toml`, a
  `listen_address` and an `advertise_address`). GitLab connects **to the runner** on that
  address, over a WebSocket, and the runner opens a shell in the build container: `docker exec`
  on the Docker executor, an exec through the Kubernetes API on the Kubernetes executor.
- **What it costs.** An inbound path from GitLab to every runner host, which GitLab's own
  instance runners on GitLab.com do not offer. The Helm chart supports it only with one replica
  and a `LoadBalancer` Service. On the Docker executor the terminal ends when the build script
  ends, because the container stops.
- **Access.** Only the user who started the job (or an administrator) may open it.
- **Why it matters here.** It is the one comparable terminal that needs inbound access to the
  runner, which DESIGN.md §1.2 and §9.5 rule out for us.

Sources:
[Interactive web terminals](https://docs.gitlab.com/ci/interactive_web_terminal/),
[The `[session_server]` section](https://docs.gitlab.com/runner/configuration/advanced-configuration/#the-session_server-section).

## 6. Buildkite: the agent and `agent-stack-k8s`

- **Where commands run.**
  - *Agent on a host:* the agent polls the Agent API over HTTPS and runs each job as a
    subprocess (`buildkite-agent bootstrap`). The Docker plugin runs a step in a container with
    `docker run`, and by default mounts the agent binary into it, so `buildkite-agent artifact
    upload` and the other job commands work from inside.
  - *`agent-stack-k8s`:* a controller in the cluster polls the Agent API for its queue and
    creates a Kubernetes Job per Buildkite job. The pod has an init container that copies the
    agent binary onto the shared workspace volume, an `agent` container that acquires the job
    and talks to Buildkite, a `checkout` container, and the user's command containers, whose
    **entrypoint is overwritten to the agent binary** (`kubernetes-bootstrap`). Commands run as
    processes **inside** the command containers.
- **Output and the live log.** The agent uploads log chunks to Buildkite while the job runs. In
  the Kubernetes stack the command containers connect to the `agent` container over a Unix
  socket, `buildkite.sock`, on the shared `/workspace` volume, register, and send their output
  through it; the `agent` container uploads it. From the source, the socket is created world-
  writable, because the pod is the security boundary.
- **Helpers.** Checkout is a container of its own. Artifacts and metadata go through the
  injected agent binary, which reaches Buildkite with the job's access token.
- **Interactive terminal.** None.
- **The runner's credentials.** The cluster's agent token is used by the controller and the
  `agent` container. Command containers get the job's environment over the socket, including the
  job-scoped access token, not the agent token.
- **Runner restart or lost connection.** An agent that stops heartbeating has its job marked
  lost. In the Kubernetes stack, the job's pod carries its own agent, so a controller restart
  does not stop a job that is already running.
- **Docker vs Kubernetes.** On a host the agent is a process next to the job; on Kubernetes it is
  a container in the job's pod and an injected binary in each command container.

Sources:
[Agent Stack for Kubernetes overview](https://buildkite.com/docs/agent/self-hosted/agent-stack-k8s),
[`buildkite/agent-stack-k8s`](https://github.com/buildkite/agent-stack-k8s),
[`buildkite/agent` `kubernetes/runner.go`](https://github.com/buildkite/agent/blob/main/kubernetes/runner.go),
[Docker plugin](https://github.com/buildkite-plugins/docker-buildkite-plugin).

## 7. CircleCI: the machine runner and the container runner

- **Where commands run.**
  - *Machine runner:* `circleci-runner` on the host claims tasks and runs a task agent per task
    on the host.
  - *Container runner:* `container-agent`, installed with Helm, claims tasks and creates a pod
    per task. **Up to 3.0 it used the Kubernetes exec API** to copy the task agent into the
    primary container and run commands from outside. **Since 3.1 an init container
    (`runner-init`) copies an orchestrator, GOAT, and the task agent onto a shared ephemeral
    volume, and GOAT runs as PID 1 of the primary container** and runs the task agent, which
    runs the steps inside.
- **Why they moved.** The `runner-init` README gives the reasons: the exec API was not built for
  that intensity of use, it produced errors, it lost idempotency on disconnections, and it loaded
  the API server enough to congest the cluster network under heavy task load. With GOAT as PID 1
  they also gained signal handling, process reaping, an HTTP health check instead of exec probes,
  and independence from the image's shell.
- **Output and the live log.** The task agent in the primary container streams step output to
  CircleCI itself. When a task has service containers, a logging sidecar reads their logs
  through the pod log API with its own narrow service account and streams them to the UI.
- **Helpers.** Service containers are containers of the task pod.
- **Interactive terminal.** "Rerun job with SSH" is offered on container runner, with extra
  permissions on Gateways and Services: an inbound path into the cluster.
- **The runner's credentials.** The resource class token is in a Secret used by
  `container-agent`; the task pod does not get it.
- **RBAC.** `pods` and `pods/exec` are still in the documented Role, with `secrets`, `events` and
  `nodes`. The documentation assumes the runner has a namespace of its own, because its agent
  or garbage collector may delete other pods in it.
- **Runner restart or lost connection.** A termination signal drains `container-agent` cleanly.
  After a crash, the documentation makes no promise for in-flight or queued tasks.

Sources:
[`circleci/runner-init` README](https://github.com/circleci/runner-init/blob/main/README.md),
[Container runner reference](https://circleci.com/docs/runner/container-runner/),
[Self-hosted runner concepts](https://circleci.com/docs/runner/runner-concepts/).

## 8. Jenkins: the Kubernetes plugin

- **Where commands run.** The plugin creates an agent pod. Its `jnlp` container runs the Jenkins
  agent, which connects out to the controller (TCP or WebSocket). Steps inside `container('x')
  { … }` run in container `x` of the same pod through the **Kubernetes exec API**, opened by the
  plugin's client on the controller side (`ContainerExecDecorator`), not by the agent.
- **Output and the live log.** A `sh` step is a durable task: the command is launched with its
  output redirected to a log file in a control directory of the workspace, and its exit code
  written to a result file. The controller reads both through the agent's channel. The output
  therefore does not depend on the exec stream staying open.
- **Helpers.** Any container in the pod template, sharing the workspace volume and `localhost`.
- **Interactive terminal.** None.
- **The runner's credentials.** The controller holds the Kubernetes credential. The agent's
  secret is in the `jnlp` container's environment, which other containers of the pod do not see.
- **Runner restart or lost connection.** A durable task survives a controller restart: the
  pipeline resumes and reattaches to the log and result files.
- **Docker vs Kubernetes.** The Docker plugins run `docker exec` from the agent, with the same
  durable-task wrapper.

Sources:
[Kubernetes plugin](https://plugins.jenkins.io/kubernetes/),
[`ContainerExecDecorator.java`](https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/main/java/org/csanchez/jenkins/plugins/kubernetes/pipeline/ContainerExecDecorator.java),
[`durable-task` plugin](https://github.com/jenkinsci/durable-task-plugin).

## 9. Tekton Pipelines: the injected `entrypoint`

- **Where commands run.** A TaskRun is one pod, a container per step. An init container copies
  Tekton's `entrypoint` binary into a shared `emptyDir` (`/tekton/bin`), and the controller
  rewrites each step container's command to that binary, with the step's original command after
  it. The binary waits for the previous step's marker file, runs the command **as a process
  inside the step container**, and writes its own marker and exit code.
- **Output and the live log.** Each step's stdout and stderr is its container's log, read
  through the pod log API (`tkn` and the dashboard do this). Results leave through the
  container's termination message.
- **Helpers.** Sidecars are containers of the pod. When the steps are done, the controller stops
  them by swapping their image for a no-op one.
- **Interactive terminal.** None.
- **Credentials.** The controller holds the cluster credentials. Step containers get only what
  the Task mounts; credentials for git and registries are prepared into the pod by the
  controller from the service account's Secrets.
- **Controller restart.** The pod does not depend on the controller to run its steps: ordering is
  done by files inside the pod, so a controller restart does not interrupt a TaskRun.

Sources:
[Container contract: entrypoint](https://tekton.dev/docs/pipelines/container-contract/),
[`cmd/entrypoint`](https://github.com/tektoncd/pipeline/tree/main/cmd/entrypoint),
[Sidecars](https://tekton.dev/docs/pipelines/tasks/#specifying-sidecars).

## 10. Argo Workflows: the emissary executor

- **Where commands run.** The executor runs both as an init container, which copies `argoexec`
  into a shared volume, and as a `wait` sidecar. The main container's command is rewritten to
  `argoexec emissary -- <command>`, so the user's command runs **as a process inside the main
  container**, under the injected binary.
- **Output and the live log.** The main container's log, through the pod log API. Signals and
  exit codes are passed through files on the shared volume.
- **Helpers.** The `wait` sidecar collects outputs and uploads artifacts after the main
  container exits.
- **Interactive terminal.** None.
- **Credentials.** The artifact repository credentials are used by the `wait` sidecar, not by the
  main container: a credential kept out of the user's container by putting it in another
  container of the same pod.
- **Security.** The documentation lists no privileged access, no escape from the pod's service
  account, and non-root support. The executor normally reads and writes the container's disk and
  does not use network APIs.

Sources:
[Workflow executors](https://argo-workflows.readthedocs.io/en/latest/workflow-executors/),
[`cmd/argoexec`](https://github.com/argoproj/argo-workflows/tree/main/cmd/argoexec).

## 11. OpenHands: the action execution server and the agent server

- **Where commands run.** OpenHands builds its runtime image on top of the user's base image and
  adds its own server. That server (the action execution server, and in the V1 SDK the agent
  server) runs **inside the sandbox container** and executes shell commands, file operations and
  code there.
- **Output.** The backend talks to that server over HTTP and a WebSocket and receives
  observations and events from it.
- **Helpers.** VS Code and other plugins are started inside the same container.
- **Interactive terminal.** The sandbox exposes its server, VS Code and worker ports on host
  ports, and the frontend reaches them through a URL pattern. The traffic is inbound to the
  sandbox.
- **Credentials.** A session API key protects the server. The sandbox holds what the agent
  needs; there is no separate runner identity to protect from it.
- **Docker vs Kubernetes.** The same image and server on Docker, Kubernetes or a remote runtime
  API.

Sources:
[Runtime architecture](https://docs.openhands.dev/usage/architecture/runtime),
[Remote agent server overview](https://docs.openhands.dev/sdk/guides/agent-server/overview),
[`OpenHands/software-agent-sdk`](https://github.com/OpenHands/software-agent-sdk).

## 12. E2B: `envd`

- **Where commands run.** `envd` is a daemon inside every sandbox (a Firecracker microVM). It
  serves a REST and ConnectRPC API on port 49983: processes with streamed I/O and PTYs, the
  filesystem, environment, metrics, and forwarding of ports that listen on the sandbox's
  `localhost`.
- **Output.** Streamed by `envd`'s process API to the client.
- **Interactive terminal.** A PTY process through the same API.
- **How a client reaches it.** Through E2B's edge proxy, routed by sandbox id and port
  (`<port>-<sandbox id>` hostnames or headers). The traffic is inbound to the sandbox through
  E2B's own proxy.
- **Credentials.** A per-sandbox access token (`X-Access-Token`), returned when the sandbox is
  created. Running user code as a non-root user, separate from the root daemon, is the
  documented hardening.
- **Elsewhere.** The Kubernetes SIG `agent-sandbox` project and OpenKruise Agents run `envd` as a
  pod's entrypoint or inject it as a sidecar, behind their own gateway.

Sources:
[E2B documentation: process API](https://docs.e2b.dev/api-reference/process/start),
[E2B: secured access](https://changelog.e2b.dev/docs/sandbox/secured-access),
[`e2b-dev/infra` `packages/envd`](https://github.com/e2b-dev/infra/tree/main/packages/envd),
[agent-sandbox: the envd example](https://agent-sandbox.sigs.k8s.io/docs/use-cases/examples/envd-sandbox/),
[OpenKruise Agents: accessing sandboxes](https://openkruise.io/kruiseagents/user-manuals/sandbox-access).

## 13. Daytona: runners and the sandbox daemon

- **Where commands run.** A Daytona runner is a compute node that **polls the control plane** for
  jobs and creates, starts, stops and destroys sandboxes on its host. Inside each sandbox a
  daemon serves the Toolbox API: files and git, process and code execution, log streaming and
  terminal sessions.
- **How a client reaches it.** A proxy routes `{port}-{sandbox id}.{proxy domain}` to the right
  runner and sandbox, injects the authentication headers, and carries HTTP and WebSocket
  traffic. "Bring your own compute" regions can run their own proxy next to their runners.
- **Credentials.** The runner holds its control-plane identity; the sandbox is reached through
  the proxy, which adds authentication on the way in.
- **What it shows.** Lifecycle by an outbound-polling runner, execution by a daemon inside the
  sandbox, and interactive traffic through a relay the platform operates.

Sources:
[Daytona architecture](https://www.daytona.io/docs/en/architecture/),
[Bring your own compute](https://www.daytona.io/docs/en/bring-your-own-compute/),
[`daytonaio/daytona`](https://github.com/daytonaio/daytona).

## 14. Coder: the workspace agent

- **Where commands run.** `coder agent` runs **inside the workspace**, started by the template.
  It provides SSH, port forwarding, the web terminal, apps, scripts and liveness.
- **Output.** Agent logs and startup script output are sent to `coderd` over the agent's
  connection.
- **Interactive terminal.** The agent **dials out** to `coderd` over HTTPS and WebSockets and
  joins a WireGuard network (Tailscale's code). Clients connect directly when NAT traversal works
  and are relayed through the control plane otherwise; the workspace opens no inbound port. The
  web terminal is a reconnecting PTY, backed by `screen` when it is installed and by a buffer
  replay otherwise, so a dropped browser connection reattaches to the same shell.
- **Credentials.** The agent token is inside the workspace. From the source, the agent also sets
  `CODER_AGENT_TOKEN` in the environment of the processes it starts, so the workspace's user can
  act as the agent. Coder accepts this because the workspace belongs to that user.
- **Restart or lost connection.** The workspace keeps running; the agent reconnects, and
  reconnecting PTYs survive while the agent does.

Sources:
[Architecture](https://coder.com/docs/admin/infrastructure/architecture),
[Networking](https://coder.com/docs/admin/networking),
[`agent/reconnectingpty`](https://github.com/coder/coder/tree/main/agent/reconnectingpty),
[`agent/agent.go`](https://github.com/coder/coder/blob/main/agent/agent.go).

## 15. Also found: Gitpod's `supervisor`

- **Where commands run.** Gitpod (classic) puts `supervisor` into every workspace container as
  **PID 1**. It manages terminals, starts the IDE, serves a gRPC API and an SSH server, and
  handles graceful termination.
- **Why it is here.** It is the closest analogue to DESIGN.md §6.8's `aixle-runner --mode
  session`: a platform binary as the init process of the user's container, owning the terminal
  and the IDE. It shows the cost too: the platform's binary becomes part of every workspace
  image's boot path.

Sources:
[`components/supervisor`](https://github.com/gitpod-io/gitpod/tree/main/components/supervisor),
[Supervisor component notes](https://github.com/gitpod-io/gitpod/blob/main/memory-bank/components/supervisor.md).

---

## 16. Comparison

"Outside" means through the container runtime's API (Docker exec, Kubernetes exec or attach) by a
process that is not in the job's container. "Inside" means a process in the job's container,
usually an injected binary.

| Service | Commands run | Live log | Helpers (git, artifacts, cache, proxy) | Interactive terminal | Runner credential kept from the job by | Runner restart / lost connection | Docker vs Kubernetes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GitHub Actions runner | Outside: `docker exec` | The exec's output, sent by the worker | Steps in the job container, with mounted Node.js and a job token; services on a job network | None | Staying on the host; job-scoped tokens only | Job lost when the lease runs out | Docker on a host; hooks on Kubernetes |
| ARC with container hooks | Outside: Kubernetes exec into a workflow pod | The exec's output | Service containers in the workflow pod (`localhost`) | None | Being in another pod | Job lost with the runner pod | Same runner, different hook; needs `pods/exec` |
| GitLab Docker executor | Outside: attach to a shell in the build container | Attached output, `PATCH trace` by offset | Helper container (git, artifacts, cache); service containers | Session server, inbound | Staying in `config.toml`; `CI_JOB_TOKEN` | Jobs lost; graceful stop waits | Same roles as containers or one pod |
| GitLab Kubernetes executor | Outside: Kubernetes attach (or exec) | A log file in the pod, read by `read-logs` from an offset | Helper container; services in the pod | Session server, inbound, exec | Kubeconfig or service account in the runner | A broken stream resumes from the offset | Needs `pods/exec` and `pods/attach` |
| Buildkite `agent-stack-k8s` | Inside: injected agent as the command containers' entrypoint | Over a Unix socket to the `agent` container, which uploads | Checkout container; agent binary for artifacts | None | Agent token only in the `agent` container | Job continues without the controller | Agent on a host; agent in the pod on Kubernetes |
| CircleCI container runner | Inside since 3.1: GOAT as PID 1 runs the task agent (exec before 3.1) | Task agent streams; a log sidecar reads service logs via the pod log API | Service containers in the pod | SSH rerun, inbound | Token in `container-agent`'s Secret | No promise after a crash | Machine runner on a host; injected agent on Kubernetes |
| Jenkins Kubernetes plugin | Outside: Kubernetes exec from the controller | Durable task log file, read through the agent | Containers of the agent pod | None | Kubernetes credential on the controller | Durable tasks survive a controller restart | `docker exec` with the same wrapper |
| Tekton | Inside: injected `entrypoint` per step | Container log (pod log API) | Sidecars, stopped by image swap | None | Controller holds it; steps get mounted secrets only | Pod runs on without the controller | Kubernetes only |
| Argo emissary | Inside: injected `argoexec emissary` | Container log (pod log API) | `wait` sidecar uploads artifacts | None | Artifact credentials in the `wait` sidecar | Pod runs on without the controller | Kubernetes only |
| OpenHands | Inside: action execution / agent server | Server streams events | In the same container | Ports exposed on the host, inbound | No runner identity in the sandbox | — | Same server everywhere |
| E2B `envd` | Inside: daemon | Process API streams | In the sandbox | PTY over the API, through E2B's proxy | Per-sandbox access token | — | microVM; sidecar or entrypoint in Kubernetes projects |
| Daytona | Inside: sandbox daemon; lifecycle by polling runners | Daemon streams | In the sandbox | Through the platform's proxy | Proxy adds authentication | — | Runners per region |
| Coder agent | Inside: workspace agent | Agent sends logs | In the workspace | Outbound tunnel (WireGuard over WebSocket), reconnecting PTY | Not kept: the token is in the workspace | Workspace keeps running; agent reconnects | Any workspace type |
| Gitpod `supervisor` | Inside: PID 1 | Supervisor API | In the workspace | Through the supervisor | — | — | Kubernetes |

## 17. Patterns DESIGN.md §6.9 relies on

1. **Two families, and the CI services sit in both.** Services that run an unmodified image the
   user chose execute from outside, through the runtime's API (GitHub Actions, ARC, GitLab,
   Jenkins). Services that need a contract inside the container inject a binary as its
   entrypoint (Tekton, Argo, Buildkite on Kubernetes, CircleCI since 3.1, Gitpod), and the
   sandboxes run a daemon inside (OpenHands, E2B, Daytona, Coder).
2. **Exec through the Kubernetes API is the known weak spot, and each service works around it in
   its own way.** CircleCI left it for an in-container PID 1, citing errors, lost idempotency on
   disconnection and API-server load. GitLab kept it but stopped trusting the stream: output goes
   to a file in the pod and is read from an offset. Jenkins never trusted it: output and exit code
   go to files. ARC and the Jenkins plugin still need `pods/exec`, and CircleCI and GitLab still
   list it.
3. **The live log comes from a file or from the container's own output, read by offset or by the
   log API, never from the exec stream alone.** GitLab's `read-logs` resumes by byte offset.
   Tekton, Argo and CircleCI's log sidecar read the pod log API. Jenkins reads a log file.
4. **Helpers live in another container that shares the job's network and volumes.** GitLab's
   helper container, Argo's `wait` sidecar, Buildkite's `agent` and `checkout` containers,
   CircleCI's log sidecar, service containers everywhere. Within a pod they share `localhost`.
5. **A credential is kept from the job by putting it in a different container or process, not
   by hiding it in the same one.** Argo's artifact credentials are in `wait`, Buildkite's agent
   token is in `agent`, GitHub's and GitLab's runner credentials stay on the host. Coder and the
   sandboxes do not try, because their sandbox belongs to the user.
6. **Only GitLab's terminal and CircleCI's SSH rerun need inbound access.** Coder and Daytona
   bring interactive traffic in through an outbound connection or a platform-operated relay.
   That is the shape DESIGN.md §12.2's tunnel already assumes.
7. **A job that survives its runner keeps its state in the job's environment.** Jenkins' durable
   tasks and GitLab's attach strategy keep output and exit codes in files next to the job, and
   Tekton and Argo order steps by files in the pod. A runner that restarts reads them again.
