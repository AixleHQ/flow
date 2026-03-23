# Story 33.7: Frontend — BMAD Toggle in SessionLaunchWidget

Status: ready-for-dev

## Story

As a **developer launching a standalone session**,
I want a "Use BMAD Method" toggle in the session launch configuration,
so that I can enable BMAD with a single click before starting my session.

## Acceptance Criteria

1. **Given** the user opens the session launch widget
   **When** the configuration options are displayed
   **Then** a "Use BMAD Method" toggle (MUI Switch) is visible in the configuration section

2. **Given** the user enables the "Use BMAD Method" toggle
   **When** the session is started
   **Then** the API request includes `sessionConfig: { bmadEnabled: true }` in the payload (camelCase for frontend, decamelized to `bmad_enabled` by API layer)

3. **Given** the user does not interact with the BMAD toggle
   **When** the session is started
   **Then** `bmadEnabled` is not included in the payload

4. **Given** the toggle is displayed
   **When** rendered
   **Then** it follows MUI 6 dark theme styling with `accent.blue` active state
   **And** has label "Use BMAD Method"
   **And** is keyboard-accessible with ARIA attributes

## Tasks / Subtasks

- [ ] Task 1: Add BMAD toggle state to SessionLaunchWidget (AC: #1, #3)
  - [ ] Add `const [bmadEnabled, setBmadEnabled] = useState(false)` to component state
  - [ ] Add MUI `Switch` with `FormControlLabel` in the configuration section
  - [ ] Label: "Use BMAD Method"
- [ ] Task 2: Include in API payload (AC: #2)
  - [ ] In `handleStart`, add `sessionConfig: { bmadEnabled: true }` when toggle is on
  - [ ] Use `decamelizeKeys` — will become `session_config: { bmad_enabled: true }` on backend
- [ ] Task 3: Styling and accessibility (AC: #4)
  - [ ] Use MUI Switch component (follows theme automatically)
  - [ ] Ensure `FormControlLabel` has proper `label` prop
  - [ ] Verify keyboard navigation (Tab + Space to toggle)

## Dev Notes

- **File:** `app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx`
- **Existing state pattern (lines 69–78):**
  ```typescript
  const [selectedAgent, setSelectedAgent] = useState<AgentType | null>(null);
  const [mode, setMode] = useState<SessionMode>('interactive');
  // ... etc
  ```
- **Existing payload (lines 186–199):** The `createSessionAction` call currently does NOT include `sessionConfig`. This story adds it.
- **API transformation:** Frontend uses `camelCase`, `decamelizeKeys` middleware converts to `snake_case` for Rails API. So `{ sessionConfig: { bmadEnabled: true } }` becomes `{ session_config: { bmad_enabled: true } }`.
- **Placement in UI:** Add below the mode selector and above the "Start" button, grouped with other toggles/options.

### MUI Switch Pattern

```tsx
<FormControlLabel
  control={
    <Switch
      checked={bmadEnabled}
      onChange={(e) => setBmadEnabled(e.target.checked)}
      color="primary"
    />
  }
  label="Use BMAD Method"
/>
```

### Payload Addition

```typescript
const result = await createSessionAction({
  terminalSession: {
    sessionType: 'agent_session',
    agentType: selectedAgent,
    projectId: projectId,
    // ... existing fields ...
    ...(bmadEnabled ? { sessionConfig: { bmadEnabled: true } } : {}),
  },
});
```

### Project Structure Notes

- Feature-Sliced Design: widget is in `app/frontend/widgets/session-launch/`
- MUI 6 is already in the project (v6.4.7)
- Dark theme tokens auto-apply to MUI components
- Import: `import { Switch, FormControlLabel } from '@mui/material'`

### References

- [Source: app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx#L69-78] — existing state
- [Source: app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx#L186-199] — payload
- [Source: ai/ux-design-specification.md#Component-Strategy] — MUI component patterns
- [Source: ai/project-context.md#TypeScript/Frontend] — `decamelizeKeys` API convention

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
