# Story 34.3: Frontend — BMAD Toggle in Workflow Step Editor

Status: ready-for-dev

## Story

As a **workflow builder admin**,
I want a "Use BMAD Method" toggle in the step configuration panel,
so that I can enable BMAD for specific steps when designing a workflow.

## Acceptance Criteria

1. **Given** the admin opens a step configuration panel in the workflow builder
   **When** the step settings are displayed
   **Then** a "Use BMAD Method" toggle (MUI Switch) is visible below the tools/MCP configuration

2. **Given** the admin enables the BMAD toggle on a step
   **When** the workflow is saved
   **Then** the step's `bmad_enabled` field is persisted as `true` via the API

3. **Given** the admin re-opens a step with BMAD enabled
   **When** the step configuration panel loads
   **Then** the BMAD toggle shows as active/on

4. **Given** the toggle is displayed
   **When** rendered in the UI
   **Then** it follows MUI 6 dark theme styling
   **And** is keyboard-accessible with proper ARIA attributes

## Tasks / Subtasks

- [ ] Task 1: Add BMAD toggle to StepDetailPanel (AC: #1, #3, #4)
  - [ ] Add MUI `Switch` + `FormControlLabel` in `StepDetailPanel` component
  - [ ] Read initial value from `step.bmadEnabled` (API response, camelCase)
  - [ ] Place below existing toggles (after `allow_non_interactive` / `mount_repositories`)
  - [ ] Label: "Use BMAD Method"
- [ ] Task 2: Wire toggle to API (AC: #2)
  - [ ] Use existing `onFieldChange` pattern with `immediate: true` (saves on toggle, not debounced)
  - [ ] Call `updateStep({ bmadEnabled: true/false })` → decamelized to `bmad_enabled` on backend
- [ ] Task 3: Update Step TypeScript types (AC: #1–#3)
  - [ ] Add `bmadEnabled?: boolean` to Step type/interface
  - [ ] Ensure RTK Query / API layer includes this field

## Dev Notes

- **File:** `app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx`
- **Component:** `StepDetailPanel` (lines ~875–1043+)
- **Existing toggle patterns:**
  - `allow_non_interactive` toggle → uses `onFieldChange` with immediate save
  - `mount_repositories` toggle → same pattern
  - Both use MUI `Switch` + `FormControlLabel`

### Toggle Pattern (from existing code)

```tsx
<FormControlLabel
  control={
    <Switch
      checked={step.bmadEnabled ?? false}
      onChange={(e) => onFieldChange('bmadEnabled', e.target.checked, { immediate: true })}
      color="primary"
    />
  }
  label="Use BMAD Method"
/>
```

### Field Change Pattern

The `onFieldChange` handler (lines ~439–449) dispatches to `updateStep` with the field name and value. When `immediate: true`, it calls `updateStep` directly (no debounce).

```typescript
// Existing pattern in WorkflowBuilderPage:
const onFieldChange = useCallback((field: string, value: unknown, opts?: { immediate?: boolean }) => {
  const payload = { [field]: value };
  if (opts?.immediate) {
    updateStep(payload);
  } else {
    debouncedUpdateStep(payload);
  }
}, [updateStep, debouncedUpdateStep]);
```

### API Layer

- `useUpdateStepMutation` / `useUpdateCompanyStepMutation` — existing RTK Query mutation
- `decamelizeKeys` handles `bmadEnabled` → `bmad_enabled` conversion
- Step serializer returns `bmad_enabled` → `camelcaseKeys` converts to `bmadEnabled` on frontend

### Project Structure Notes

- All changes in one file: `WorkflowBuilderPage.tsx` (StepDetailPanel section)
- Step type definition likely in `app/frontend/entities/step/` or shared types — add `bmadEnabled`
- Follow existing toggle placement order: general settings → agent → toggles → tools/MCP

### References

- [Source: app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx#L875+] — StepDetailPanel
- [Source: app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx#L439-449] — onFieldChange
- [Source: app/controllers/concerns/steps_actions.rb#L49-61] — step_params (backend)
- [Source: ai/epics/epic-34-bmad-workflow-step.md#Story-34.3] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
