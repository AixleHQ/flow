# E1: Aixle Builder — Fix & E2E Verification

## Overview

Fix the broken Aixle Builder flow (session start → agent launch) and verify it works end-to-end via Playwright MCP.

---

## Problem Statement

Aixle Builder is a project-scoped interactive agent session with meta-tools that create boards, columns, bindings, workflows, steps, agents, tools, skills, and MCP servers. The feature was migrated from Material UI SPA (with API controller + Redux RTK Query) to Inertia + Mantine. Currently something breaks during the session start flow — likely routing or session creation issues.

---

## Architecture Comparison: develop (old) vs feature/inertia-mantine (current)

### develop (MUI + TanStack Router + Redux RTK Query)

```
AixleBuilderPage.tsx (MUI, TanStack Router)
  → useStartAixleBuilderMutation (Redux RTK)
    → POST /api/v1/company/projects/:project_id/aixle_builder/start
      → Api::V1::Company::Projects::AixleBuilderController#start
        → SessionService.create_and_start
        → respond_with session, serializer: TerminalSessionSerializer
  → navigate({ to: aixleBuilderRunPath(projectId, session.id) })
    → AixleBuilderSessionPage.tsx (uses useTerminalSession hook, ActionCable channel)
```

**Key Differences:**

| Aspect | develop (old) | feature/inertia-mantine (current) |
|--------|---------------|-----------------------------------|
| **Controller** | `Api::V1::Company::Projects::AixleBuilderController` (JSON API) | `Web::Company::Projects::AixleBuilderController` (Inertia) |
| **Routing** | TanStack Router, client-side navigation | Inertia `router.post()` + server-side redirect |
| **Session start** | POST → JSON response → client-side redirect | POST → server-side `redirect_to` string path |
| **Session page** | Client fetches session via `useTerminalSession` hook (RTK Query polling) | Server renders via Inertia props + `InertiaRails.defer` |
| **Activities** | `useMetaActivityChannel` (ActionCable `TerminalSessionChannel`) | Server-side `builder_activities` from session metadata + `cable_stream` |
| **Board preview** | Client fetches via API (`fetch(boardPath)`) with polling | Server deferred prop `board_columns` via Inertia |
| **Workflows preview** | `WorkflowsListPreview` uses RTK Query with polling | Server deferred prop `workflows` via Inertia |
| **Terminal** | `TerminalSessionWidget` (embedded xterm.js component) | Same widget, but loaded via Inertia page |
| **Routes** | `resource :aixle_builder { post :start; get :status }` under API | `get/post/get` custom routes under web scope |
| **Error handling** | RTK Query `.unwrap()` + snackbar | Server redirect (no error handling if session fails) |
| **Data format** | JSON (ActiveModelSerializers) | Inertia props (Alba resources) |

### develop Feature Components (all MUI + RTK Query)

| File | Role | Equivalent in Inertia |
|------|------|-----------------------|
| `features/aixle-builder/api/aixleBuilderApi.ts` | RTK Query: `start` + `sessions` | Inline `router.post()` in LandingPage |
| `features/aixle-builder/lib/useMetaActivityChannel.ts` | ActionCable subscription for meta activities | `useInertiaCableStream` + deferred `builder_activities` prop |
| `features/aixle-builder/ui/AixleBuilderBanner.tsx` | CTA banner on Workflows page | Exists in WorkflowsPage.tsx |
| `features/aixle-builder/ui/MetaActivityLog.tsx` | Activity feed in side panel | Reimplemented in SessionPage.tsx |
| `features/aixle-builder/ui/BoardPreview.tsx` | Board preview in side panel (client fetch + polling) | Deferred `board_columns` prop |
| `features/aixle-builder/ui/WorkflowPreview.tsx` | Single workflow detail preview | Not directly ported (SessionPage shows workflow list) |
| `features/aixle-builder/ui/WorkflowsListPreview.tsx` | All project workflows (RTK Query + polling) | Deferred `workflows` prop |
| `pages/aixle-builder/ui/AixleBuilderPage.tsx` | Landing page (MUI) | `LandingPage.tsx` (Mantine) |
| `pages/aixle-builder/ui/AixleBuilderRunPage.tsx` | Workflow run-based session page | Not used — Inertia uses direct session page |
| `pages/aixle-builder/ui/AixleBuilderSessionPage.tsx` | Direct session page (MUI) | `SessionPage.tsx` (Mantine) |

### develop API Routes

```ruby
# In develop (API-only, under api/v1/company/projects):
resource :aixle_builder, only: [], controller: "aixle_builder" do
  post :start    # POST /api/v1/company/projects/:project_id/aixle_builder/start
  get :status    # GET  /api/v1/company/projects/:project_id/aixle_builder/status
end
```

### Current Inertia Routes

```ruby
# In feature/inertia-mantine (web scope):
get "aixle_builder",              to: "aixle_builder#show",    as: :aixle_builder
post "aixle_builder/start",       to: "aixle_builder#start",   as: :aixle_builder_start
get "aixle_builder/:id/session",  to: "aixle_builder#session", as: :aixle_builder_session
```

---

## Key Files

| File | Role |
|------|------|
| `app/controllers/web/company/projects/aixle_builder_controller.rb` | show, start, session actions |
| `app/frontend/pages/Projects/AixleBuilder/LandingPage.tsx` | Landing + session list (Mantine) |
| `app/frontend/pages/Projects/AixleBuilder/SessionPage.tsx` | Active session UI (Mantine) |
| `app/services/session_service.rb` | Creates TerminalSession + starts Temporal workflow |
| `app/services/context_builders/aixle_builder.rb` | Injects system prompt for builder sessions |
| `db/seeds/aixle_builder.rb` | Seeds Workflow Architect agent + Aixle Builder workflow |
| `app/services/internal_tools/meta_*.rb` | ~25 meta-tools for board/workflow/entity CRUD |
| `db/seeds/platform_tools.rb` | Tool definitions (META_WORKFLOW_TOOLS, BOARD_WORKFLOW_TOOLS) |

---

## Stories

### Story 1.1: Debug and Fix Session Start Flow

**Goal:** Ensure clicking "Start Builder" on the LandingPage successfully creates a TerminalSession and redirects to the SessionPage.

**Investigation Points:**

1. **Empty `configuredAgents`** — LandingPage uses `configuredAgents[0]` for default runtime. If the user has no configured agents, runtime is null, Start is disabled, and there's no clear error message. In develop, the old page used `currentUser.configuredAgents` from Redux — check what `current_user.configured_agents` returns in the Inertia controller. Is it populated?

2. **`SessionService.create_and_start` failure** — The method returns the session without raising on save failure. Controller then does `redirect_to "...#{session.id}/session"`. If `session.id` is nil (unsaved), this produces a bad redirect. In develop, the old page used `.unwrap()` on the mutation and showed a snackbar on error. **The Inertia version has no error handling.**

3. **Meta-tool IDs empty** — `Tool.where(kind: :workflow, name: aixle_builder_tool_names)` may return empty if seeds haven't been run. The old develop version had the same risk. Verify seeds are loaded.

4. **Session page scope** — `#session` finds TerminalSession with `metadata @> { "aixle_builder": true }` AND `user: current_user` AND project scope. If the session was created but metadata is malformed, `find` raises 404.

5. **Temporal workflow startup** — `SessionService.start_temporal_workflow` may fail if Temporal is not configured/running. Session would be saved but in `not_started` state with error_message.

6. **`agent_models` fetch in LandingPage** — Uses raw `fetch('/agent_models?agent_runtime=...')` instead of Inertia props. In develop, this was an RTK Query hook. The current implementation uses `credentials: 'include'` which should work, but verify the endpoint returns JSON correctly.

7. **Tool name mismatch** — develop used `meta_create_skill` but current uses `meta_install_skill` and `meta_search_skills`. Verify the tool_names list matches what's actually seeded.

**Acceptance Criteria:**

- [ ] Clicking "Start Builder" with a valid agent runtime creates a TerminalSession
- [ ] Redirect lands on SessionPage with correct session data
- [ ] SessionPage renders without errors
- [ ] If no configured agents, show clear message (not just disabled button)
- [ ] If session creation fails, show error (not broken redirect)

### Story 1.2: Verify Meta-Tools Are Seeded and Accessible

**Goal:** Ensure all 27 meta-tools referenced in `aixle_builder_tool_names` exist as Tool records with correct schemas.

**Scope:**

- Run/verify `db/seeds/platform_tools.rb` loads all META_WORKFLOW_TOOLS and BOARD_WORKFLOW_TOOLS
- Verify `Tool.where(kind: :workflow, name: ...)` returns 27 records
- Cross-reference tool names with `InternalTools::Meta*` service classes
- Compare tool_names list between develop and current (noted difference: `meta_create_skill` → `meta_install_skill` + `meta_search_skills`)

**Acceptance Criteria:**

- [ ] All 27 tools exist in DB with correct `kind: :workflow`
- [ ] Each tool's `input_schema` matches its `InternalTools::*` service expectations

### Story 1.3: E2E Verification via Playwright MCP

**Goal:** Create a Playwright test that exercises the full Aixle Builder flow through the browser.

**Test Flow:**

1. Log in as authenticated user
2. Navigate to project → Aixle Builder
3. Select agent runtime
4. Click "Start Builder"
5. Verify redirect to SessionPage
6. Verify session UI renders (terminal area, builder activities panel)
7. (Agent actually running is out of scope — we verify the UI flow)

**Implementation Notes:**

- Use Playwright MCP tools to drive the browser
- Tests live under `test/playwright/` or equivalent
- Need seed data: company, user with agent credential, project

**Acceptance Criteria:**

- [ ] Playwright test navigates Landing → Start → Session successfully
- [ ] Test verifies key UI elements on SessionPage
- [ ] Test is repeatable (proper setup/teardown)

---

## Migration Gap Analysis: develop → inertia

Things that were in develop but may be missing or different:

| Feature | develop | current | Gap? |
|---------|---------|---------|------|
| Error handling on start failure | RTK `.unwrap()` + snackbar | No error handling | **YES — add flash/redirect on failure** |
| Default model from agent credential | `useEffect` sets from `currentUser.agentCredentials` | Not implemented | **YES — need credential-based default** |
| AixleBuilderRunPage (workflow-run flow) | Full page with `useGetWorkflowRunQuery` | Not present | **NO — Inertia uses direct session, not workflow run** |
| Activity merging (persisted + realtime) | `useMemo` merges `session.metadata.builderActivities` + WebSocket | Deferred prop only, no realtime merge | **PARTIAL — cable_stream should handle refresh** |
| Board preview refresh on activity | `fetch` + `useEffect` on activity count change | Deferred prop (one-shot) | **PARTIAL — cable_stream may not refresh board_columns** |
| Workflows list polling | RTK Query with `pollingInterval: 10000` | Deferred prop (one-shot) | **PARTIAL — same cable_stream concern** |
| Terminal widget | `TerminalSessionWidget` with `showEditor={false}` | Same component reference | **OK** |
| Finish session button | `useFinishSessionMutation` (RTK) | `router.post(finishPath)` | **Verify this works** |

## Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Temporal not running in test | Session stays `not_started` | Stub or skip Temporal for UI-only test |
| No agent credentials | Can't select runtime | Seed test user with at least one configured agent |
| Meta-tools not seeded | Session creates but agent has no tools | Run platform_tools seed in test setup |
| `configuredAgents` implementation unclear | May need model-level fix | Investigate User model method |
| Deferred props not refreshing via cable_stream | Activities/board/workflows stale | May need to add cable_stream reload for deferred props |
