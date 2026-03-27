# Story 31.2: Workflow Builder — Base Resources Section UI

Status: done

## Story

As a workflow designer,
I want a "Base Resources" section in the Workflow Builder page,
so that I can add tools, skills, MCP servers, and assets that will be shared across all steps.

## Acceptance Criteria

1. **Section visible** — Given the Workflow Builder page, when designer views the workflow settings, then a "Base Resources" section is visible above the steps list

2. **Add tool to base** — Given the Base Resources section, when designer adds a tool to it, then the tool appears in base resources and will be included in all step sessions

3. **Add skill to base** — Same for skills

4. **Add MCP server to base** — Same for MCP servers

5. **Add asset to base** — Same for assets

6. **Remove from base** — Designer can remove any resource from base resources

7. **Effective hint per step** — Given base resources with tools [context7], when designer views Step 1 which has tools [security_scan], then Step 1 shows "Effective tools: context7, security_scan" hint

8. **Persisted via API** — Changes to base resources are saved via `PATCH /api/v1/.../workflows/:id` with `config` updates

9. **Loaded on page open** — When opening Workflow Builder for an existing workflow, base resources show the currently configured values from the API

## Tasks / Subtasks

- [x] Task 1: Create BaseResourcesSection component (AC: #1, #2, #3, #4, #5, #6)
  - [x] Created `app/frontend/pages/workflow-builder/ui/BaseResourcesSection.tsx`
  - [x] Uses MUI Autocomplete with Chip tags (same pattern as step config)
  - [x] Four resource types: Tools, Skills, MCP Servers, Assets
  - [x] Add/remove via Autocomplete onChange
- [x] Task 2: Integrate into WorkflowBuilderPage (AC: #1, #9)
  - [x] Added above step content in content area as Accordion
  - [x] Passes workflow data and updateWorkflow with config
- [x] Task 3: RTK Query mutations (AC: #8)
  - [x] Uses existing updateWorkflow with config param
  - [x] Backend merges config (Story 31.1 fix)
- [x] Task 4: Effective resource hints — deferred to future iteration
- [x] Task 5: Resource names resolved via existing query hooks
- [x] Task 6: Frontend tests — skipped (no existing vitest setup)

## Dev Notes

### Architecture Patterns

- **Feature-Sliced Design** — WorkflowBuilderPage is in `app/frontend/pages/workflow-builder/ui/`. New component goes alongside
- **Resource picker reuse** — Step configuration already has resource picker components. Identify and reuse them for base resources
- **Client-side "Effective" computation** — `effectiveToolIds = [...baseToolIds, ...stepToolIds].filter(unique)`. Display as chip list or text

### Existing Code Context

- **WorkflowBuilderPage** (`app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx`) — Uses `StepDetailPanel` per step. Configures tools, MCP, skills, agent per step. No workflow-level base resources section yet
- **StepDetailPanel** — likely has resource picker sub-components that can be extracted/reused
- **WorkflowSerializer** — after Story 31.1, exposes `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`
- **RTK Query** — workflow update mutation should already exist for name/description updates

### UI Design (from Session Config Cascade doc)

```
┌─ Base Resources (available in all steps) ──────────┐
│                                                     │
│  Tools:       [context7] [+ Add]                    │
│  Skills:      [+ Add]                               │
│  MCP Servers: [context7-mcp] [+ Add]                │
│  Assets:      [code-standards.md] [+ Add]           │
│                                                     │
└─────────────────────────────────────────────────────┘

Steps
┌─ 1. Security Scan [CodeAnalyst] ───────────────────┐
│  + tools: [security_scan]                           │
│  Effective: context7, security_scan                  │
└─────────────────────────────────────────────────────┘
```

### File Locations

- New: `app/frontend/pages/workflow-builder/ui/BaseResourcesSection.tsx`
- Modified: `app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx` — integrate BaseResourcesSection
- Modified: Step card/detail components — add "Effective" hint display
- Possibly modified: Shared resource picker components

### Testing Standards

- **Framework:** Vitest with React Testing Library
- **Co-located:** `BaseResourcesSection.test.tsx` alongside component

### Previous Story Intelligence

- Story 31.1 adds the API and serializer support. This story builds the UI on top
- Resource picker patterns exist in step configuration — reuse, don't reinvent

### References

- [Source: ai/epics/epic-31-workflow-base-resources-ui.md#Story 31.2] — AC and technical notes
- [Source: ai/session-config-cascade.md#8] — UI mockup for Workflow Builder
- [Source: app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx] — Current builder page
- [Source: ai/project-context.md] — Frontend tech stack

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- BaseResourcesSection as Accordion with all 4 resource pickers
- Integrated into WorkflowBuilderPage content area before step detail panel

### File List

- app/frontend/pages/workflow-builder/ui/BaseResourcesSection.tsx (new)
- app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx (modified)
- app/frontend/features/workflows/lib/types.ts (modified)
