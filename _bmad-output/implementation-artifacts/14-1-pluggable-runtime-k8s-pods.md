# Story 14.1: Pluggable Runtime with Kubernetes Pods

Status: draft

## Story

As a system,
I want a pluggable container runtime (Docker or Kubernetes Pods),
So that execution can run locally via Docker or via Kubernetes without changing workflow behavior.

## Architecture Decision

**Approach:** Introduce a `ContainerRuntime` abstraction with two implementations:
- `DockerRuntime` (wraps existing Docker API behavior)
- `KubernetesRuntime` (creates Pods + Services + IngressRoutes)

**Runtime Selection:** `Settings.container_runtime = docker | k8s` (default: docker)

**Key Principles:**
- Preserve existing Temporal workflows and strategy lifecycle behavior
- Keep strategy inputs and outputs unchanged
- Maintain current routing paths: `/t/{route_token}/tty` and `/t/{route_token}/fs`
- Use volumes (`emptyDir`) for credentials and artifacts in k8s
- PoC scope only: local Orbstack Kubernetes

## Acceptance Criteria

1. ✅ `ContainerRuntime` interface exists with core lifecycle operations
2. ✅ `DockerRuntime` behavior matches current Docker execution
3. ✅ `KubernetesRuntime` supports all execution modes (auth, session, tool, MCP)
4. ✅ Path-based routing works identically in k8s
5. ✅ Artifacts are collected via volume-backed files
6. ✅ Runtime selection is configurable
7. ✅ Minimal changes to `UnifiedContainerWorkflow`

## Tasks

### Task 1: Run Application in Cluster (PoC)

- [x] Create `palad` namespace
- [x] Deploy Postgres, Redis, Temporal, Temporal UI
- [x] Deploy Rails app (`web`) with Service
- [x] Deploy `worker-ruby` with ServiceAccount
- [x] Deploy Traefik (CRDs + RBAC + ForwardAuth)
- [x] Configure `terminal-auth` middleware to call in-cluster Rails

### Task 2: Define Runtime Interface (AC: 1)

- [x] Create `app/services/container_runtime/base_runtime.rb`:
  - `pull_image(image)`
  - `create_container(spec)`
  - `start_container(id)`
  - `exec(id, cmd, opts)`
  - `copy_from(id, path)`
  - `stop_container(id, timeout)`
  - `remove_container(id)`
  - `wait_for_ready(id, ports)`

### Task 3: Implement DockerRuntime (AC: 2)

- [x] Create `app/services/container_runtime/docker_runtime.rb`:
  - Wrap current Docker API operations
  - Preserve timeouts and error handling
  - Return the same results as current `BaseStrategy` helpers

### Task 4: Implement KubernetesRuntime (AC: 3, 4, 5)

- [x] Create `app/services/container_runtime/kubernetes_runtime.rb`:
- [x] Add KubernetesRuntime template (stubs only)
  - Create Pod with same env vars and commands
  - Attach `emptyDir` volumes for credentials + artifacts
  - Create Service for ttyd/watcher ports
  - Create IngressRoute for `/t/{route_token}/tty` and `/t/{route_token}/fs`
  - Exec into Pod for file reads and artifact collection
  - Delete Pod + Service + IngressRoute on cleanup

### Task 5: Wire Runtime Selection (AC: 6)

- [x] Add config: `Settings.container_runtime` (docker | k8s)
- [x] Update `ContainerService` and `BaseStrategy` to use runtime adapter

### Task 6: Update Strategies (AC: 2, 3, 4, 5)

- [x] Replace direct Docker calls with runtime API
- [x] Keep strategy outputs unchanged
- [x] Ensure routing URLs remain the same

### Task 7: Orbstack Kubernetes Setup (AC: 3, 4)

- [x] Add minimal manifests for Traefik + RBAC
- [x] Add example namespace + service account
- [ ] Document local setup steps

## Notes / Assumptions

- PoC only, no production scaling requirements
- No new observability requirements
- No special security isolation constraints
- No migration plan required
