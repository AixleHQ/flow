# Epic 14: Container Runtime (Phase 0)

Introduce a pluggable container runtime so execution can run on Docker or Kubernetes Pods without changing workflow behavior.

**Phase:** 0 (Infrastructure foundation)

**User Outcome:** Same execution experience across Docker and Kubernetes.

## Story 14.1: Pluggable Runtime with Kubernetes Pods

**Acceptance Criteria:**
- Runtime abstraction supports Docker and Kubernetes Pods
- Path-based routing works for ttyd and watcher
- Artifacts can be collected from volume-backed files
- Runtime selection is configurable
