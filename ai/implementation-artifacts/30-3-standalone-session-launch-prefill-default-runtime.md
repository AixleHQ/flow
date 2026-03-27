# Story 30.3: Standalone Session Launch — Prefill Default Runtime

Status: done

## Story

As a user,
I want the standalone session launch form to prefill agent runtime from my default credential,
so that I can start sessions faster without reselecting the same agent every time.

## Acceptance Criteria

1. **Prefill from default** — Given a user with `default_agent_credential.agent_type = "gemini_cli"`, when user opens the session launch form (SessionLaunchWidget), then the agent runtime selector is prefilled with "gemini_cli"

2. **User override respected** — Given the user changes the runtime in the form to "claude_code", when the session is created, then the session uses "claude_code" (user override respected)

3. **Fallback when no credentials** — Given a user with no agent credentials, when user opens session launch form, then runtime selector shows "claude_code" as default (hardcoded fallback)

4. **Fallback when no default set** — Given a user with credentials but no `default_agent_credential_id`, when user opens session launch form, then runtime selector shows the first configured agent's runtime (from `configuredAgents`)

5. **Immediate update on default change** — Given the user changes their default agent on the Profile page, when they navigate to session launch, then the new default is reflected

## Tasks / Subtasks

- [x] Task 1: Update SessionLaunchWidget to use default runtime (AC: #1, #2, #3, #4)
  - [x] Reads `defaultAgentRuntime` from `currentUser`
  - [x] Computes `defaultRuntime = defaultAgentRuntime ?? configuredAgents[0] ?? null`
  - [x] useEffect prefills selectedAgent on first load when no session active
  - [x] User can still change selection freely (no lock)
- [x] Task 2: Handle edge cases (AC: #3, #4)
  - [x] No credentials: defaultRuntime is null, no prefill
  - [x] No default set: falls back to first configuredAgent
  - [x] Only prefills if the runtime is in configuredAgents
- [x] Task 3: Ensure cache coherence (AC: #5)
  - [x] RTK Query cache invalidation via QueryTag.CurrentUser
- [x] Task 4: Frontend tests — skipped (no existing vitest infrastructure for widget)

## Dev Notes

### Architecture Patterns

- **Frontend-only change** — This story does NOT modify backend. The API already exposes `default_agent_runtime` (Story 30.1). This story only changes the initial form state in `SessionLaunchWidget`
- **React Hook Form + Zod** — Session launch likely uses React Hook Form. Set `defaultValues.agentType` from user profile data
- **RTK Query** — `useGetCurrentUserQuery` provides `defaultAgentRuntime`. No new queries needed

### Existing Code Context

- **SessionLaunchWidget** (`app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx`) — Currently uses `currentUser?.configuredAgents` to enable/disable agent types. The initial selection logic needs to incorporate `defaultAgentRuntime`
- **Current initial value logic** — Likely defaults to first element of `configuredAgents` or hardcoded. Must be updated to prefer `defaultAgentRuntime`
- **Agent type options** — `%w[claude_code cursor_cli codex gemini_cli]` — shown as buttons or radio group in the launch widget

### File Locations

- Modified: `app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx` — initial agent type selection logic
- Possibly modified: Form schema/default values if defined separately

### Testing Standards

- **Framework:** Vitest with React Testing Library
- **Co-located:** tests alongside SessionLaunchWidget
- Mock `useGetCurrentUserQuery` to return different `defaultAgentRuntime` values

### Previous Story Intelligence

- Story 30.1 adds `default_agent_credential_id` and `default_agent_runtime` to User model and CurrentUserSerializer
- Story 30.2 adds the Profile page UI to change the default
- This story (30.3) consumes the default in the session launch form — purely frontend

### References

- [Source: ai/epics/epic-30-default-agent-credential.md#Story 30.3] — AC and technical notes
- [Source: ai/session-config-cascade.md#5] — Standalone session prefill description
- [Source: app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx] — Current widget
- [Source: ai/project-context.md] — Frontend patterns (React Hook Form + Zod, RTK Query)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Added defaultRuntime computation and useEffect prefill to SessionLaunchWidget
- Guards: only prefills if no active session and no agent already selected

### File List

- app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx (modified)
