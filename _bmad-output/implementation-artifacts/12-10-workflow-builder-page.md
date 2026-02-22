# Story 12.10: Workflow Builder Page

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a company admin or project collaborator,
I want the Workflow Builder page to be connected to real API endpoints and display all step configuration fields,
so that I can visually build workflow steps with real agents, sub-steps, asset specs, and tools.

## Acceptance Criteria

1. **AC1: Load workflow from API** — On mount, fetch workflow by `workflowId` from route params. Use `scopeType` from response to determine company vs project context. Display real `name` and `description` in the header. Show `CircularProgress` while loading. Show "Workflow not found" if 404.

2. **AC2: Load steps from API** — Fetch steps for the workflow using `useGetCompanyStepsQuery({ workflowId })` or `useGetStepsQuery({ projectId, workflowId })` based on scope. Render in sidebar ordered by `position`. Each step card shows: position number, name, agent name (from nested data or "No agent"), `allowNonInteractive` badge.

3. **AC3: Real agent picker** — Replace hardcoded `AGENT_OPTIONS` with agents from `useGetCompanyAgentsQuery()`. Agent select dropdown shows real agent names. Selecting an agent saves immediately via step update mutation. Show "No agent" option.

4. **AC4: Step CRUD via API** — "Add Step" calls `createCompanyStep` / `createStep` mutation with auto-assigned next position. Step field changes (name, instructions, description) save via debounced (500ms) update mutation on change. Delete step calls `deleteCompanyStep` / `deleteStep` with confirmation dialog.

5. **AC5: Sub-step management** — Step detail panel includes collapsible sub-steps section. List sub-steps ordered by position. Add sub-step: inline form with name (required), description, instructions, required toggle. Edit/delete sub-steps via `sub_steps_attributes` on step update (`_destroy: true` for removal). Reorder sub-steps via position updates.

6. **AC6: Full step configuration form** — Step detail panel exposes ALL Step model fields:
   - `name` (TextField, required)
   - `description` (TextField, multiline)
   - `instructions` (TextField, multiline, 8+ rows, placeholder mentions `{{artifact_name}}` variables)
   - `agent_id` (Select from real agents, AC3)
   - `allow_non_interactive` (Switch)
   - `skip_policy` (Select: never / if_outputs_exist / manual)
   - `on_failure` (Select: retry / skip / fail)
   - `max_retries` (number input, only visible when `on_failure === 'retry'`)
   - `input_asset_specs` (structured add/remove list: name, asset_type, required toggle)
   - `output_asset_specs` (structured add/remove list: name, asset_type, required toggle, name_pattern)
   - `tool_ids` (Autocomplete multi-select from available tools via `useGetCompanyToolsQuery`)

7. **AC7: Inline workflow name/description edit** — Header name/description use editable TextFields. Changes save via `updateCompanyWorkflow` / `updateProjectWorkflow` mutation, debounced 500ms on change.

8. **AC8: Step reorder** — Up/Down arrow buttons on each step card in sidebar. Calls `reorderCompanySteps` / `reorderSteps` mutation with updated position map. Optimistic UI update.

9. **AC9: Scope-aware navigation** — "Back" button navigates to: `/company/workflows` if `scopeType === 'Company'`, or project workflows tab if `scopeType === 'Project'`. Use `workflow.scopeId` as projectId for project navigation.

10. **AC10: Error handling** — Snackbar on mutation failures. Loading indicators on save operations. Disable actions while mutations in-flight. 404 state with "Go back" link.

## Tasks / Subtasks

- [ ] Task 1: Scope-aware workflow fetch (AC: #1, #9)
  - [ ] 1.1 Add `getCompanyWorkflow` query to `workflowsApi.ts` — single workflow by ID: `GET /api/v1/company/workflows/:id`
  - [ ] 1.2 On mount: fetch workflow, extract `scopeType`, `scopeId` → set context for all subsequent API calls
  - [ ] 1.3 Loading skeleton / CircularProgress while fetching
  - [ ] 1.4 404 / not found state with navigation back
- [ ] Task 2: Replace local state with API data (AC: #2)
  - [ ] 2.1 Remove `IWorkflow`, `IWorkflowStep` interfaces and `useState` for workflow/steps
  - [ ] 2.2 Use `useGetCompanyStepsQuery` / `useGetStepsQuery` based on scope
  - [ ] 2.3 Render steps in sidebar from API data, ordered by position
  - [ ] 2.4 Selected step state: only store `selectedStepId: number | null`
- [ ] Task 3: Real agent picker (AC: #3)
  - [ ] 3.1 Remove hardcoded `AGENT_OPTIONS`
  - [ ] 3.2 Fetch agents via `useGetCompanyAgentsQuery()` (always company-level, agents are shared)
  - [ ] 3.3 Agent Select dropdown: `agent.name` as label, `agent.id` as value, "No agent" option
  - [ ] 3.4 On agent change → call step update mutation with `{ agent_id: selectedId }`
- [ ] Task 4: Step CRUD (AC: #4)
  - [ ] 4.1 "Add Step" → `createCompanyStep` / `createStep` mutation, position = steps.length + 1
  - [ ] 4.2 Debounced auto-save for text fields (name, description, instructions) — 500ms
  - [ ] 4.3 Immediate save for selects/toggles (agent, skip_policy, on_failure, allow_non_interactive)
  - [ ] 4.4 Delete step → confirmation dialog → `deleteCompanyStep` / `deleteStep`
- [ ] Task 5: Sub-step management (AC: #5)
  - [ ] 5.1 Collapsible sub-steps section in step detail panel
  - [ ] 5.2 List existing sub-steps with position, name, required badge
  - [ ] 5.3 "Add Sub-step" inline form: name (required), description, instructions, required toggle
  - [ ] 5.4 Edit sub-step inline
  - [ ] 5.5 Delete sub-step via `_destroy: true` in `sub_steps_attributes`
  - [ ] 5.6 Sub-step reorder (up/down buttons)
- [ ] Task 6: Full step config form (AC: #6)
  - [ ] 6.1 Layout all fields in step detail panel with sections (Configuration, Execution, Assets, Tools)
  - [ ] 6.2 `skip_policy` Select with options: never, if_outputs_exist, manual
  - [ ] 6.3 `on_failure` Select with options: retry, skip, fail
  - [ ] 6.4 `max_retries` NumberField, conditionally visible when on_failure=retry
  - [ ] 6.5 `input_asset_specs` add/remove list UI (name TextField, asset_type Select, required Switch)
  - [ ] 6.6 `output_asset_specs` add/remove list UI (name, asset_type, required, name_pattern)
  - [ ] 6.7 `tool_ids` Autocomplete multi-select — fetch tools via `useGetCompanyToolsQuery`
- [ ] Task 7: Inline workflow header edit (AC: #7)
  - [ ] 7.1 Editable name/description TextFields in header
  - [ ] 7.2 Debounced save (500ms) via `updateCompanyWorkflow` / `updateProjectWorkflow`
- [ ] Task 8: Step reorder (AC: #8)
  - [ ] 8.1 Up/Down IconButtons on each step card in sidebar
  - [ ] 8.2 On click → compute new positions → call `reorderCompanySteps` / `reorderSteps`
  - [ ] 8.3 Optimistic update: reorder locally, revert on error
- [ ] Task 9: Error handling & polish (AC: #10)
  - [ ] 9.1 `enqueueSnackbar` on mutation errors
  - [ ] 9.2 Saving indicator (e.g., "Saving..." text or subtle spinner near header)
  - [ ] 9.3 Disable Add/Delete buttons while mutations in-flight

## Dev Notes

### Scope Detection Strategy

The builder page route is `/workflow-builder/:workflowId` — no project context in URL. To determine scope:

1. Fetch workflow via company endpoint: `GET /api/v1/company/workflows/:id` — works for company-scoped workflows
2. Check `workflow.scopeType`:
   - `"Company"` → use `useGetCompanyStepsQuery`, `useCreateCompanyStepMutation`, etc.
   - `"Project"` → use `useGetStepsQuery({ projectId: workflow.scopeId, workflowId })`, etc.

**Important**: The company show endpoint currently only returns company-scoped workflows. For project-scoped workflows accessed via builder, you need either:
- Option A: Modify the company `show` action to also find project workflows (simplest — just use `Workflow.active.find(params[:id])` without scoping to company)
- Option B: Add a universal endpoint
- **Recommended: Option A** — modify `Api::V1::Company::WorkflowsController#show` to use `Workflow.active.find(params[:id])` with policy check

### Existing Components to Reuse

**DO NOT recreate** — these already exist in `features/workflow-steps/`:
- `StepCard` — expandable step card (may need adaptation for builder context)
- `AddStepDialog` — RHF + Zod form for step creation
- `WorkflowStepsList` — step list with "Add Step" button

However, the builder page has a **sidebar + main panel layout** (different from the list-based layout of WorkflowStepsList). The builder needs:
- Sidebar: compact step cards (position, name, agent badge) — **new component or simplified StepCard**
- Main panel: full step configuration form — **new component**

Consider extracting shared logic but building builder-specific UI components.

### API Hooks Available

**Workflows** (`features/workflows/api/workflowsApi.ts`):
- `useGetCompanyWorkflowsQuery()` — list
- `useGetWorkflowQuery({ projectId, id })` — single (project-level only)
- Need to add: `useGetCompanyWorkflowQuery(id)` — single company workflow
- `useUpdateCompanyWorkflowMutation()` / `useUpdateProjectWorkflowMutation()`

**Steps** (`features/workflow-steps/api/stepsApi.ts`):
- Company: `useGetCompanyStepsQuery`, `useCreateCompanyStepMutation`, `useUpdateCompanyStepMutation`, `useDeleteCompanyStepMutation`, `useReorderCompanyStepsMutation`
- Project: `useGetStepsQuery`, `useCreateStepMutation`, `useUpdateStepMutation`, `useDeleteStepMutation`, `useReorderStepsMutation`

**Agents** (`features/agents-management/api/agentsApi.ts`):
- `useGetCompanyAgentsQuery()` — returns all company agents

**Tools** (`features/tools-management/api/toolsApi.ts`):
- `useGetCompanyToolsQuery()` — returns all company tools (for `tool_ids` multi-select)

### TypeScript Types

**Step** (`features/workflow-steps/lib/types.ts`):
```
Step { id, workflowId, agentId, position, name, description, instructions, allowNonInteractive, skipPolicy, onFailure, maxRetries, inputAssetSpecs, outputAssetSpecs, agentRuntime, toolIds, subSteps: SubStep[] }
```

**SubStep**: `{ id, stepId, position, name, description, instructions, required }`

**AssetSpec**: `{ name, assetType, required, namePattern? }`

**Workflow** (`features/workflows/lib/types.ts`):
```
Workflow { id, name, description, config, scopeType, scopeId, scopeIndicator, stepsCount, ... }
```

### Key Patterns from Previous Stories

1. **ActionController::TestCase** for controller tests (NOT ActionDispatch::IntegrationTest)
2. **AMS config conflict**: serializer explicit `def config` delegation to `object.config`
3. **Reorder unique constraint**: offset positions by 10000 in transaction, then set final values
4. **sub_steps_attributes**: `accepts_nested_attributes_for :sub_steps, allow_destroy: true` — send `_destroy: true` for removals
5. **Debounced callbacks**: use `useDebouncedCallback` from `use-debounce` package (already used in WorkflowsPanel)
6. **Case conversion**: Frontend sends camelCase, auto-converted to snake_case by `baseApi` interceptors

### File Structure

```
app/frontend/
├── pages/workflow-builder/ui/WorkflowBuilderPage.tsx  # MODIFY — main page component
├── features/workflows/api/workflowsApi.ts             # MODIFY — add getCompanyWorkflow query
├── features/workflow-steps/api/stepsApi.ts             # EXISTS — company + project step hooks ready
├── features/workflow-steps/lib/types.ts                # EXISTS — Step, SubStep, AssetSpec types
├── features/workflows/lib/types.ts                     # EXISTS — Workflow types
```

Backend (if Option A for scope detection):
```
app/controllers/api/v1/company/workflows_controller.rb  # MODIFY — show action to find any workflow
```

### Testing Standards

- Backend: Minitest, `ActionController::TestCase`, FactoryBot
- Frontend: Vitest, co-located `*.test.tsx`
- Run `make check` before commit (runs inside Docker)

### References

- [Source: _bmad-output/implementation-artifacts/12-1-create-new-workflow.md] — Workflow model, controller, serializer patterns
- [Source: _bmad-output/implementation-artifacts/12-2-define-workflow-steps.md] — Step/SubStep models, nested attributes, reorder
- [Source: _bmad-output/implementation-artifacts/12-5-view-workflows-list.md] — WorkflowsPanel, navigation integration
- [Source: ai/epics/epic-11-workflows-phase-5-6.md] — Epic 12 requirements
- [Source: ai/workflow-architecture.md] — Workflow data model, execution architecture

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
