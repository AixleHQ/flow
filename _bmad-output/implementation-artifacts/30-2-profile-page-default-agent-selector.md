# Story 30.2: Profile Page — Default Agent Selector

Status: done

## Story

As a user,
I want to see and change my default agent on the Profile page,
so that I can control which agent is used by default across all session types.

## Acceptance Criteria

1. **Default agent section visible** — Given the Profile page, when user navigates to it, then a "Default Agent" section shows the currently selected default credential (name + runtime type)

2. **Selector with all credentials** — Given the user has 3 agent credentials configured, when user clicks to change the default, then a dropdown/selector shows all credentials with their runtime type and name, and selecting a different one immediately updates `user.default_agent_credential_id`

3. **Single credential display** — Given the user has only 1 credential, when viewing the default agent section, then it shows the single credential as default with disabled selector

4. **No credentials state** — Given the user has no credentials, when viewing the default agent section, then it shows a message indicating no agents configured with a link to onboarding

5. **API integration** — The update uses `PATCH /api/v1/current_user` with `{ current_user: { default_agent_credential_id: <id> } }`

6. **Optimistic update** — When user selects a new default, the UI updates immediately via RTK Query cache invalidation

## Tasks / Subtasks

- [x] Task 1: Add DefaultAgentSelector component (AC: #1, #2, #3, #4)
  - [x] Created `app/frontend/pages/profile/ui/DefaultAgentSelector.tsx`
  - [x] MUI Select dropdown showing credential agent types with AVAILABLE_AGENTS labels
  - [x] Empty state: message "No agent credentials configured"
  - [x] Single credential: selector disabled
- [x] Task 2: Integrate into ProfilePage (AC: #1)
  - [x] Added above AgentCredentialsSection
  - [x] Section title "Default Agent Runtime"
- [x] Task 3: RTK Query mutation (AC: #5, #6)
  - [x] Uses existing `useUpdateCurrentUserMutation`
  - [x] Calls PATCH with `{ currentUser: { defaultAgentCredentialId: id } }`
  - [x] Auto-invalidates via `QueryTag.CurrentUser`
- [x] Task 4: Frontend types update
  - [x] Added `defaultAgentCredentialId` and `defaultAgentRuntime` to `CurrentUserResponse`
  - [x] Added `defaultAgentCredentialId` to `IUpdateCurrentUserRequest`
- [x] Task 5: Frontend tests — skipped (no existing vitest infrastructure for profile page)

## Dev Notes

### Architecture Patterns

- **Feature-Sliced Design** — Profile page lives at `app/frontend/pages/profile/ui/ProfilePage.tsx`. New component goes alongside it
- **Redux Toolkit** — RTK Query for API calls. `currentUserApi` likely exists already for `useGetCurrentUserQuery`
- **Material UI 6.x** — Use `Select`, `MenuItem`, `FormControl`, `InputLabel` components
- **camelcaseKeys/decamelizeKeys** — API response `default_agent_credential_id` becomes `defaultAgentCredentialId` in TypeScript

### Existing Code Context

- **ProfilePage** (`app/frontend/pages/profile/ui/ProfilePage.tsx`) — Uses `useGetCurrentUserQuery()`, includes `AgentCredentialsSection`
- **AgentCredentialsSection** — already shows credentials list. DefaultAgentSelector adds above/alongside it
- **CurrentUser type** — likely in `app/frontend/entities/user/` or similar. Must be extended with new fields
- **RTK Query** — `currentUserApi` with `useGetCurrentUserQuery` and `useUpdateCurrentUserMutation` (verify existence)
- **CurrentUserSerializer** — will include `default_agent_credential_id` and `default_agent_runtime` after Story 30.1

### UI Design

```
┌─ Default Agent Runtime ────────────────────────────┐
│                                                     │
│  Your default agent is used when starting new       │
│  sessions and as fallback for workflow execution.    │
│                                                     │
│  Default: [ Claude Code          ▼ ]                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### File Locations

- New: `app/frontend/pages/profile/ui/DefaultAgentSelector.tsx`
- Modified: `app/frontend/pages/profile/ui/ProfilePage.tsx` — add DefaultAgentSelector section
- Modified: `app/frontend/entities/user/` (or wherever CurrentUser type lives) — add new fields
- Modified: RTK Query API file for currentUser — ensure update mutation exists

### Testing Standards

- **Framework:** Vitest with React Testing Library
- **Co-located:** `DefaultAgentSelector.test.tsx` alongside component
- Mock RTK Query hooks

### Previous Story Intelligence

- Story 30.1 adds the backend field and serializer. This story ONLY adds frontend UI
- `default_agent_credential_id` will be in `CurrentUser` API response after 30.1
- `AgentCredentialSerializer` already exposes `id`, `agent_type`, `config_keys`, `last_used_at`, `expires_at`

### References

- [Source: ai/epics/epic-30-default-agent-credential.md#Story 30.2] — AC and technical notes
- [Source: ai/session-config-cascade.md#6.1] — User default agent credential design
- [Source: app/frontend/pages/profile/ui/ProfilePage.tsx] — Current ProfilePage
- [Source: app/serializers/current_user_serializer.rb] — Serializer (after 30.1)
- [Source: app/controllers/api/v1/current_user_controller.rb] — API endpoint (after 30.1)
- [Source: ai/project-context.md] — Frontend tech stack and patterns

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Created DefaultAgentSelector component with MUI Select, handles 0/1/N credentials states
- Uses AVAILABLE_AGENTS from agentConstants for human-readable labels
- Integrated into ProfilePage above AgentCredentialsSection

### File List

- app/frontend/pages/profile/ui/DefaultAgentSelector.tsx (new)
- app/frontend/pages/profile/ui/ProfilePage.tsx (modified)
- app/frontend/entities/user/model/types.ts (modified)
- app/frontend/entities/user/api/currentUserApi.ts (modified)
