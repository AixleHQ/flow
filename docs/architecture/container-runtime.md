# Container Runtime & Service

This document covers two related but distinct angles of the container execution
stack:

1. **The pluggable container runtime** — an abstraction that lets the same
   Temporal workflows and container strategies run on either Docker or
   Kubernetes Pods (Epic 14 PoC, targeting local Orbstack Kubernetes).
2. **The ContainerService refactoring (historical record)** — a phase-based
   redesign of `ContainerService`, the strategy hierarchy, and the Temporal
   activities/workflow that unified agent and tool execution.

The runtime abstraction is the forward-looking design. The ContainerService
refactoring is preserved below as a period snapshot; its naming (notably
`ToolExecutionStrategy`) is period-accurate and left as written.

## Table of contents

- [Container Runtime: Pluggable Docker + Kubernetes Pods](#container-runtime-pluggable-docker--kubernetes-pods)
  - [Overview](#overview)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
  - [Current Execution Model (Baseline)](#current-execution-model-baseline)
  - [Target Architecture](#target-architecture)
  - [Kubernetes Runtime Model](#kubernetes-runtime-model)
  - [Strategy Mapping](#strategy-mapping)
  - [Temporal Workflow Compatibility](#temporal-workflow-compatibility)
  - [Data & Artifacts](#data--artifacts)
  - [Error Handling](#error-handling)
  - [PoC Deployment (Orbstack)](#poc-deployment-orbstack)
  - [Access Paths: `/t/{route_token}`](#access-paths-troute_token)
  - [URL Generation for TTY + FS](#url-generation-for-tty--fs)
  - [Traefik Authentication for `/t/*` Paths](#traefik-authentication-for-t-paths)
  - [Run the Full Application in Cluster (PoC Steps)](#run-the-full-application-in-cluster-poc-steps)
  - [Registering New Containers (K8s API Calls)](#registering-new-containers-k8s-api-calls)
  - [Calling the Kubernetes API (Credentials & Access)](#calling-the-kubernetes-api-credentials--access)
  - [Open Questions (PoC)](#open-questions-poc)
  - [Implementation Notes](#implementation-notes)
  - [Acceptance Criteria Coverage](#acceptance-criteria-coverage)
- [ContainerService Refactoring (historical record)](#containerservice-refactoring-historical-record)
  - [Motivation](#motivation)
  - [Target Architecture](#target-architecture-refactoring)
  - [Components](#components)
  - [Implementation Order](#implementation-order)

---

# Container Runtime: Pluggable Docker + Kubernetes Pods

## Overview

This document defines the architecture for a pluggable container runtime that supports both Docker and Kubernetes Pods while preserving existing Temporal workflows and container strategy behavior. It targets a PoC scope running on local Orbstack Kubernetes.

## Goals

- Preserve current execution behavior (timeouts, signals, outputs, artifacts).
- Support both Docker and Kubernetes runtimes via a common interface.
- Keep all existing workflows and strategies intact with minimal changes.
- Maintain existing routing paths: `/t/{route_token}/tty` and `/t/{route_token}/fs`.
- Use volume-backed storage for credentials and artifacts in Kubernetes.

## Non-Goals

- Production-scale scheduling or high availability.
- Advanced observability, security hardening, or compliance.
- Multi-tenant isolation or namespace per customer.
- Migration plan or data backfill.

## Current Execution Model (Baseline)

- Temporal orchestrates workflow steps and timeouts.
- `ContainerService` executes lifecycle phases via strategies.
- Docker API is used directly for container creation, exec, and file extraction.
- Routing uses Traefik labels on containers.
- Artifacts are extracted before cleanup and stored in DB fields or results.

## Target Architecture

Introduce a runtime layer that abstracts container lifecycle operations.

### Runtime Abstraction

**Interface:** `ContainerRuntime`

Required operations:
- `pull_image(image)`
- `create_container(spec)`
- `start_container(id)`
- `exec(id, cmd, opts)`
- `copy_from(id, path)`
- `stop_container(id, timeout)`
- `remove_container(id)`
- `wait_for_ready(id, ports)`

### Implementations

- `DockerRuntime`: wraps existing Docker API calls.
- `KubernetesRuntime`: creates Pods + Services + IngressRoutes and uses exec/copy for artifacts.

### Runtime Selection

- Config: `Settings.container_runtime = docker | k8s`
- Default: `docker`

## Kubernetes Runtime Model

### Pod Layout

- Single main container (agent/tool image).
- `emptyDir` volume for home directories and artifacts.
- Command and env vars identical to Docker runtime.

### Volumes

- `emptyDir` mounted into:
  - `HOME_DIR` (agent credential locations)
  - `/workspace` (tool outputs)
  - any adapter-defined tmpfs paths (mapped to emptyDir)

### Networking

- Service for each Pod with ports:
  - `7681` (ttyd)
  - `4040` (watcher)
- IngressRoute rules (Traefik) per `route_token`:
  - `/t/{route_token}/tty` → service:7681
  - `/t/{route_token}/fs` → service:4040

### Execution Semantics

- `exec` maps to Kubernetes exec API.
- `copy_from` uses exec + tar (PoC) or kubectl cp.
- `wait_for_ready` polls Pod Ready + optional port checks.

### Cleanup

- Delete IngressRoute, Service, Pod (in that order).
- Artifact collection happens before deletion.

## Strategy Mapping

No strategy behavior changes; only runtime operations are swapped.

- `AgentAuthStrategy`:
  - Uses runtime for create/start/exec.
  - Generates routing via runtime in k8s.
  - Auth files read from volume-backed paths via `copy_from`.

- `AgentSessionStrategy`:
  - Credentials injected via `exec`.
  - Artifacts collected via `copy_from`.

- `ToolStrategy` (and subclasses `CustomToolStrategy` / `InternalToolStrategy`):
  - Tool files injected via `exec` (tar in).
  - Execution via `exec`.
  - Output files collected via `copy_from`.

## Temporal Workflow Compatibility

No change to:
- `ContainerWorkflow`
- Activity input/output schemas
- Signals: only `container_finished` exists as a `workflow_signal`. There is
  no `container_cancelled` signal — cancellation uses Temporal native
  cancellation (`Temporalio::Error.canceled?`).

## Data & Artifacts

- Credentials and output files remain in DB fields as today.
- Volume-backed files in k8s are temporary and extracted before cleanup.

## Error Handling

- Preserve existing `ContainerService::ExecutionError` behavior.
- Runtime exceptions wrap into existing Temporal error handling.
- Cleanup best-effort, ignore not-found on deletion.

See [Temporal error handling](./temporal-error-handling.md) for the shared
error-handling conventions.

## PoC Deployment (Orbstack)

### Required Components

- Orbstack Kubernetes cluster
- Traefik deployed with CRDs and RBAC
- Namespace for runtime resources

### Minimal Resources Created

- `Pod` per execution
- `Service` per execution (ttyd + watcher)
- `IngressRoute` per execution

## Access Paths: `/t/{route_token}`

**How access works:**
- For each agent container, create a Kubernetes `Service` exposing ports 7681 and 4040.
- Create a Traefik `IngressRoute` with two `PathPrefix` rules:
  - `/t/{route_token}/tty` → Service:7681
  - `/t/{route_token}/fs` → Service:4040
- This preserves the current frontend URLs and WebSocket behavior.

**Why this works:**
- Traefik already handles path-based routing; in k8s we replicate the current Docker label behavior via CRDs.
- `route_token` remains the stable external identifier.

### Local Access (Orbstack)

- Run Traefik in the local Orbstack cluster and expose it on the host (HTTP/WebSocket).
- The application continues to use `Settings.traefik.ws_base` for the base URL.
- Example (local): `Settings.traefik.ws_base = http://localhost:8080`.
- Resulting URLs:
  - `http://localhost:8080/t/{route_token}/tty/ws`
  - `http://localhost:8080/t/{route_token}/fs`

## URL Generation for TTY + FS

The application must keep the same URL structure as today.

**Generation rules:**
- Base URL: `Settings.traefik.ws_base`
- TTY: `/t/{route_token}/tty/ws`
- File watcher: `/t/{route_token}/fs`

**Source of truth:**
- The `AgentAuthStrategy` already builds these URLs.
- Only the base URL changes per environment (Docker vs k8s).

## Traefik Authentication for `/t/*` Paths

**Mechanism:** Traefik ForwardAuth middleware (`terminal-auth`).

**Flow:**
1. Client requests `/t/{route_token}/tty/ws` or `/t/{route_token}/fs`.
2. Traefik calls the ForwardAuth endpoint:
  - `GET /api/v1/internal/ws_auth`
  - Headers include `X-Forwarded-Uri` with the original path.
  - Cookies include the Rails session cookie (`_aixle_session`).
3. `WsAuthController` validates:
  - User is authenticated
  - User owns the terminal session for `route_token`
  - Session state is `started` or `running`
4. Traefik allows or denies the proxy based on status code.

**Required middleware on IngressRoute:**
- `terminal-auth` (ForwardAuth)
- `terminal-cors` (for watcher)
- `stripPrefix` (to remove `/t/{route_token}/tty|fs` before proxy)

**Kubernetes requirement:**
- IngressRoute must reference the same middleware as Docker labels do today.
- The ForwardAuth endpoint must be reachable from Traefik (same cluster or reachable service).

### ForwardAuth Reachability Options (PoC)

**Option A: Run Rails inside the cluster (selected)**
- Deploy Rails app as a Service in the same Orbstack cluster.
- Traefik ForwardAuth URL targets the in-cluster service:
  - `http://web.app.svc.cluster.local:4000/api/v1/internal/ws_auth`

## Run the Full Application in Cluster (PoC Steps)

1. **Create namespace**
  - `aixle` namespace for all services.

2. **Deploy core services**
  - Postgres
  - Redis
  - Temporal + Temporal UI

3. **Deploy Rails app (`web`)**
  - Build image with app code.
  - Create Deployment + Service (port 4000).
  - Provide env vars matching docker-compose.

4. **Deploy Temporal worker (`worker-ruby`)**
  - Same image as `web`.
  - Run worker command only.

5. **Deploy Traefik**
  - Enable CRDs and ForwardAuth middleware.
  - Expose Traefik via NodePort or LoadBalancer.

6. **Configure ForwardAuth middleware**
  - Use in-cluster URL: `http://web.app.svc.cluster.local:4000/api/v1/internal/ws_auth`.

7. **Configure Settings**
  - `Settings.traefik.ws_base` points to Traefik external URL.
  - `Settings.container_runtime = k8s`.

8. **Run a test session**
  - Start auth session → verify `/t/{route_token}/tty`.
  - Complete auth → verify credential extraction.

## Registering New Containers (K8s API Calls)

**What gets created per execution:**
1. `Pod` (main workload)
2. `Service` (ttyd + watcher ports)
3. `IngressRoute` (path routing)

**Kubernetes API operations:**
- `create_namespaced_pod`
- `create_namespaced_service`
- `create_namespaced_custom_object` (Traefik `IngressRoute` CRD)
- `delete_namespaced_custom_object`
- `delete_namespaced_service`
- `delete_namespaced_pod`

**Execution lifecycle:**
- Create Pod → wait for Ready → create Service → create IngressRoute
- On cleanup: remove IngressRoute → Service → Pod

## Calling the Kubernetes API (Credentials & Access)

### PoC (Local Orbstack)

- Use kubeconfig-based auth from the Rails container or host.
- Mount `$HOME/.kube/config` into the Rails container, or run Rails directly on host.
- Use a service account only if running inside the cluster.

### In-Cluster (Future-Ready)

- Create a ServiceAccount with RBAC permissions for:
  - Pods, Services
  - IngressRoute CRDs (Traefik)

**Required RBAC:**
- `pods`: create/get/list/watch/delete
- `services`: create/get/list/watch/delete
- `ingressroutes.traefik.io`: create/get/list/watch/delete

**How the app authenticates:**
- In-cluster: use projected service account token (standard Kubernetes client behavior).
- Out-of-cluster: use kubeconfig (local development).

## Open Questions (PoC)

- Final approach for `copy_from` (tar vs kubectl cp).
- Whether to cache images in local registry for performance.
- How to map tmpfs semantics to emptyDir for all adapters.

## Implementation Notes

- Keep Docker runtime as default during development.
- Add runtime as dependency in `BaseStrategy` (injected or singleton).
- Avoid changing existing strategy inputs/outputs.

## Acceptance Criteria Coverage

Mapped to Story 14.1 acceptance criteria.

---

# ContainerService Refactoring (historical record)

> **Historical record.** This section captures the phase-based refactoring of
> `ContainerService`, the strategy hierarchy, and the Temporal
> activities/workflow as a period snapshot. Naming here (notably
> `ToolExecutionStrategy`) is period-accurate and preserved as originally
> written; it may differ from the current runtime-abstraction naming used
> above.

## Motivation

Current architecture has:
- 6 activity classes (3 agent + 3 tool) with significant duplication
- Timeouts scattered between workflow, ContainerService, and Settings
- `AgentSessionStrategy` fragile inheritance from `AgentAuthStrategy` (`.map!` hacks)
- Signal-waiting logic hardcoded in `AgentContainerWorkflow`
- Two separate workflows (`AgentContainerWorkflow`, `ToolExecutionWorkflow`) doing the same thing

<a id="target-architecture-refactoring"></a>
## Target Architecture

```
ContainerWorkflow (generic, one for all)
  → resolve_manifest activity → phase configs from strategy
  → for each phase:
      → container_phase activity → ContainerService.new(strategy:, state:).run_phase(phase)
      → if await_signal → workflow waits for signal
  → ensure: cleanup phase activity (always runs)

ContainerService — thin phase runner, delegates before/phase/after to strategy
Strategy — defines behavior + phase_config (timeouts, signals, retries)
```

## Components

### 1. ContainerService (phase runner)

No timeout logic. No signal logic. Accumulates state from strategy return values.

```ruby
class ContainerService
  PHASES = %i[pull_image create_container start_container exec cleanup].freeze

  def initialize(strategy:, state: {})
    @strategy = strategy
    @state = state.deep_symbolize_keys
  end

  def run_phase(phase)
    @state.merge!(invoke(:"before_#{phase}"))
    @state.merge!(invoke(phase))
    @state.merge!(invoke(:"after_#{phase}"))
    @state
  end

  private

  def invoke(hook)
    return {} unless @strategy.respond_to?(hook)
    result = @strategy.public_send(hook, **@state)
    result.is_a?(Hash) ? result.deep_symbolize_keys : {}
  end
end
```

### 2. Strategy — phase_config

Each strategy defines per-phase metadata. The workflow uses this to set Temporal timeouts, decide on signal-waiting, and configure retries.

```ruby
# BaseStrategy
def phase_config(phase)
  { timeout: 300 }
end

# AgentAuthStrategy
def phase_config(phase)
  case phase
  when :pull_image    then { timeout: 600 }
  when :exec          then { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
  when :cleanup       then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
  else                     { timeout: 300 }
  end
end

# AgentSessionStrategy
def phase_config(phase)
  case phase
  when :pull_image    then { timeout: 600 }
  when :exec
    if non_interactive?
      { timeout: 85_800 }
    else
      { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
    end
  when :cleanup       then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
  else                     { timeout: 300 }
  end
end

# ToolExecutionStrategy
def phase_config(phase)
  case phase
  when :exec    then { timeout: [input[:timeout] || 300, 1800].min }
  when :cleanup then { timeout: 60, always: true }
  else               { timeout: 120 }
  end
end
```

### 3. Strategy inheritance (agent)

**Before:**
```
BaseStrategy
├── AgentAuthStrategy
│   └── AgentSessionStrategy (inherits auth, overrides with .map! hacks)
└── ToolExecutionStrategy
```

**After:**
```
BaseStrategy
├── AgentBaseStrategy (common: traefik, env vars, naming, validate, mark_session)
│   ├── AgentAuthStrategy (session_type=auth_setup, extract credentials)
│   └── AgentSessionStrategy (session_type=agent_session, load credentials, collect logs)
└── ToolExecutionStrategy
```

`AgentBaseStrategy` contains:
- `validate_input!`
- `resolve_image` (AGENT_IMAGES lookup)
- `build_base_env_vars` (common env: USER_ID, AGENT_TYPE, SESSION_ID, ROUTE_TOKEN, ports)
- `build_traefik_labels`
- `build_host_config` with tmpfs
- `build_exposed_ports`
- `mark_session_running`
- `services_ports`
- Traefik URL helpers

### 4. Activities

Single activity class (down from 6):

**`Activities::Container::PhaseActivity`** — runs a single phase:
```ruby
def run(input)
  strategy = resolve_strategy(input)
  state = (input.state || {}).deep_symbolize_keys
  service = ContainerService.new(strategy: strategy, state: state)
  service.run_phase(input.phase.to_sym)
end
```

### 5. Manifest — computed by caller, passed as workflow input

`phase_config` is a pure function (no DB, no IO), so manifest is built
before starting the workflow by the caller (`SessionService`), via
`build_manifest` on the strategy (defined in `BaseStrategy`):

```ruby
# SessionService (manifest built from strategy#build_manifest)
def start_session(session:)
  strategy = session.strategy
  manifest = strategy.build_manifest  # { phases: { pull_image: { timeout: 600 }, ... } }

  TemporalService.start_workflow(
    container_workflow,
    { session_id: session.id, manifest: manifest }
  )
end
```

This avoids an extra activity just to read config.

### 6. Workflow (generic)

One workflow for all container types. Manifest comes from input.

```ruby
class ContainerWorkflow < Base
  workflow_signal
  def container_finished
    @signals[:container_finished] = true
  end

  def run(input)
    @signals = {}
    manifest = input.manifest
    context = {}
    execution_error = nil

    phases = ContainerService::PHASES - [:cleanup]
    phases.each do |phase|
      config = manifest[phase]
      context = execute_activity(:container_phase,
        { phase: phase, context: context, **input },
        start_to_close_timeout: config[:timeout]
      )
      if config[:await_signal]
        wait_for_signal(config[:await_signal], config[:signal_timeout])
      end
    end
  rescue => e
    execution_error = e.message
  ensure
    cleanup_config = manifest[:cleanup]
    execute_activity(:container_phase,
      { phase: :cleanup, context: context, error: execution_error, **input },
      start_to_close_timeout: cleanup_config[:timeout],
      retry_policy: build_retry(cleanup_config[:retry])
    )
  end
end
```

### 7. State between activities — explicit contracts

No magic context hash. Each strategy method declares its inputs via **keyword args** and returns a **Hash** of what it produced.

`ContainerService` accumulates state by merging return values:
```ruby
def run_phase(phase)
  @state.merge!(invoke(:"before_#{phase}"))
  @state.merge!(invoke(phase))
  @state.merge!(invoke(:"after_#{phase}"))
  @state
end

def invoke(hook)
  return {} unless @strategy.respond_to?(hook)
  result = @strategy.public_send(hook, **@state)
  result.is_a?(Hash) ? result : {}
end
```

Strategy methods use `**_` to swallow state they don't need:
```ruby
# Declares: needs container_id, produces: exit_code, stdout, stderr, ...
def exec(container_id:, **)
  container = resolve_container(container_id)
  # ...
  { exit_code: 0, stdout: "...", stderr: "" }
end

# Declares: needs nothing extra, produces: image, env_vars, labels, ...
def before_create_container(**)
  { image: resolve_image, env_vars: build_env_vars, labels: build_labels, ... }
end
```

Key state fields (flow between activities):
- `image:` — set by `pull_image` or `before_create_container`
- `container_id:` — set by `create_container`
- `session_id:` — passed from workflow input
- `error:` — set by workflow on failure, passed to cleanup

### 8. Files to change

**New:**
- `app/services/container_strategies/agent_base_strategy.rb`
- `app/temporal/activities/container/phase_activity.rb`
- `app/temporal/workflows/container_workflow.rb`

**Rewrite:**
- `app/services/container_service.rb` — thin phase runner
- `app/services/container_strategies/agent_auth_strategy.rb` — inherit AgentBaseStrategy
- `app/services/container_strategies/agent_session_strategy.rb` — inherit AgentBaseStrategy (not Auth)

**Remove:**
- `app/temporal/activities/agent/pull_image_activity.rb`
- `app/temporal/activities/agent/execute_container_activity.rb`
- `app/temporal/activities/agent/cleanup_container_activity.rb`
- `app/temporal/activities/tool/pull_image_activity.rb`
- `app/temporal/activities/tool/execute_container_activity.rb`
- `app/temporal/activities/tool/cleanup_container_activity.rb`
- `app/temporal/workflows/agent_container_workflow.rb`

**Update:**
- `app/temporal/workflows.yml` — single container_workflow entry
- `app/services/session_service.rb` — start new workflow (build manifest from strategy)
- `app/services/container_strategies/base_strategy.rb` — remove phase logic that moves to service

## Implementation Order

1. Create `AgentBaseStrategy`, extract shared code
2. Refactor `AgentAuthStrategy` → inherit `AgentBaseStrategy`
3. Refactor `AgentSessionStrategy` → inherit `AgentBaseStrategy` (not Auth)
4. Rewrite `ContainerService` as thin phase runner
5. Adapt strategies to new phase names (pull_image, create_container, start_container, exec, cleanup)
6. Add `phase_config` to all strategies
7. Create the single new `PhaseActivity` (manifest is computed by the caller per §5 — no resolve-manifest activity)
8. Create generic `ContainerWorkflow`
9. Update `workflows.yml` and `SessionService`
10. Remove old activities and workflows
11. Update tests
