# Story 16.6: Artifact Review Page (Frontend)

Status: ready-for-dev

## Story

As a user,
I want a dedicated page to review session outputs,
so that I can preview files and decide which to keep as project assets.

## Acceptance Criteria

1. **AC1: Route** — `/company/sessions/:sessionId/artifacts` renders `SessionArtifactsPage`. Also works from project context: `/company/projects/:projectId/sessions/:sessionId/artifacts`.

2. **AC2: Data fetching** — Fetches pending artifacts via RTK Query (`getSessionArtifacts`). Shows loading state while fetching.

3. **AC3: File list** — Table or card list showing: filename, size (human-readable), content type icon. Sorted by name.

4. **AC4: Selection** — Checkboxes per file. "Select all" / "Deselect all" toggle. Default: all unchecked.

5. **AC5: Scope selector** — Dropdown or radio: "Save to Project" (pre-selected if session has project) or "Save to Company". Shows project/company name.

6. **AC6: Actions** — "Save selected" button (POST review with `save` for checked, `dismiss` for unchecked). "Dismiss all" button. Both disabled while processing.

7. **AC7: Post-review** — Navigate back to session view page. Show success toast/snackbar.

8. **AC8: Empty state** — "No outputs collected from this session" when no artifacts.

9. **AC9: Already reviewed** — If `artifacts_reviewed` is true, show message: "Outputs already reviewed" with link back.

## Tasks / Subtasks

- [ ] Task 1: Add RTK Query endpoints (AC: #2)
  - [ ] 1.1 Add `getSessionArtifacts` query to `terminalSessionApi.ts`
  - [ ] 1.2 Add `reviewSessionArtifacts` mutation
  - [ ] 1.3 Add types: `ISessionArtifact`, `IReviewArtifactsRequest`
- [ ] Task 2: Add route (AC: #1)
  - [ ] 2.1 Add `companySessionArtifactsPath` to `shared/routes.ts`
  - [ ] 2.2 Add `companyProjectSessionArtifactsPath` variant
  - [ ] 2.3 Add route entries to `routeTree.tsx` with lazy loading
- [ ] Task 3: Create SessionArtifactsPage (AC: #3-#9)
  - [ ] 3.1 Create `web/app/frontend/pages/session-artifacts/ui/SessionArtifactsPage.tsx`
  - [ ] 3.2 Create `web/app/frontend/pages/session-artifacts/index.ts`
  - [ ] 3.3 File list with checkboxes (MUI Table or List)
  - [ ] 3.4 Scope selector (MUI Select)
  - [ ] 3.5 Action buttons: Save Selected, Dismiss All
  - [ ] 3.6 Handle loading, empty, already-reviewed states
  - [ ] 3.7 Post-review: navigate + toast

## Dev Notes

### RTK Query Endpoints

Add to `web/app/frontend/shared/api/terminalSessionApi.ts`:

```typescript
getSessionArtifacts: builder.query<ISessionArtifact[], number>({
  query: (sessionId) => ({
    url: `/api/v1/company/terminal_sessions/${sessionId}/artifacts`,
    method: 'GET',
  }),
  transformResponse: (response: { data: ISessionArtifact[] }) => response.data ?? response,
  providesTags: (_result, _error, sessionId) => [
    { type: QueryTag.TerminalSession, id: `artifacts-${sessionId}` },
  ],
}),

reviewSessionArtifacts: builder.mutation<ITerminalSession, IReviewArtifactsRequest>({
  query: ({ sessionId, ...body }) => ({
    url: `/api/v1/company/terminal_sessions/${sessionId}/artifacts/review`,
    method: 'POST',
    data: body,
  }),
  invalidatesTags: (_result, _error, { sessionId }) => [
    { type: QueryTag.TerminalSession, id: sessionId },
    { type: QueryTag.TerminalSession, id: `artifacts-${sessionId}` },
    { type: QueryTag.TerminalSession, id: 'LIST' },
  ],
}),
```

### Types

Add to `entities/terminal-session/model/types.ts`:

```typescript
export interface ISessionArtifact {
  id: number;
  name: string;
  folder: string | null;
  status: string;
  fileSize: number | null;
  contentType: string | null;
  downloadUrl: string | null;
  createdAt: string;
}

export interface IReviewArtifactsRequest {
  sessionId: number;
  decisions: Record<string, 'save' | 'dismiss'>;
  targetScopeType?: 'Project' | 'Company';
  targetScopeId?: number;
}
```

### Routes

Add to `shared/routes.ts`:
```typescript
companySessionArtifactsPath: (sessionId: string) => `/company/sessions/${sessionId}/artifacts`,
companyProjectSessionArtifactsPath: (projectId: string, sessionId: string) =>
  `/company/projects/${projectId}/sessions/${sessionId}/artifacts`,
```

### Route Tree Entry

```typescript
const SessionArtifactsPage = lazyRouteComponent(() => import('../pages/session-artifacts'));

export const companySessionArtifactsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companySessionArtifactsPath('$sessionId'),
  component: SessionArtifactsPage,
});

export const projectSessionArtifactsRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: Routes.frontend.companyProjectSessionArtifactsPath('$projectId', '$sessionId'),
  component: SessionArtifactsPage,
});
```

Add both to `routeTree.addChildren([...])`.

### Page Component Structure

```
SessionArtifactsPage
├── Header (Back button, "Review Session Outputs" title)
├── Already Reviewed banner (if artifactsReviewed)
├── Empty state (if no artifacts)
├── Artifact list
│   ├── Select All checkbox
│   ├── Per-file rows (checkbox, name, size, type, download link)
│   └── Scope selector
└── Action bar (Save Selected, Dismiss All)
```

### Formatting Helpers

```typescript
const formatFileSize = (bytes: number | null) => {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};
```

### Feature-Slice Design

Following existing FSD structure:
- `pages/session-artifacts/ui/SessionArtifactsPage.tsx`
- `pages/session-artifacts/index.ts`
- Types go in `entities/terminal-session/model/types.ts` (co-located with session types)
- API endpoints go in `shared/api/terminalSessionApi.ts`

### Files to Touch

- `web/app/frontend/pages/session-artifacts/ui/SessionArtifactsPage.tsx` (new)
- `web/app/frontend/pages/session-artifacts/index.ts` (new)
- `web/app/frontend/shared/api/terminalSessionApi.ts` — add endpoints
- `web/app/frontend/shared/routes.ts` — add paths
- `web/app/frontend/app/routeTree.tsx` — add routes
- `web/app/frontend/entities/terminal-session/model/types.ts` — add artifact types

### Dependencies

- **Requires Story 16.5** — API endpoints must exist

### What NOT To Change

- Do NOT modify `CompanySessionViewPage` — linking happens in Story 16.7
- Do NOT modify `SessionHistoryWidget` — badge happens in Story 16.7

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.6]
- [Source: web/app/frontend/shared/api/terminalSessionApi.ts — RTK Query patterns]
- [Source: web/app/frontend/shared/routes.ts — route definitions]
- [Source: web/app/frontend/app/routeTree.tsx — route tree structure]
- [Source: web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx — page pattern]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
