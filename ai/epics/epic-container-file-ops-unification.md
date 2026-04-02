# Epic: Container File Operations Unification

**Status: DONE**

## Problem Statement

Container runtimes (Docker & Kubernetes) used three different file transfer mechanisms:
- **Base64** via `exec echo | base64 -d > file` — broke on large files due to shell argument limits
- **Tar stream** via Docker Archive API or `exec tar` — reliable, works for any file size
- **tmpfs** mounts — added complexity, broke tar-based reads, necessitated `cat` fallback

## Result

All file I/O now goes through a clean, unified API on `BaseRuntime`:

```
write_file(id, path, content, mode:, uid:, gid:) → true/false
read_file(id, path)                              → String | nil
```

Both Docker and Kubernetes runtimes implement these via tar streams.
uid/gid are embedded in tar headers — no separate `chown` exec needed.

### What was removed
- `copy_to`, `store_file`, `copy_from` — legacy method aliases
- All base64 file transfer
- All tmpfs / emptyDir(Memory) mounts
- Duplicate `extract_from_tar` in KubernetesRuntime
- `cat` fallback in `read_file_from_container`
- `chown` exec calls after file writes
- `tmpfs_paths` from all adapters

### Final API surface (BaseRuntime)

| Category | Method | Signature |
|----------|--------|-----------|
| Lifecycle | `pull_image` | `(image)` → Hash |
| | `create_container` | `(spec)` → handle |
| | `start_container` | `(id)` → handle |
| | `wait_for_ready` | `(id, ports=[])` → true |
| | `stop_container` | `(id, timeout=nil)` → void |
| | `remove_container` | `(id, options={})` → void |
| | `remove_image` | `(image)` → void (no-op by default) |
| Execution | `exec` | `(id, cmd, opts={})` → [stdout, stderr, exit_code] |
| File I/O | `write_file` | `(id, path, content, mode:, uid:, gid:)` → bool |
| | `read_file` | `(id, path)` → String \| nil |
| Introspection | `resolve_container` | `(id)` → handle |
| | `container_identifier` | `(container)` → String |
| | `wait_container` | `(id, timeout=nil)` → Hash |
| | `container_logs` | `(id, opts={})` → Hash |

## Stories (all completed)

1. **Unify DockerRuntime#copy_to via tar** — replaced base64 with Docker Archive API
2. **Migrate services off direct base64** — AgentCredentialsService, BmadMethodInjector
3. **Remove tmpfs** — adapters, strategies, KubernetesRuntime
4. **Consolidate BaseRuntime API** — single `write_file` + `read_file`
5. **Add uid/gid to tar headers** — removed chown exec calls
6. **Simplify SessionContextService** — removed fallback chains
7. **Update tests** — aligned all test stubs and expectations
