# Story 16.3: Rename Output Directory

Status: ready-for-dev

## Story

As a user,
I want the session output directory to be called `/workspace/outputs/`,
so that naming is consistent and clear (plural, matching "outputs" concept).

## Acceptance Criteria

1. **AC1: Entrypoint** — In `docker/base/entrypoint.sh`, the `mkdir` line creates `/workspace/outputs` instead of `/workspace/output`.

2. **AC2: Context service** — All references to `/workspace/output/` in `SessionContextService` updated to `/workspace/outputs/`.

3. **AC3: No backward compat needed** — Each session gets a fresh container, so no migration of existing containers required.

## Tasks / Subtasks

- [ ] Task 1: Update entrypoint.sh (AC: #1)
  - [ ] 1.1 Change `mkdir -p "$WORKSPACE/repo" "$WORKSPACE/output"` → `"$WORKSPACE/outputs"`
- [ ] Task 2: Update SessionContextService (AC: #2)
  - [ ] 2.1 In `build_workspace_layout` method, change `/workspace/output/` → `/workspace/outputs/` (3 occurrences)
- [ ] Task 3: Verify no other references
  - [ ] 3.1 Search codebase for `/workspace/output` (without trailing s) — update any remaining references

## Dev Notes

### entrypoint.sh — Line 39

Current:
```bash
mkdir -p "$WORKSPACE/repo" "$WORKSPACE/output"
```

Change to:
```bash
mkdir -p "$WORKSPACE/repo" "$WORKSPACE/outputs"
```

### SessionContextService — build_workspace_layout (lines 318-335)

Three references to update:

1. Line 324:
```ruby
lines << "- **`/workspace/output/`** — Put all results..."
```
→
```ruby
lines << "- **`/workspace/outputs/`** — Put all results..."
```

2. Line 328:
```ruby
"...copy it to `/workspace/output/` with the full content..."
```
→
```ruby
"...copy it to `/workspace/outputs/` with the full content..."
```

3. There's also a reference around line 416 in the non-interactive prompt section:
```ruby
lines << "4. Save all results to `/workspace/output/` so they persist after the session"
```
→
```ruby
lines << "4. Save all results to `/workspace/outputs/` so they persist after the session"
```

### No Test Changes Needed

This is a string/config change only. No unit tests reference the output directory path directly.

### Files to Touch

- `docker/base/entrypoint.sh` — line 39
- `web/app/services/session_context_service.rb` — 3 occurrences in `build_workspace_layout` + non-interactive prompt

### What NOT To Change

- Do NOT create the `collect_outputs` method — that's Story 16.4
- Do NOT modify Dockerfile

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.3]
- [Source: docker/base/entrypoint.sh — line 39]
- [Source: web/app/services/session_context_service.rb — build_workspace_layout lines 318-335]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
