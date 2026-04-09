# Story 38.1: Debug and Fix Session Start Flow

Status: review

## Story

As a user with configured agents,
I want to click "Start Builder" on the Aixle Builder landing page and land on a working session page,
so that I can begin an interactive AI-powered workflow building session.

## Acceptance Criteria

1. Clicking "Start Builder" with a valid agent runtime creates a `TerminalSession` (persisted, with `metadata: { "aixle_builder": true }`)
2. Redirect lands on `SessionPage` with correct session data (session props render without errors)
3. If no configured agents exist, show a clear empty-state message (not just a disabled button with no explanation)
4. If `SessionService.create_and_start` fails validation (unpersisted session), show a flash error and stay on LandingPage — never redirect with a nil session ID
5. If Temporal workflow startup fails (session saved but `failed` state), SessionPage shows `errorMessage` and does not render a broken terminal iframe
6. Eager Hash/Array props on `show` and `session` actions are wrapped in lambdas to prevent partial-reload corruption (project architecture rule)
7. Finish Session button calls the correct API route (`POST /api/v1/terminal_sessions/:id/finish`)

## Tasks / Subtasks

- [x] **Task 1: Fix controller `start` error handling** (AC: #4)
  - [x] 1.1 — After `SessionService.create_and_start`, check `session.persisted?`. If `false`, `redirect_to` back with `flash[:alert]`
  - [x] 1.2 — If `session.persisted?` but `session.failed?`, still redirect to session page (Temporal error is visible there via `errorMessage`)
  - [x] 1.3 — Log a warning if `meta_tool_ids` resolves to empty array (tools not seeded)

- [x] **Task 2: Fix lambda wrapping on controller props** (AC: #6)
  - [x] 2.1 — In `#show`: wrap `sessions`, `active_session_id`, `configured_agents`, `assets` in `-> { ... }`
  - [x] 2.2 — In `#show_session`: wrap `session` and `cable_stream` props in `-> { ... }`
  - [x] 2.3 — `project_props` already wrapped via `InertiaRails.always` in parent `inertia_share` — removed redundant prop

- [x] **Task 3: Fix LandingPage empty-agents state** (AC: #3)
  - [x] 3.1 — Alert shown when `configuredAgents` is empty with link to `/profile`
  - [x] 3.2 — Start button disabled with tooltip "No agent runtime configured"

- [x] **Task 4: Add flash error display on LandingPage** (AC: #4)
  - [x] 4.1 — Flash already handled globally in `AuthLayout.tsx` — `flash.alert` shows red notification automatically
  - [x] 4.2 — `Web::ApplicationController` `inertia_share` includes `flash.to_hash` which covers both `notice` and `alert`

- [x] **Task 5: Fix Finish Session route** (AC: #7)
  - [x] 5.1 — Added web-scoped `POST aixle_builder/:id/finish` route + `finish` action on controller
  - [x] 5.2 — Controller action delegates to `SessionService.finish` and redirects back to session page
  - [x] 5.3 — Frontend `handleFinish` updated to use `${basePath}/aixle_builder/${s.id}/finish`

- [x] **Task 6: Write backend integration tests** (AC: #1, #2, #4)
  - [x] 6.1 — Created `test/integration/web/company/projects/aixle_builder_controller_test.rb`
  - [x] 6.2 — Test `GET #show` renders `Projects/AixleBuilder/LandingPage`
  - [x] 6.3 — Test `POST #start` with valid params → redirects to session URL
  - [x] 6.4 — Test `POST #start` with failed session → redirects back with flash alert
  - [x] 6.5 — Test `GET #show_session` with valid session → renders `Projects/AixleBuilder/SessionPage`
  - [x] 6.6 — Test `GET #show_session` with wrong user → 404
  - [x] 6.7 — Added `:aixle_builder` factory trait

## Dev Notes

### Architecture Compliance

**Controller hierarchy:** `Web::Company::Projects::AixleBuilderController < Web::Company::Projects::ApplicationController`. Auth, project scoping, Pundit, and `inertia_share` (current_user, projects, project, flash) are handled by parent classes.

**Lambda wrapping rule (CRITICAL):** When any prop on the page uses `InertiaRails.defer`, ALL eager Hash/Array props MUST be wrapped in `-> { ... }`. Without this, Inertia Rails' `PropsResolver` recursively traverses plain Hash props during partial reloads, filtering out scalar keys while leaking Array keys — producing corrupted props that overwrite the full data on the frontend. Both `show` and `session` actions currently violate this rule.

**`SessionService.create_and_start` returns unsaved session on failure** — it does `return session unless session.save` (line 15 of `session_service.rb`). The controller must check `session.persisted?` before using `session.id` in the redirect URL.

**Finish route mismatch:** The `finish` action lives under `api/v1` scope at `POST /api/v1/terminal_sessions/:id/finish` (routes.rb:38-42). The SessionPage frontend calls `POST /terminal_sessions/${s.id}/finish` without the API prefix — this will 404 or hit the wrong route.

### Key Files to Modify

| File | Changes |
|------|---------|
| `app/controllers/web/company/projects/aixle_builder_controller.rb` | Error handling in `start`, lambda wrapping in `show` and `session` |
| `app/frontend/pages/Projects/AixleBuilder/LandingPage.tsx` | Empty-agents state, flash error display |
| `app/frontend/pages/Projects/AixleBuilder/SessionPage.tsx` | Fix finish URL |
| `test/integration/web/company/projects/aixle_builder_controller_test.rb` | New test file |
| `test/factories/terminal_sessions.rb` | Add `:aixle_builder` trait |

### Existing Patterns to Follow

- **Integration tests:** Inherit `WebTestCase < ActionDispatch::IntegrationTest`. Use `create_authenticated_user` → returns `[company, user]`. Use `web_sign_in(user)`. Assert with `assert_inertia_component "Projects/AixleBuilder/LandingPage"`.
- **Flash handling:** `Web::ApplicationController` shares flash via `inertia_share`. Frontend reads via `usePage().props.flash`. Pattern used in login flow already.
- **Mantine alerts:** Use `Alert` component from `@mantine/core` for inline messages, `notifications.show` for toasts.
- **apiFetch:** `shared/lib/apiFetch.ts` — sets CSRF, `Accept: application/json`, `credentials: include`. Used for JSON API mutations throughout the app.

### Anti-Patterns to Avoid

- **Never use plain Hash/Array props when defer props exist** — wrap in `-> { }`
- **Never use `router.post` for JSON API endpoints** — use `apiFetch` + `router.reload`
- **Never redirect with a nil `session.id`** — check `persisted?` first
- **Never use `new Date()` on Alba-serialized dates** — use `shared/lib/formatDate` helpers

### Project Structure Notes

- Controller: `app/controllers/web/company/projects/aixle_builder_controller.rb`
- Pages: `app/frontend/pages/Projects/AixleBuilder/LandingPage.tsx`, `SessionPage.tsx`
- Integration tests: `test/integration/web/company/projects/`
- Factories: `test/factories/terminal_sessions.rb`
- Shared flash props: `Web::ApplicationController` `inertia_share` block

### References

- [Source: app/services/session_service.rb#create_and_start — line 15: `return session unless session.save`]
- [Source: config/routes.rb#L38-42 — finish route under api/v1 namespace]
- [Source: .cursor/rules/rails-rules/inertia-alba-realtime-agent.mdc — lambda wrapping rule]
- [Source: .cursor/rules/rails-rules/inertia-drawer-data-pattern.mdc — PropsResolver corruption explanation]
- [Source: ai/project-context.md — testing patterns, controller hierarchy, anti-patterns]

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Debug Log References

- Renamed `session` action to `show_session` to avoid shadowing Rails' `session` method (caused NoMethodError in all actions when `AuthConcern#signed_in?` called `session[:user_id]`)
- Added `show_session?` and `finish?` to policy (dynamic_authorize! requires policy method per action)
- Used `company_project_*` path helpers (routes nested under `resources :projects`)

### Completion Notes List

- Controller error handling: `session.persisted?` check prevents nil-id redirects; flash alert on failure
- Lambda wrapping: all eager Hash/Array props wrapped in `-> { }` on both `show` and `show_session`
- Empty-agents UX: Mantine Alert with link to profile, Tooltip on disabled button
- Flash: already handled globally in AuthLayout — no page-level changes needed
- Finish route: added web-scoped `POST finish` action instead of calling API endpoint — cleaner Inertia flow
- Action rename: `session` → `show_session` to avoid Rails method collision (breaking bug fix)
- All 7 integration tests passing

### File List

- app/controllers/web/company/projects/aixle_builder_controller.rb (modified)
- app/policies/web/company/projects/aixle_builder_policy.rb (modified)
- app/frontend/pages/Projects/AixleBuilder/LandingPage.tsx (modified)
- app/frontend/pages/Projects/AixleBuilder/SessionPage.tsx (modified)
- config/routes.rb (modified)
- test/factories/terminal_sessions.rb (modified)
- test/integration/web/company/projects/aixle_builder_controller_test.rb (new)
