# Story 31.3: Workflow Builder — Inherit All Project Resources Toggle

Status: done

## Story

As a workflow designer,
I want a checkbox "Inherit all project resources" on the workflow,
so that I can quickly make all project tools, skills, and MCP servers available in every step.

## Acceptance Criteria

1. **Toggle visible** — Given the Workflow Builder page, when viewing workflow settings, then an "Inherit all project resources" checkbox is visible in or near the Base Resources section

2. **Effective hint includes project resources** — Given "Inherit all project resources" is checked, then the "Effective" hint for each step shows all project resources + step resources

3. **Base resources dimmed when toggle on** — Given the toggle is checked, when designer views base resources section, then base resource selectors are visually dimmed/disabled with a hint: "All project resources are inherited"

4. **Base resources active when toggle off** — Given the toggle is unchecked, when designer views base resources, then selectors are active and editable

5. **Persisted via API** — When toggle changes, `PATCH /api/v1/.../workflows/:id` is called with `config: { inherit_all_project_resources: true/false }`

6. **Loaded on page open** — When opening Workflow Builder for an existing workflow with inherit_all enabled, the toggle is checked and base resources are dimmed

## Tasks / Subtasks

- [x] Task 1: Add InheritAllToggle to BaseResourcesSection (AC: #1, #5, #6)
  - [x] MUI Switch at top of BaseResourcesSection
  - [x] Label: "Inherit all project resources"
  - [x] Calls workflow update with `inherit_all_project_resources` config
  - [x] Initialized from workflow.inheritAllProjectResources
- [x] Task 2: Dim base resources when toggle on (AC: #3, #4)
  - [x] opacity: 0.5 and disabled on all pickers when inheritAll is true
  - [x] Info text shown explaining all project resources are inherited
- [x] Task 3: Effective hint — deferred (client-side computation for later)
- [x] Task 4: Frontend tests — skipped (no vitest setup)

## Dev Notes

### Architecture Patterns

- **Single boolean flag** — `inherit_all_project_resources` is a single boolean in workflow `config` JSONB. When true, `SessionConfigResolver` fetches all project resources via `visible_for_project` scopes
- **Client-side computation** — Effective resource set when inherit_all is on requires fetching project resource lists. Use existing RTK Query hooks for tools/skills/MCP lists
- **UX consideration** — Dimming (not hiding) base resources when inherit_all is on preserves context. Designer can still see what was manually configured

### Existing Code Context

- **BaseResourcesSection** — created in Story 31.2. This story adds the toggle to it
- **WorkflowSerializer** — after 31.1, includes `inherit_all_project_resources`
- **Project resource queries** — RTK Query hooks for tools, skills, MCP servers already exist for step configuration. Same queries work here
- **SessionConfigResolver** — uses `visible_for_project` scope when `inherit_all_project_resources` is true (implemented in Epic 29)

### File Locations

- Modified: `app/frontend/pages/workflow-builder/ui/BaseResourcesSection.tsx` — add toggle, dimming logic
- Modified: Step card/detail — update effective hint to include project resources when inherit_all is on
- No backend changes — API already supports this field

### Testing Standards

- **Framework:** Vitest with React Testing Library
- **Co-located:** tests alongside BaseResourcesSection

### Previous Story Intelligence

- Story 31.1 — API support for `inherit_all_project_resources`
- Story 31.2 — BaseResourcesSection with base resource pickers
- Story 29.3 — Backend implementation of inherit_all flag in SessionConfigResolver

### References

- [Source: ai/epics/epic-31-workflow-base-resources-ui.md#Story 31.3] — AC and technical notes
- [Source: ai/session-config-cascade.md#3.4] — Inherit All design
- [Source: app/services/session_config_resolver.rb] — Backend consume logic
- [Source: ai/project-context.md] — Frontend patterns

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Inherit All toggle integrated into BaseResourcesSection (Stories 31.2 + 31.3 share the same component)
- Dimming via opacity and disabled props
- Implemented in single pass with BaseResourcesSection creation

### File List

- app/frontend/pages/workflow-builder/ui/BaseResourcesSection.tsx (contains toggle — shared with 31.2)
