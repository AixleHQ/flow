# Container Runtime Architecture: Pluggable Docker + Kubernetes Pods (Epic 14)

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

- `ToolExecutionStrategy`:
  - Tool files injected via `exec` (tar in).
  - Execution via `exec`.
  - Output files collected via `copy_from`.

## Temporal Workflow Compatibility

No change to:
- `UnifiedContainerWorkflow`
- Activity input/output schemas
- Signals (`container_finished`, `container_cancelled`)

## Data & Artifacts

- Credentials and output files remain in DB fields as today.
- Volume-backed files in k8s are temporary and extracted before cleanup.

## Error Handling

- Preserve existing `ContainerService::ExecutionError` behavior.
- Runtime exceptions wrap into existing Temporal error handling.
- Cleanup best-effort, ignore not-found on deletion.

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
