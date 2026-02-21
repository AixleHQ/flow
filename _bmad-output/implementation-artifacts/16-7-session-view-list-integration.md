# Story 16.7: Session View & List Integration

Status: ready-for-dev

## Story

As a user,
I want to see when a session has pending outputs to review,
so that I don't miss important results from completed sessions.

## Acceptance Criteria

1. **AC1: Serializer** — `TerminalSessionSerializer` includes `artifacts_reviewed` (boolean), `pending_artifacts_count` (integer), `session_logs_count` (integer).

2. **AC2: Frontend types** — `ITerminalSession` includes `artifactsReviewed: boolean`, `pendingArtifactsCount: number`, `sessionLogsCount: number`.

3. **AC3: Session view page** — In `CompanySessionViewPage`, when session is collected and `!artifactsReviewed && pendingArtifactsCount > 0`: show prominent "Review Outputs (N files)" button linking to artifacts page.

4. **AC4: Session list badge** — In `SessionHistoryWidget`, when session is collected and `!artifactsReviewed && pendingArtifactsCount > 0`: show a small badge/chip next to the status chip.

5. **AC5: SessionSummaryCard** — Add logs count and outputs info to the shared `SessionSummaryCard` component.

## Tasks / Subtasks

- [ ] Task 1: Update serializer (AC: #1)
  - [ ] 1.1 Add `artifacts_reviewed` to attributes
  - [ ] 1.2 Add computed `pending_artifacts_count` method
  - [ ] 1.3 Add computed `session_logs_count` method
- [ ] Task 2: Update frontend types (AC: #2)
  - [ ] 2.1 Add `artifactsReviewed`, `pendingArtifactsCount`, `sessionLogsCount` to `ITerminalSession`
- [ ] Task 3: Update CompanySessionViewPage (AC: #3)
  - [ ] 3.1 Add "Review Outputs" button in terminal state block
  - [ ] 3.2 Link to `Routes.frontend.companySessionArtifactsPath(sessionId)` or project variant
  - [ ] 3.3 Only show when `!artifactsReviewed && pendingArtifactsCount > 0`
- [ ] Task 4: Update SessionHistoryWidget (AC: #4)
  - [ ] 4.1 Add badge/chip next to status column for pending review
  - [ ] 4.2 Use MUI Badge or small Chip with "Pending review" or icon
- [ ] Task 5: Update SessionSummaryCard (AC: #5)
  - [ ] 5.1 Add logs count display when `sessionLogsCount > 0`
  - [ ] 5.2 Add outputs pending info

## Dev Notes

### Serializer Changes

Add to `terminal_session_serializer.rb`:

```ruby
attributes :artifacts_reviewed, :pending_artifacts_count, :session_logs_count

def pending_artifacts_count
  object.output_assets.pending_review.count
end

def session_logs_count
  object.session_logs.count
end
```

**N+1 concern**: `pending_artifacts_count` and `session_logs_count` run COUNT queries per session. For the list endpoint (index), this means N+1. Options:
- Accept it (sessions list is paginated, max 25 per page)
- Add counter cache columns later if performance is an issue
- For now, `count` on already-loaded association is acceptable

### Frontend Type Changes

In `entities/terminal-session/model/types.ts`, add to `ITerminalSession`:

```typescript
artifactsReviewed: boolean;
pendingArtifactsCount: number;
sessionLogsCount: number;
```

### CompanySessionViewPage — Review Button

After the `SessionSummaryCard` in the terminal state block, add:

```tsx
{session.state === 'collected' && !session.artifactsReviewed && session.pendingArtifactsCount > 0 && (
  <Button
    variant="contained"
    color="warning"
    onClick={() => {
      const pid = routeProjectId || (session.projectId ? String(session.projectId) : null);
      const to = pid
        ? Routes.frontend.companyProjectSessionArtifactsPath(pid, String(id))
        : Routes.frontend.companySessionArtifactsPath(String(id));
      navigate({ to: to as string });
    }}
  >
    Review Outputs ({session.pendingArtifactsCount} files)
  </Button>
)}
```

Place between `SessionSummaryCard` and the existing button row.

### SessionHistoryWidget — Badge

In `SessionHistoryWidget.tsx`, in the status column render (where `<Chip label={session.state} .../>` is):

```tsx
<Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
  <Chip size="small" label={session.state} color={...} />
  {session.state === 'collected' && !session.artifactsReviewed && session.pendingArtifactsCount > 0 && (
    <Chip size="small" label={`${session.pendingArtifactsCount} pending`} color="warning" variant="outlined" />
  )}
</Box>
```

### SessionSummaryCard Additions

Add to the bottom of the card (after usage section), if session has logs or pending outputs:

```tsx
{(session.sessionLogsCount > 0 || session.pendingArtifactsCount > 0) && (
  <Box sx={{ mt: 1, pt: 1, borderTop: 1, borderColor: 'divider', display: 'flex', gap: 1.5 }}>
    {session.sessionLogsCount > 0 && (
      <Typography variant="caption" color="text.secondary">
        {session.sessionLogsCount} log{session.sessionLogsCount > 1 ? 's' : ''}
      </Typography>
    )}
    {session.pendingArtifactsCount > 0 && (
      <Typography variant="caption" color="warning.main">
        {session.pendingArtifactsCount} output{session.pendingArtifactsCount > 1 ? 's' : ''} pending review
      </Typography>
    )}
  </Box>
)}
```

### Files to Touch

- `web/app/serializers/terminal_session_serializer.rb` — add 3 new attributes
- `web/app/frontend/entities/terminal-session/model/types.ts` — add 3 fields
- `web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx` — review button
- `web/app/frontend/widgets/session-history/ui/SessionHistoryWidget.tsx` — pending badge
- `web/app/frontend/entities/terminal-session/ui/SessionSummaryCard.tsx` — logs/outputs info

### Dependencies

- **Requires Story 16.4** — `output_assets` association, `artifacts_reviewed` column
- **Requires Story 16.1** — `session_logs` association
- **Requires Story 16.6** — Artifacts page route exists for linking

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.7]
- [Source: web/app/serializers/terminal_session_serializer.rb — current attributes]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — ITerminalSession]
- [Source: web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx — terminal state block]
- [Source: web/app/frontend/widgets/session-history/ui/SessionHistoryWidget.tsx — status column]
- [Source: web/app/frontend/entities/terminal-session/ui/SessionSummaryCard.tsx — card structure]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
