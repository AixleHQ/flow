# Story 33.3: Hide BMAD Files in VS Code

Status: ready-for-dev

## Story

As a **developer**,
I want BMAD internal files hidden from the VS Code file explorer,
so that my workspace stays clean and I only see my project files.

## Acceptance Criteria

1. **Given** BMAD is installed in the container
   **When** `BmadMethodInjector#hide_bmad_in_vscode` is called
   **Then** `.vscode/settings.json` includes `files.exclude` entries for `_bmad`, `_bmad-output`, `.cursor/skills`, `.claude/skills`, `.agents/skills`, `.gemini/skills`

2. **Given** a `.vscode/settings.json` already exists with other settings
   **When** BMAD exclude entries are added
   **Then** existing settings are preserved and BMAD entries are merged in

3. **Given** no `.vscode/settings.json` exists
   **When** BMAD exclude entries are added
   **Then** a new `.vscode/settings.json` is created with only the BMAD exclude entries

## Tasks / Subtasks

- [ ] Task 1: Implement `hide_bmad_in_vscode` in BmadMethodInjector (AC: #1–#3)
  - [ ] Define `BMAD_HIDDEN_PATHS` constant with all 6 paths
  - [ ] Read existing `/workspace/.vscode/settings.json` via `runtime.exec(container, ["cat", path])`
  - [ ] If file exists: JSON.parse, deep merge `files.exclude`, write back
  - [ ] If file does not exist (exit_code != 0): create new JSON with only `files.exclude`
  - [ ] Write via `runtime.exec(container, ["sh", "-c", "mkdir -p ... && cat > ..."])` or echo redirect
- [ ] Task 2: Write unit tests (AC: #1–#3)
  - [ ] Test merge with existing settings preserves other keys
  - [ ] Test creation when no settings file exists
  - [ ] Test all 6 BMAD paths are in files.exclude

## Dev Notes

- **Read file pattern:** `BaseStrategy#read_file_from_container` — `runtime.exec(container, ["cat", path])`, returns `nil` if exit_code non-zero
- **Write file:** Use `runtime.exec(container, ["sh", "-c", "mkdir -p /workspace/.vscode && echo '#{json}' > /workspace/.vscode/settings.json"])`
  - Escape single quotes in JSON or use heredoc approach
- **Hidden paths constant:**
  ```ruby
  BMAD_HIDDEN_PATHS = %w[
    _bmad
    _bmad-output
    .cursor/skills
    .claude/skills
    .agents/skills
    .gemini/skills
  ].freeze
  ```
- This method is called within `BmadMethodInjector#inject!` after `run_bmad_install` (Story 33.2)

### Project Structure Notes

- Added to existing `app/services/bmad_method_injector.rb` (created in Story 33.2)
- VS Code Server is already running in containers (Epic 15) — settings.json changes take effect immediately

### References

- [Source: app/services/container_strategies/base_strategy.rb#L170-175] — read_file_from_container pattern
- [Source: ai/bmad-method-checkbox-integration.md#5.6] — PRD VS Code settings spec
- [Source: ai/epics/epic-33-bmad-standalone-session.md#Story-33.3] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
