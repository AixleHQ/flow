# Story 38.3: E2E Verification via Playwright MCP

Status: review

## Story

As a developer,
I want a Playwright E2E test that exercises the full Aixle Builder flow (Landing → Start → Session),
so that regressions in the session start flow are caught automatically.

## Acceptance Criteria

1. Playwright test navigates to the Aixle Builder landing page for an existing project
2. Test selects an agent runtime and clicks "Start Builder"
3. Test verifies redirect to the SessionPage URL pattern (`/company/projects/:id/aixle_builder/:session_id/session`)
4. Test verifies key UI elements render on SessionPage: session state badge, "Back" button, "Finish Session" button, Activity/Workflows/Board tabs
5. Test is repeatable (uses staging seed data, no destructive side effects beyond creating sessions)
6. Test follows existing Playwright helper conventions (`test/playwright/helpers/`)

## Tasks / Subtasks

- [x] **Task 1: Add Aixle Builder navigation helper** (AC: #6)
  - [x] 1.1 — Added `goToAixleBuilder(page, projectId)` to `test/playwright/helpers/navigation.ts`
  - [x] 1.2 — Exported from `test/playwright/helpers/index.ts`

- [x] **Task 2: Create E2E test file** (AC: #1, #2, #3, #4, #5)
  - [x] 2.1 — Created `test/playwright/specs/aixle-builder.spec.ts`
  - [x] 2.2 — Test: "can view Aixle Builder landing page" — asserts heading, runtime select, start/continue button
  - [x] 2.3 — Test: "can start a builder session and land on session page" — handles both Start and Continue flows, asserts Back button, tabs, and Finish button when active
  - [x] 2.4 — Test: "session page shows loading state or terminal" — uses Promise.race for loading/terminal/error/badge states

- [x] **Task 3: Handle Temporal/container not available** (AC: #5)
  - [x] 3.1 — Tests accept any of: loading state, terminal iframe, error state, or state badge
  - [x] 3.2 — Error state pattern (`Session failed/finished`) is included in acceptable outcomes
  - [x] 3.3 — `waitForURL` uses 30s timeout; `Promise.race` uses 10s timeout per state check

- [x] **Task 4: Document test prerequisites** (AC: #5)
  - [x] 4.1 — JSDoc comment block at top of spec lists all prerequisites
  - [x] 4.2 — Project ID configurable via `STAGING_PROJECT_ID` env var (defaults to "1")

## Dev Notes

### Existing Playwright Infrastructure

Tests use Playwright helpers in `test/playwright/helpers/`:

- `auth.ts` — `login(page, credentials)`, `loginAsAdmin`, `loginAsCompanyAdmin`, `loginAsCompanyEmployee`; reads credentials from env vars
- `navigation.ts` — `goTo(page, path)` wraps `page.goto(BASE_URL + path)` with HTTP credentials; existing helpers for projects, agents, tools, etc.
- `index.ts` — barrel re-export

Env vars: `STAGING_URL` (default `https://staging.aixle.com`), `STAGING_HTTP_USER/PASSWORD` for basic auth, role-specific email/password vars.

### Route Patterns

| Action | URL |
|--------|-----|
| Landing | `GET /company/projects/:project_id/aixle_builder` |
| Start | `POST /company/projects/:project_id/aixle_builder/start` |
| Session | `GET /company/projects/:project_id/aixle_builder/:id/session` |

### Page Element Selectors

**LandingPage (`LandingPage.tsx`):**
- Title: `<Text size="xl" fw={700}>Aixle Builder</Text>`
- Runtime select: `<Select label="Agent Runtime" ...>`
- Start button: `<Button ... >Start Builder</Button>` (or "Continue Active Session" if active)

**SessionPage (`SessionPage.tsx`):**
- State badge: `<Badge color={...} size="sm" variant="outline">{s.state}</Badge>`
- Back button: `<Button variant="subtle" size="xs" ...>Back</Button>`
- Finish button: `<Button ... color="yellow">Finish Session</Button>` (only when `isActive`)
- Tabs: `<Tabs.Tab value="activity">Activity...</Tabs.Tab>`, `<Tabs.Tab value="workflows">Workflows</Tabs.Tab>`, `<Tabs.Tab value="board">Board</Tabs.Tab>`
- Loading state: `<Text size="sm" c="dimmed">Starting container...</Text>`

### Recommended Selectors Strategy

Use Playwright's role-based selectors for resilience:
- `page.getByRole('button', { name: 'Start Builder' })`
- `page.getByRole('button', { name: 'Back' })`
- `page.getByRole('button', { name: 'Finish Session' })`
- `page.getByRole('tab', { name: 'Activity' })`
- `page.getByText('Aixle Builder')` for heading
- `page.getByLabel('Agent Runtime')` for the select

### Test Configuration

The tests target the staging environment (not localhost). They need:
1. `.env` file populated in `test/playwright/helpers/` (see `.env.example`)
2. A project ID — either hardcode from staging or use `STAGING_PROJECT_ID` env var
3. The staging user must have at least one configured agent credential

### Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Temporal not running on staging | Session stays `not_started` | Assert UI renders loading state; don't require terminal iframe |
| No configured agents for test user | Start button disabled | Pre-condition: verify `configuredAgents` is non-empty or skip with message |
| Session creation slow | Test timeout | Use 30s timeout on `waitForURL` |
| Active session exists | "Continue" shown instead of "Start" | Either finish the active session first or assert "Continue" also works |
| Platform tools not seeded | Session creates but agent has no tools | Document as prerequisite; optionally check tool count in admin |

### Key Files to Create/Modify

| File | Changes |
|------|---------|
| `test/playwright/aixle-builder.spec.ts` | New test file |
| `test/playwright/helpers/navigation.ts` | Add `goToAixleBuilder` |
| `test/playwright/helpers/index.ts` | Export new helper |

### Anti-Patterns to Avoid

- **Never hardcode waits** (`page.waitForTimeout`) — use `waitForURL`, `waitForSelector`, or Playwright auto-waiting
- **Never rely on implementation details** like CSS class names — use role selectors and text content
- **Never create test data via API from the test** — use pre-seeded staging data
- **Never assert Temporal actually ran** — the E2E test scope is UI flow verification only

### References

- [Source: test/playwright/helpers/ — existing auth, navigation helpers]
- [Source: test/playwright/helpers/README.md — env var documentation]
- [Source: app/frontend/pages/Projects/AixleBuilder/LandingPage.tsx — UI element structure]
- [Source: app/frontend/pages/Projects/AixleBuilder/SessionPage.tsx — session page elements and state logic]
- [Source: config/routes.rb — aixle_builder route definitions]
- [Source: ai/epics/epic-38-aixle-builder-fix-e2e.md — test flow specification]

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Debug Log References

- Playwright specs directory was empty — this is the first E2E test in the project
- No playwright.config found — tests rely on the `yarn test:e2e` script in package.json

### Completion Notes List

- Navigation helper `goToAixleBuilder` added following existing patterns
- 3 E2E tests covering: landing page visibility, session start flow + redirect, and session page state rendering
- Tests handle both "Start Builder" and "Continue Active Session" flows
- Temporal-resilient: tests pass regardless of whether Temporal is running (accepts loading/terminal/error states)
- All prerequisites documented in spec file header comment

### File List

- test/playwright/helpers/navigation.ts (modified)
- test/playwright/helpers/index.ts (modified)
- test/playwright/specs/aixle-builder.spec.ts (new)
