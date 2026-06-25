---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Backendless frontend testing system (Inertia + React 19 + Mantine 9 + Vitest), driven by generated Typelizer types'
research_goals: 'Establish a frontend test system that never touches a real backend (no containers); leverages the Typelizer-generated TypeScript types so prop shapes/types are the known contract; catches UI breakage when libraries (Mantine/React/etc.) are upgraded; and stays simple, readable, and low-maintenance.'
user_name: 'Artem_Petrov'
date: '2026-06-25'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-06-25
**Author:** Artem_Petrov
**Research Type:** technical

---

## Research Overview

This report investigates a **backendless frontend testing system** for the application's
Inertia.js + React 19 + Mantine 9 frontend, using the **Typelizer-generated TypeScript types**
as the known prop contract. The aim is a test suite that runs entirely in Node (no Rails, no
containers), catches UI regressions when libraries are upgraded, and stays simple and
low-maintenance. Findings are grounded in the real codebase (`app/frontend`,
`app/frontend/types/generated`, `entrypoints/application.tsx`, `Makefile`, CI config) and
verified against current public sources.

---

## Technical Research Scope Confirmation

**Research Topic:** Backendless frontend testing system (Inertia + React 19 + Mantine 9 + Vitest), driven by generated Typelizer types

**Research Goals:**

- Frontend tests that never touch a real backend (no containers required).
- Leverage the Typelizer-generated TS types so prop shapes/types are the known contract.
- Catch UI breakage when libraries (Mantine/React/Tabler/recharts/etc.) are upgraded.
- Keep the system simple, readable, and low-maintenance.

**Technical Research Scope:**

- Architecture Analysis — test pyramid (pure logic → presentational components → Inertia pages), tiers and boundaries.
- Implementation Approaches — Vitest + React Testing Library, Mantine render wrapper, jsdom vs happy-dom, global mocks.
- Technology Stack — devDependencies to add, Vitest config alongside vite-plugin-ruby, test placement/naming.
- Integration Patterns — the mock seam: mocking `@inertiajs/react` (usePage/useForm/router) vs MSW; ActionCable, uppy, window data.
- Typed Fixtures — factories on top of `types/generated`, compile-time drift enforcement, the `unknown` computed-field problem.
- Upgrade Validation — layered: `tsc` → smoke render → snapshot/visual regression; now vs later; CI gating.

**Research Methodology:**

- Current web data with rigorous source verification (context7 for Mantine/Vitest, web for Inertia patterns).
- Multi-source validation for critical technical claims; confidence levels where uncertain.
- All findings anchored to real repository files.

**Scope Confirmed:** 2026-06-25

---

## Technology Stack Analysis

This section maps the **testing tooling landscape** for the app's actual stack (Inertia.js +
React 19.2 + Mantine 9 + Vite 8), verified against current public sources. The generic
"languages / databases / cloud" axes of a typical tech-stack survey are not meaningful for a
frontend test harness, so the axes below are reinterpreted to the relevant tooling layers:
runner, DOM environment, component-testing libraries, Mantine-specific requirements, the
backend-mocking layer, typed-fixture tooling, and upgrade-validation tooling.

> **Current state of the repo (baseline).** `vitest@4` is already in `devDependencies` but
> there is **no `vitest` config, no setup file, no test files, and no `@testing-library/*`,
> `jsdom`, or `happy-dom` installed**. `yarn tsc` and ESLint already run in CI. So the runner
> is chosen; everything around it must still be added.

### Test Runner & Execution Environment

- **Vitest 4** (already installed) is the correct runner: it shares Vite's transform pipeline,
  so the project's path aliases (`shared/ui`, `@/types/generated`, resolved by
  `vite-tsconfig-paths`), SWC/React, and CSS-module handling work in tests with near-zero extra
  config. Jest would require re-deriving all of that. _Confidence: high._
- It runs **entirely in Node — no Rails, no containers** — which is the central goal. CI needs
  only a Node step, parallel to the existing Ruby suite.
- _Source:_ [Vitest – Test Environment guide](https://vitest.dev/guide/environment)

### DOM Simulation: jsdom vs happy-dom

A headless DOM is required because tests run in Node. Two options:

| | jsdom | happy-dom |
|---|---|---|
| Maturity / spec coverage | Most mature, widest Web-API coverage | Newer, some APIs missing |
| Speed | Baseline | ~2–10× faster on large suites |
| Mantine fit | **What Mantine's official guide uses** | Works for most RTL tests; edge gaps possible |

- **Recommendation:** start with **jsdom** because Mantine's own testing guide targets it and
  Mantine leans on browser APIs (portals, `matchMedia`, `ResizeObserver`, `getComputedStyle`)
  where jsdom's fidelity reduces surprises. If suite runtime later becomes a pain point, adopt
  the documented hybrid: set `happy-dom` as the default environment and override the few files
  that need jsdom with a `// @vitest-environment jsdom` file-header comment. _Confidence:
  medium-high._
- _Sources:_ [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/) ·
  [happy-dom vs jsdom (2026)](https://www.pkgpulse.com/guides/happy-dom-vs-jsdom-2026) ·
  [Vitest environment guide](https://vitest.dev/guide/environment)

### Component-Testing Libraries

- **@testing-library/react** (RTL) — render components, query by **role/label/text** rather
  than Mantine's auto-generated CSS class names (class names are unstable and must not be
  asserted on). _Confidence: high._
- **@testing-library/user-event** — realistic user interactions (typing, clicking, keyboard),
  needed for the form-heavy pages (`useForm` on `LoginPage` etc.).
- **@testing-library/jest-dom** — DOM matchers (`toBeInTheDocument`, `toBeDisabled`, …);
  imported in the setup file as `@testing-library/jest-dom/vitest`.
- _Source:_ [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/)

### Mantine 9 Testing Requirements (version-specific)

Mantine components break in a bare jsdom unless specific globals are mocked, and they render
better in tests when the provider is put into test mode. Both are documented for **Mantine
9.0.0**:

- A **setup file** must mock `window.matchMedia`, `ResizeObserver`,
  `HTMLElement.prototype.scrollIntoView`, `getComputedStyle`, and `document.fonts`. (Exact
  documented snippet to be captured in the Implementation step.)
- A **custom `render()` wrapper** must wrap the UI in `MantineProvider`. Crucially, passing
  **`env="test"`** disables transitions and portal mount/unmount delays that otherwise make
  Modal/Drawer/Popover/Notifications tests flaky. The wrapper must mirror the app's real
  provider tree (`MantineProvider theme` + `ModalsProvider` + `Notifications`) from
  `app/frontend/entrypoints/application.tsx` so tests render like production.
- _Sources:_ [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/) ·
  [Mantine – Testing portal components (Modal/Drawer/Popover)](https://help.mantine.dev/q/portals-testing)

### Backend / Inertia Mocking Layer

Because Inertia **injects props into the page** (they are not fetched by the component), the
natural seam to "cut the backend" is the `@inertiajs/react` module itself, not the network:

- **`vi.mock('@inertiajs/react')`** — stub `usePage` to return fixture props, stub `useForm`,
  `router`, render `Link` as an `<a>` and `Head` as a fragment. This is the community-standard
  approach for client-side Inertia unit tests and needs no HTTP layer. _Confidence: high._
- **MSW (Mock Service Worker)** — only warranted later if/when components make *direct*
  `fetch`/XHR calls (the repo currently routes navigation through `router`, and uploads through
  `@uppy/aws-s3`). Kept as a phase-2 option for testing real request/response flows.
- _Sources:_ [Inertia – How to test components that depend on usePage (#675)](https://github.com/inertiajs/inertia/discussions/675) ·
  [Inertia.js – Testing docs](https://inertiajs.com/docs/v2/advanced/testing) ·
  [Unit testing React in Laravel with Vitest](https://tangiblebytes.co.uk/2024/unit-testing-react-code-in-laravel-using-vitest/)

### Typed-Fixture Tooling

The Typelizer-generated interfaces in `app/frontend/types/generated/` (42 types, camelCase,
nullable) are the prop contract. Fixtures should be **typed against them** so a serializer
change that regenerates a type breaks fixtures at compile time.

- **Hand-rolled builders** (`buildBoardTask(overrides?: Partial<BoardTask>): BoardTask`) — zero
  dependencies, fully typed, readable; preferred default.
- **`fishery`** — typed factory library (`Factory.define<BoardTask>()`); good if many
  interrelated fixtures with sequences/associations are needed.
- **`@faker-js/faker`** — realistic random values; pair with the above for variety, but keep
  determinism for snapshot stability.
- Open issue to resolve in later steps: Typelizer emits **computed Alba attributes as
  `unknown`** (e.g. `BoardTask.assigneeName`, `commentsCount`), which weakens the contract;
  options are to type them on the Rails side or augment them in fixtures.
- _Source:_ tool docs to be cited in the Implementation step.

### UI Upgrade-Validation Tooling

Layered, lowest-cost-first, to catch breakage when Mantine/React/etc. are bumped:

- **`yarn tsc`** (already in CI) — catches removed/renamed props and signature changes at the
  type level on upgrade. The cheapest and already-present guard.
- **Smoke render tests** (RTL "renders without crashing") — catch *runtime* breakage that types
  miss (a component that now throws, changed portal behavior, etc.).
- **Visual / DOM snapshots** — DOM snapshots are brittle with Mantine's generated class names;
  prefer accessibility-tree assertions. Heavier visual-regression (Vitest browser mode,
  Playwright component testing, or Storybook + Chromatic) is a deliberate **phase-2** decision.
- _Sources:_ [Vitest browser mode](https://medium.com/@fswwdza/why-should-you-use-vitest-browser-mode-right-now-b89b96a8f954) ·
  [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/)

### Adoption & Currency Notes

- Vitest + RTL is the mainstream 2025–2026 stack for Vite-based React apps; Mantine ships an
  official Vitest guide, confirming first-class support for this exact combination.
- happy-dom is increasingly positioned as the faster default, but jsdom remains the
  compatibility-safe choice and is the one Mantine documents — hence the staged recommendation
  above.
- Inertia's official testing docs focus on the *server* side (asserting rendered props); the
  *client* side is covered by community practice (module mocking), which the design relies on.

**Step 2 confidence summary:** runner (high), libraries (high), Mantine setup specifics
(high, version-pinned to 9.0.0), DOM environment (medium-high — a reversible choice), fixtures
& visual regression (medium — refined in later steps).

## Integration Patterns Analysis

For a backendless test harness, "integration patterns" means the **coupling points between the
frontend and the backend/runtime, and the patterns for cutting each one** so tests run in pure
Node. This section inventories every seam (grounded in a full `app/frontend` scan) and the
mock pattern for each, then gives a single setup-file checklist. It deliberately replaces the
generic "REST/GraphQL/microservices" axes, which do not apply to a client test harness.

### Primary seam — the `@inertiajs/react` module (THE coupling)

Every page renders through Inertia, and **props are server-injected and read via
`usePage().props` — never fetched**. That makes the module boundary the truthful, minimal seam:
mock the module, not the network. Exact surface in use (deduped imports): `createInertiaApp`,
`usePage` (39 files), `useForm` (14 files), `router`, `Link` (6 files), `Head`, `Deferred`
(×31), `InfiniteScroll`, `usePoll`. Router method calls counted: `visit` ×36, `post` ×29,
`reload` ×27, `patch` ×14, `delete` ×14, `get` ×7, `on` ×4, `put` ×1.

**Pattern: `vi.mock('@inertiajs/react')` with `importActual` + spread**, overriding only:
`usePage` → returns fixture props; `useForm` → a controllable `{ data, setData, errors,
processing, post/get/patch/put/delete (spies), … }`; `router` → all methods are `vi.fn()` and
**`router.on(...)` must return an unsubscribe function** (the global `InertiaRouteIndicator`
calls it in an effect cleanup); `Link` → `<a>`; `Head` → `null`; `Deferred`/`InfiniteScroll`
→ render children (never resolve in tests); `usePoll` → no-op (so no timers/reloads).

> **Adversarial finding (maintenance):** this mock is the **single highest-churn maintenance
> item** in the whole design — it silently diverges from reality on any `@inertiajs/react`
> minor (the repo is on `^3.0.1`/`^3.4.0`). Two mitigations: (a) keep the override surface
> **minimal** — let `Link`/`Head`/`Deferred` pass through as the real exports where they render
> fine in jsdom; (b) add a **type-level guard** in setup (`const _c: typeof
> import('@inertiajs/react')['useForm'] = useFormStub`) so a signature change fails `tsc`
> (Layer 0) instead of passing green. Optionally back un-stubbed exports with a `Proxy` that
> throws `Not mocked: <name>` rather than silently returning `undefined`.

### Realtime seam — `@rails/actioncable` (NOT `@inertia-cable/react`)

**Correction to the initial assumption:** `@inertia-cable/react` is listed in `package.json`
but is **unimported**; realtime uses `@rails/actioncable` directly through
`shared/lib/actionCableConsumer.ts` (`getConsumer()` → `createConsumer()`), which opens a real
WebSocket to `/cable` at module load and **will try to connect in jsdom**. Call sites:
`useInertiaCableStream`, `useSessionListCableUpdates`, `Profile/Show.tsx`.

**Pattern:** `vi.mock('@rails/actioncable')` so `createConsumer()` returns
`{ subscriptions: { create: () => ({ unsubscribe: vi.fn() }) } }` (or mock `getConsumer`).
This belongs in the **baseline `setup.ts`**, not added incrementally — `BoardPage`, `ShowPage`,
`SessionPage`, and `SessionShowContent` all hit it at mount, so any smoke test in that
neighborhood throws without it. The `received()` callback can optionally be driven manually to
assert realtime behavior.

### Network seam — `fetch` (no axios/XHR anywhere)

`apiFetch` (`shared/lib/apiFetch.ts`) wraps `fetch`, reads the CSRF token from a
`meta[name=csrf-token]` (absent in jsdom → returns `''`, graceful), and is used in 8 files; raw
`fetch(` appears in 4 more (notably `Workflows/BuilderPage.tsx` ~10 calls). **Pattern:**
`vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({}), { status: 200 })))`.
Route-path builders (`shared/routes.ts`, generated by `ts_routes-rails`) are pure string
functions — leave them real.

### Upload seam — `@uppy/core` + `@uppy/aws-s3`

Single integration (`shared/resources/assets/AssetsContent.tsx`). **Pattern:** mock both
modules so `new Uppy()` returns an object with `use/on/addFile/upload/cancelAll` as `vi.fn()`,
avoiding `File`/worker/S3 concerns; the underlying presign/POST go through the `fetch` stub.

### Browser/DOM API polyfills jsdom lacks (Mantine 9 requires)

Mantine components throw or misbehave in bare jsdom without these (all installed in `setup.ts`):
`window.matchMedia`, `ResizeObserver` (ScrollArea, Combobox/Select sizing, recharts),
`IntersectionObserver` (`Docs/DocsToc.tsx` + Inertia `InfiniteScroll`),
`HTMLElement.prototype.scrollIntoView` (Select/Combobox; `DocsToc`), and a `getComputedStyle`
pass-through + `document.fonts` stub. Mantine usage that exercises these: Modal ×26, Select
×24, Tooltip ×24, Menu ×6, MultiSelect ×6, Drawer ×4, ScrollArea ×3, Tabs ×3, Popover ×2.

### Global side-effects to neutralize

`navigator.clipboard.writeText` (×2), `window.confirm` (`Profile/Show.tsx`),
`window.location.href` hard-redirect (`IntegrationsContent.tsx` — jsdom warns), `localStorage`
(12 usages — clear in `afterEach`), and `@sentry/react` (init early-returns when
`env==='development'`; `ErrorBoundary` is harmless but consider mocking it). Note: tests render
page components **directly** and must **not** import `entrypoints/application.tsx`, which
sidesteps the `#app` `data-page` JSON parse and the Sentry boot entirely. `@xterm/*`, `nuqs`,
`zustand` are in `package.json` but **unimported** — no mocks needed today.

### Alternative integration pattern — MSW (deliberately reserved)

MSW (Mock Service Worker) runs the *real* Inertia router and intercepts XHR/visits, returning
Inertia JSON page envelopes (`{ component, props, url, version }` + `X-Inertia: true`). It is
**heavier and reserved for a small opt-in `*.flow.test.tsx` tier** — worthwhile only when a test
genuinely asserts the router/`useForm` round-trip (e.g. login `422`-error handling, create →
redirect). For the 39 read-only `usePage` pages it invents a network layer that does not exist
in production and fights the "simple/maintainable" goal. Install `msw` only when those flow
tests are actually written.

### Honest seam limitations (what mocking the backend does NOT cover)

- **Route correctness is structurally uncovered.** Mocked `router.post('/login')` asserts the
  call, not that `/login` exists, that the HTTP verb matches the Rails route, or that the
  redirect is right. A server-side `/login`→`/sessions` rename or a `post`→`put` flip leaves all
  FE tests green while the app 404s. `tsc` does not catch it either (these are string literals).
- **Prop reactivity on partial reloads is out of scope.** The `usePage` stub returns a static
  object; real `usePage()` re-renders on `router.reload({ only: [...] })` and realtime updates.
  jsdom tests cover *initial-render* prop consumption only.
- **Layout-level behavior is skipped by default.** `renderPage` renders the page body, but
  `AuthLayout` (used by ~42 pages) is where `flash` toasts, the `currentUser` auth-gate loader,
  and sidebar chrome live. Provide an opt-in `renderPage(ui, { withLayout: true })` to cover it.

### Mock checklist (single `app/frontend/test/setup.ts`)

1. DOM polyfills **before any render**: `matchMedia`, `ResizeObserver`, `IntersectionObserver`,
   `scrollIntoView`, `getComputedStyle` pass-through, `document.fonts`.
2. `vi.mock('@inertiajs/react')` (minimal overrides + `importActual` spread + type guard).
3. `vi.mock('@rails/actioncable')` (baseline, not incremental).
4. `vi.stubGlobal('fetch', …)`; mock `@uppy/core` + `@uppy/aws-s3`.
5. Neutralize `navigator.clipboard`, `window.confirm`, `window.location`; clear `localStorage`
   in `afterEach`; `import '@testing-library/jest-dom/vitest'`.

_Sources:_ [Inertia – testing components that depend on usePage (#675)](https://github.com/inertiajs/inertia/discussions/675) ·
[Inertia.js – Testing docs](https://inertiajs.com/docs/v2/advanced/testing) ·
[Setup Vitest with Inertia.js (#1410)](https://github.com/vitest-dev/vitest/discussions/1410) ·
[Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/) ·
local verification: `@inertiajs/react` v3.0.1 export surface (`node_modules/@inertiajs/react/types/index.d.ts`),
`shared/lib/actionCableConsumer.ts`, `shared/lib/apiFetch.ts`, `entrypoints/application.tsx`.

**Step 3 confidence summary:** seam inventory (high — full-codebase grounded); the
`@rails/actioncable` correction (high — verified unimported `@inertia-cable/react`); mock
patterns (high); MSW boundary (medium-high); the three honest limitations are design facts to
carry into the final synthesis.

## Architectural Patterns and Design

This section defines the **architecture of the test system itself**: the layered model, the
render-wrapper architecture, the typed-fixture architecture, the module layout, and the design
principles that keep the suite from rotting. (The generic "microservices/SOLID/scalability"
axes are reinterpreted as the test harness's own structure and quality attributes.)

### Layered architecture (the test "pyramid")

Six layers, ordered by ROI. The first three plus fixtures are the high-leverage core; visual
and E2E are deferred.

| Layer | What it validates | Tooling | DOM? | Status |
|---|---|---|---|---|
| **L0 — Type check** | Removed/renamed/retyped props on upgrade (Mantine `color`, `positionDependencies`; React 19; recharts v3; Tabler icons) | `yarn tsc` | no | **already gating CI** |
| **L1 — Pure-logic unit** | Deterministic helpers; zod validators; extracted sort/filter/format | vitest | no | **now, zero new deps** |
| **L2 — Component/page** | Mount-without-crash + role/text + form/router side-effect spies | vitest + jsdom + RTL + Inertia mock | yes | **now, add deps** |
| **L3 — Typed fixtures** | Server↔client prop drift at **compile** time | hand-rolled builders over `@/types/generated` | compile gate | **now** |
| **L4 — Visual regression** | Pure-CSS drift (e.g. Mantine 9 light-variant change) | vitest 4 browser mode `toMatchScreenshot`, pinned Linux | real browser | **defer / see §goal-fit** |
| ~~E2E~~ | full flows | Playwright | — | **skip for upgrade validation** (wants a backend) |

**Test-surface tiers feeding L1/L2** (full `app/frontend` scan):

- **Tier 1 — pure, no DOM (highest ROI):** `Docs/data/{searchIndex,navStructure}.ts`
  (`searchDocs`, `findNavItem`/`findNavSection`/`getPrevNext` — already pure + exported,
  branchy); `shared/lib/{formatDate,formatElapsedTime,urlValidation}.ts`.
- **Tier 1b — extract-then-test:** `IndexPage` `sortedAndFiltered` → `sortAndFilterProjects()`;
  `BoardPage` `matchesBoardFilters`/`serializeFilters`/`parseFilters` (~lines 2459–2474,
  2716–2720); `formatCostCents`/`formatTokens`/`formatDuration`/`avatarInitials` (BoardPage) and
  `formatRelativeTime` (ProjectCard) lifted into `shared/lib`. **`loginSchema` and the
  `McpServerFormModal` `.superRefine` live here, not in Tier 1** — they are inline `const`s
  inside their components and must be **extracted/exported first** (adversarial correction).
- **Tier 2 — presentational:** `shared/ui/{Logo,Loader,PageShell}.tsx`, `ProjectCard.tsx`.
- **Tier 3 — Inertia pages:** start with `Auth/LoginPage.tsx` and `Projects/IndexPage.tsx`.
  **Defer** `BoardPage` (3187 lines, @dnd-kit/recharts/ActionCable), `Workflows/BuilderPage`,
  Analytics — those are L4/Playwright candidates, brittle in jsdom.
- **Tier 4 — hooks:** `useLocalStorage`/`useLocalStorageSet` via `renderHook` (cheapest jsdom
  justification); `useInertiaCableStream` later (fake timers + consumer mock).

### Render-wrapper architecture

A single `render()` mirrors the real provider tree from
`app/frontend/entrypoints/application.tsx` **minus** Sentry `ErrorBoundary` and the Inertia boot:
`MantineProvider(theme=mantineTheme, defaultColorScheme="dark", cssVariablesResolver, env="test")`
→ `ModalsProvider` → `Notifications` → children. Key decisions:

- **`env="test"`** disables Mantine transitions/portal delays → no timing flake.
- Use the **real** `mantineTheme` + `cssVariablesResolver` so a Mantine theming change surfaces
  as a test failure (the whole point of the upgrade net).
- Portal UI (Modal/Notifications/Select dropdown) renders into `document.body` → query via
  `screen`, not the render container.
- Persistent layouts (`(page as any).layout`) are **not** auto-applied (page-body isolation);
  expose an opt-in `renderPage(ui, { withLayout: true })` for `AuthLayout` flash/auth/sidebar.

### Typed-fixture architecture (drift-as-compile-error)

Builders return the generated type; the **return-type annotation is the contract** (proven
against the real `BoardTask.ts` under this repo's strict `tsc`: `number→string` → `TS2322`;
forgotten newly-required field → `TS2741`; faithful fixture → exit 0). Import types as
**default** imports (`import type BoardTask from '@/types/generated/BoardTask'`).

```ts
export const buildBoardTask = (overrides: Partial<BoardTask> = {}): BoardTask => ({
  id: 1, title: 'Task', /* …all columns… */ ...overrides,   // wrong/unknown keys also error
});
```

**Architectural caveat — the `unknown` gap.** ~35% of generated *field lines* are `unknown`,
and **38 of 42 types** contain at least one (computed Alba blocks → `unknown`; a serializer
mapping to a non-existent model — `TaskDetailResource` — degrades the *whole* type). `unknown`
accepts any value, so those fields carry **no** compile-time protection. The architecturally
correct fix is **Rails-side** (`typelize` DSL on the Alba blocks, already used in
`terminal_session_resource.rb`; plus a `TaskDetail→BoardTask` model remap in
`typelizer.rb`). A frontend "augment type" is an interim crutch that itself drifts — cap it to
the 2–3 types tests need now and tag it with a TODO pointing at the Rails task.

### Module layout

```
app/frontend/test/
  setup.ts          # DOM polyfills + @inertiajs/react + @rails/actioncable mocks + jest-dom
  renderPage.tsx    # provider-wrapped render + userEvent + RTL re-exports
  factories/        # buildBoardTask.ts, buildProject.ts, … (only types tests use)
vitest.config.ts    # repo root; tsconfigPaths()+reactSwc() ONLY (no ViteRuby/inertia)
```
Colocate specs next to source: `formatDate.test.ts`, `LoginPage.test.tsx`; reserve
`*.flow.test.tsx` for the opt-in MSW tier. `include: app/frontend/**/*.{test,spec}.{ts,tsx}`;
**`exclude: test/playwright/**`** so vitest never imports the staging-hitting helpers.

### Design principles (anti-rot)

1. **Query by role/accessible-name, never `toMatchSnapshot()` of Mantine HTML.** Hashed `.m-*`
   class names + internal-markup churn flap DOM snapshots on every minor bump — the single most
   important low-maintenance rule. **Enforce it as a lint rule** (`no-restricted-syntax` against
   `toMatchSnapshot` in `*.test.tsx`) so the convention can't decay.
2. **Minimal mock surface + type guards.** The `@inertiajs/react` mock is the top maintenance
   liability; override only what's needed, pass real exports through, and add a `tsc` type guard
   so signature drift fails loudly.
3. **Isolation by default.** Tests render page bodies, not the app shell; no network, no
   containers, no backend — milliseconds per test.
4. **Drift becomes a compile error**, not a silent runtime mismatch — but only once a page (or a
   fixture a page shares) actually imports the generated type.

_Sources:_ [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/) ·
[Mantine – portals testing](https://help.mantine.dev/q/portals-testing) ·
[Testing Library – role/accessibility queries](https://testing-library.com/docs/queries/about/#priority) ·
[Vitest – config & environment](https://vitest.dev/config/) ·
empirical: builder contract verified against `BoardTask.ts` under this repo's `tsc`.

**Step 4 confidence summary:** layered model + tiers (high — codebase-grounded); render-wrapper
(high — Mantine-canonical); fixture contract (high — empirically proven); the `unknown`-gap and
the role-not-snapshot/lint principle are the load-bearing design decisions.

## Implementation Approaches and Technology Adoption

Concrete, copy-pasteable implementation grounded in the real repo. Versions confirmed current
via the npm registry on 2026-06-25.

### Dependencies to add

`vitest@4.1.9` is already installed. Add (yarn 4, repo root):

```bash
yarn add -D jsdom@^29 \
  @testing-library/react@^16 \
  @testing-library/dom@^10 \
  @testing-library/user-event@^14 \
  @testing-library/jest-dom@^6
```

`@testing-library/dom` must be explicit — it is a required peer of RTL 16 and yarn 4 will not
auto-add it. RTL 16 + jest-dom 6 give React 19 `act()` support (repo is on `react@19.2.7`).
Confirmed latest: RTL 16.3.2, dom 10.4.1, user-event 14.6.1, jest-dom 6.9.1, jsdom 29.1.1.

### `vitest.config.ts` (repo root — separate from `vite.config.ts`)

A dedicated config is mandatory: `vite.config.ts` registers `ViteRuby()` + `inertia()`, which
inject a Rails-coupled `/vite-development/` base + manifest expectations that fail under Vitest
([vitest#436](https://github.com/vitest-dev/vitest/issues/436)). `vitest.config.ts` takes
priority when both exist; the production build stays untouched.

```ts
import { defineConfig } from 'vitest/config';
import reactSwc from '@vitejs/plugin-react-swc';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [tsconfigPaths(), reactSwc()],     // NO ViteRuby(), NO inertia()
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./app/frontend/test/setup.ts'],
    css: false,                               // assert roles/behavior, not pixels
    restoreMocks: true,
    include: ['app/frontend/**/*.{test,spec}.{ts,tsx}'],
    exclude: ['node_modules/**', 'test/playwright/**'],
  },
});
```

`tsconfigPaths()` keeps `shared/ui`, `layouts/*`, `@/types/generated` resolving (baseUrl
`app/frontend`); `reactSwc()` transforms JSX. Tier-1 pure tests run with this config alone.

### `app/frontend/test/setup.ts` (polyfills + mocks)

Mantine-canonical jsdom polyfills (copied verbatim from the Mantine 9.0.0 guide — it touches
every one), plus the baseline Inertia and ActionCable mocks:

```ts
import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

// --- Mantine-required jsdom polyfills ---
const { getComputedStyle } = window;
window.getComputedStyle = (el) => getComputedStyle(el);
window.HTMLElement.prototype.scrollIntoView = () => {};
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query) => ({
    matches: false, media: query, onchange: null,
    addListener: vi.fn(), removeListener: vi.fn(),
    addEventListener: vi.fn(), removeEventListener: vi.fn(), dispatchEvent: vi.fn(),
  })),
});
Object.defineProperty(document, 'fonts', { value: { addEventListener: vi.fn(), removeEventListener: vi.fn() } });
class RO { observe() {} unobserve() {} disconnect() {} }
window.ResizeObserver = RO as never;
window.IntersectionObserver = RO as never;   // DocsToc + Inertia InfiniteScroll

// --- Realtime: @rails/actioncable (BASELINE — many pages hit getConsumer() at mount) ---
vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({ subscriptions: { create: () => ({ unsubscribe: vi.fn() }) }, disconnect: vi.fn() }),
}));

// --- Primary seam: @inertiajs/react (minimal overrides + importActual passthrough) ---
export const inertiaState = { pageProps: {} as Record<string, unknown>, form: makeFormStub({}) };

vi.mock('@inertiajs/react', async (orig) => {
  const actual = await orig<typeof import('@inertiajs/react')>();
  return {
    ...actual,                                   // Link/Head/Deferred render fine in jsdom — keep real where possible
    usePage: () => ({ props: inertiaState.pageProps, url: '/', component: 'Test', version: '1' }),
    useForm: () => inertiaState.form,
    router: {
      visit: vi.fn(), post: vi.fn(), get: vi.fn(), put: vi.fn(), patch: vi.fn(),
      delete: vi.fn(), reload: vi.fn(), replace: vi.fn(), cancel: vi.fn(),
      on: vi.fn(() => () => {}),                 // MUST return an unsubscribe (InertiaRouteIndicator effect cleanup)
    },
    usePoll: () => {},
  };
});

// type guard: a useForm signature change fails `tsc` (L0) instead of passing green
type _Guard = typeof import('@inertiajs/react');

export function makeFormStub<T extends Record<string, unknown>>(initial: T) {
  let data = { ...initial };
  const submit = vi.fn();
  const stub: any = {
    data, errors: {} as Record<string, string>, processing: false,
    setData: vi.fn((k: any, v?: unknown) => { data = typeof k === 'string' ? { ...data, [k]: v } : { ...data, ...k }; stub.data = data; }),
    transform: vi.fn(), reset: vi.fn(), clearErrors: vi.fn(), setError: vi.fn(),
    recentlySuccessful: false, hasErrors: false, isDirty: false,
    post: submit, get: submit, put: submit, patch: submit, delete: submit, submit,
  };
  return stub;
}
```

> **Known constraint (adversarial):** `makeFormStub` is **not reactive** — `setData` does not
> trigger a React re-render, so `userEvent.type(...)` won't update the `useForm` `data`. Two
> honest consequences: (1) test the **validation-failure** branch by submitting empty input
> (works perfectly with a static stub); (2) for the happy path, **pre-seed** valid data into the
> stub rather than typing. Do not assert that typing → state → validation works through this
> stub; that controlled-input loop needs MSW or a stateful stub.

### `app/frontend/test/renderPage.tsx` (provider-wrapped render)

```tsx
import { render } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import { mantineTheme, cssVariablesResolver } from 'shared/theme/mantineTheme';
import { inertiaState, makeFormStub } from './setup';
import type { ReactElement } from 'react';

export function renderPage<TProps extends Record<string, unknown>>(
  ui: ReactElement,
  opts: { props?: TProps; form?: ReturnType<typeof makeFormStub> } = {},
) {
  inertiaState.pageProps = opts.props ?? {};
  if (opts.form) inertiaState.form = opts.form;
  return render(ui, {
    wrapper: ({ children }) => (
      <MantineProvider theme={mantineTheme} defaultColorScheme="dark"
                       cssVariablesResolver={cssVariablesResolver} env="test">
        <ModalsProvider><Notifications />{children}</ModalsProvider>
      </MantineProvider>
    ),
  });
}
export { userEvent };
export * from '@testing-library/react';
```

### Typed factory template (`app/frontend/test/factories/boardTask.ts`)

```ts
import type BoardTask from '@/types/generated/BoardTask';

export const buildBoardTask = (overrides: Partial<BoardTask> = {}): BoardTask => ({
  id: 1, title: 'Task', description: null, taskType: 'feature', priority: null,
  assigneeId: null, boardColumnId: 10, position: 0, parentTaskId: null, tags: null,
  createdAt: '2026-06-25T00:00:00Z', updatedAt: '2026-06-25T00:00:00Z',
  assigneeName: 'Ada', commentsCount: 3, childrenCount: 0, assetsCount: 0,   // unknown fields
  recentWorkflowRuns: [], pendingGates: [],
  ...overrides,
});
```

### Example tests

```ts
// L1 — pure logic, no DOM, no mocks (highest ROI first test)
import { searchDocs } from 'pages/Docs/data/searchIndex';
test('searchDocs is case-insensitive and returns [] on empty query', () => {
  expect(searchDocs('')).toEqual([]);
  expect(searchDocs('WORKFLOW').length).toBeGreaterThan(0);
});
```

```tsx
// L2 — the CORRECTED flagship: assert the validation-FAILURE branch (proves the zod+Mantine seam)
import LoginPage from 'pages/Auth/LoginPage';
import { renderPage, userEvent, screen, makeFormStub } from 'test/renderPage';

test('submitting empty login shows validation errors and does NOT post', async () => {
  const form = makeFormStub({ email: '', password: '', rememberMe: false });
  renderPage(<LoginPage />, { form });
  await userEvent.click(screen.getByRole('button', { name: /sign in/i }));
  expect(screen.getByText(/email is required/i)).toBeInTheDocument();
  expect(form.post).not.toHaveBeenCalled();          // the assertion that actually guards the gate
});

test('valid login calls post (pre-seed valid data — stub is non-reactive)', async () => {
  const form = makeFormStub({ email: 'a@b.com', password: 'secret', rememberMe: false });
  renderPage(<LoginPage />, { form });
  await userEvent.click(screen.getByRole('button', { name: /sign in/i }));
  expect(form.post).toHaveBeenCalledWith('/login', expect.objectContaining({ onSuccess: expect.any(Function) }));
});
```

### Testing and Quality Assurance — Makefile + CI wiring

Today CI runs `make check_all` **inside the Docker `web` image** (rails-test + rubocop +
brakeman + eslint + `yarn tsc` in parallel) — **no FE tests run**, and `make fe-test` is in
`.PHONY` + `help` but has **no recipe** (dangling).

```makefile
fe-test:
	yarn test
```

**CI recommendation (adversarial flip vs the first synthesis draft): fold `fe-test` into the
existing `check_all` Docker block, do NOT add a separate bare-runner job.** The web image
already carries the full `devDependencies` (it runs `yarn lint`/`yarn tsc`), so adding jsdom +
4 RTL packages is near-zero cost, and reusing the **one known-good resolved environment** avoids
a second platform/cache resolving the same `yarn.lock` differently (a classic CI-flakes-but-
passes-locally trap). `vitest` needs no Postgres/Temporal, so it rides along without `needs-db`.

### Deployment/Operations — Dependabot gating (already configured)

Dependabot already runs weekly (npm, `develop`). Add grouping so version-locked families arrive
as one coherent PR, and mark the checks **required** so a bump can't merge red:

```yaml
# .github/dependabot.yml
groups:
  mantine: { patterns: ['@mantine/*'] }
  testing-library: { patterns: ['@testing-library/*'] }
```

Then in branch protection on `develop`, mark **`typescript`** and **`fe-test`** as **required**
status checks. This converts "validate on upgrade" from aspirational to enforced.

### Risk Assessment and Mitigation

- **Inertia mock drift** (top maintenance item): minimal surface + `tsc` type guard.
- **`unknown` fields / no page imports generated types**: fixtures protect nothing until a page
  shares the type — pull a thin slice of the page-migration forward (migrate `LoginPage`/
  `IndexPage` to `@/types/generated`) so drift becomes a real compile error.
- **Visual/CSS upgrade gap**: L1–L3 are blind to pure-CSS regressions — see the synthesis step
  for the goal-fit decision (minimal L4 now vs. explicit "ships green" caveat).
- **Route correctness / prop reactivity / layout behavior**: structurally uncovered — documented
  as known holes, not silently implied as covered.

## Technical Research Recommendations

### Implementation Roadmap (fastest payoff first)

- **Phase 0 — Drift gate (hours, zero runtime infra):** add `factories/*` builders over
  `@/types/generated` for the few types tests need; they compile-check under the existing `tsc`
  CI gate even before any vitest config. _(Caveat: low standalone value until a page imports the
  type — pair with the LoginPage/IndexPage type-migration to make it real.)_
- **Phase 1 — Tier-1 pure logic (hours, zero new deps):** add `vitest.config.ts`; test
  `Docs/data` (`searchDocs`, nav traversal), `shared/lib` (`formatDate`, `urlValidation`,
  `formatElapsedTime` with `vi.useFakeTimers`).
- **Phase 2 — jsdom + first component/page tests (½ day):** install RTL/jsdom deps; write
  `setup.ts` + `renderPage.tsx`; `useLocalStorage` via `renderHook` → `shared/ui` smoke →
  `LoginPage` (failure + happy) → `IndexPage`. Wire `make fe-test` into `check_all` + required
  checks + Dependabot grouping.
- **Phase 3 — Extract-and-test buried logic (small refactor, big payoff):** lift
  `sortAndFilterProjects`, `matchesBoardFilters`/`serializeFilters`, the BoardPage/ProjectCard
  formatters, **and `loginSchema`/`.superRefine`** into `shared/lib`, then unit-test.
- **Phase 4 (later) — Rails `typelize` annotations + `TaskDetail` remap**, then migrate pages off
  local interfaces onto generated/augmented types.
- **Phase 5 (later) — L4 visual regression** in a pinned Linux job (decision pending §goal-fit).

### Technology Stack Recommendations

Vitest 4 (installed) + jsdom 29 + RTL 16/dom 10/user-event 14/jest-dom 6; separate
`vitest.config.ts`; hand-rolled typed builders (Fishery as upgrade path); MSW only for opt-in
flow tests.

### Skill Development Requirements

Team is Rails-fluent (FactoryBot/Minitest); the React-testing concepts (RTL role queries,
`vi.mock`, fixtures-as-factories) map directly. Main new discipline: **never snapshot Mantine
HTML — query by role/name** (lint-enforced).

### Success Metrics and KPIs

- `fe-test` + `typescript` are required checks on `develop` (a Mantine/React bump cannot merge
  red).
- Every `shared/ui` primitive + the high-traffic pages have ≥1 smoke test.
- A serializer field rename surfaces as a fixture/page compile error (once page-migration lands).
- Suite runs in seconds, host-only, zero containers/backend.

_Sources:_ [Mantine – Testing with Vitest](https://mantine.dev/guides/vitest/) ·
[vitest#436 (vite-plugin-ruby)](https://github.com/vitest-dev/vitest/issues/436) ·
[Vitest config](https://vitest.dev/config/) ·
[Inertia – testing #675](https://github.com/inertiajs/inertia/discussions/675) ·
[Fishery](https://github.com/thoughtbot/fishery) ·
npm registry (versions, 2026-06-25); empirical `tsc` contract check against `BoardTask.ts`.

**Step 5 confidence summary:** install/config/setup/render/factory code (high — version-pinned,
Mantine-canonical, contract empirically verified); corrected LoginPage test + CI-into-Docker
flip + actioncable-in-baseline reflect the adversarial review; roadmap is grounded in the tier
analysis.

## Research Synthesis & Recommendation

### Executive Summary

The app's frontend (Rails → Inertia.js → React 19 + Mantine 9, built with Vite) can be put under
a fast, **backendless** test net using tooling that is already half-present: `vitest@4` ships in
`devDependencies`, but there is no config, no setup file, and none of the Testing Library / jsdom
packages. The recommended system is a **layered pyramid** — type-check (`tsc`, already gating
CI) → pure-logic unit → jsdom component/page tests with the backend mocked at the
`@inertiajs/react` module boundary → typed fixtures built on the Typelizer-generated interfaces —
with visual-regression deferred. The central design insight is that **Inertia injects props, it
never fetches them**, so the truthful seam is to `vi.mock('@inertiajs/react')` (stub
`usePage`/`useForm`/`router`) rather than to run MSW or a real backend. Everything runs in Node
in seconds, with no containers.

Two themes determine whether this suite delivers value or rots. First, **low-maintenance
discipline**: query by ARIA role/accessible-name, never snapshot Mantine's hashed class names
(lint-enforce it); keep the Inertia mock surface minimal with a `tsc` type-guard, because that
mock is the highest-churn maintenance item. Second, **honesty about coverage**: a jsdom suite
with `css: false` is structurally blind to the visual/CSS regressions that library upgrades most
often cause — which is precisely the user's stated #1 goal. This report therefore treats the
**visual-regression layer as a real decision, not a footnote** (see Goal-Fit below), and is
explicit about what the default system does *not* catch.

The Typelizer types can anchor fixtures so a serializer change breaks a test at compile time —
but only partially today: **38 of 42 generated types contain `unknown` fields** (computed Alba
attributes; plus `TaskDetail`, whose serializer maps to a non-existent model and degrades
wholesale), and **zero pages currently import the generated types** (52 re-declare local
interfaces, 44 use `as unknown as Props`). So the drift-detection payoff is real but gated on two
follow-on moves: Rails-side `typelize` annotations, and migrating at least the first pages onto
the generated types.

**Key Technical Findings**

- Runner is decided (Vitest 4); the gap is config + jsdom + Testing Library + a setup/render
  harness — all node-only, no containers, no backend.
- The truthful mock seam is the `@inertiajs/react` module (props are injected, not fetched); MSW
  is over-engineering for the 39 read-only `usePage` pages and belongs in a tiny opt-in flow tier.
- Realtime uses `@rails/actioncable` directly (not the listed-but-unused `@inertia-cable/react`);
  its mock must live in the baseline setup.
- `tsc` already catches removed/renamed *typed* props on upgrade but is blind to runtime and
  **100% blind to visual/CSS** — the exact gap a Mantine bump exploits.
- Typed fixtures give a proven compile-time drift contract for column fields, but `unknown`
  fields (≈35% of field lines; 38/42 types) and the fact that no page imports the types limit the
  payoff until two follow-on steps land.

**Technical Recommendations (top 5)**

1. Add a separate `vitest.config.ts` (jsdom; `tsconfigPaths()` + `reactSwc()` only — never
   `ViteRuby()`/`inertia()`), a Mantine-canonical `setup.ts`, and a provider-mirroring
   `renderPage()`; mock `@inertiajs/react` and `@rails/actioncable` in the baseline.
2. Roll out by ROI: Phase 0 typed factories → Phase 1 pure-logic → Phase 2 jsdom + first
   component/page tests → Phase 3 extract-and-test buried logic.
3. Enforce the anti-rot rules: role/name queries (lint-banned `toMatchSnapshot` on Mantine),
   minimal Inertia mock + `tsc` type-guard, `env="test"` to kill transition flake.
4. Wire `fe-test` into the existing Docker `check_all`, group `@mantine/*` and
   `@testing-library/*` in Dependabot, and make `typescript` + `fe-test` **required** checks on
   `develop` — turning "validate on upgrade" into an enforced gate.
5. Make a deliberate call on visual regression (Goal-Fit below): either pull a minimal Layer-4
   slice forward, or accept and document that pure-CSS Mantine regressions ship green for now.

### Table of Contents

1. Research Overview & Methodology — *(top of document)*
2. Technology Stack Analysis — runner, DOM env, libraries, Mantine specifics
3. Integration Patterns Analysis — mock seams (Inertia, ActionCable, fetch, uppy, DOM)
4. Architectural Patterns and Design — layered pyramid, render wrapper, fixtures, anti-rot
5. Implementation Approaches — deps, configs, code, tests, CI, roadmap
6. Research Synthesis & Recommendation — *(this section)*

### Recommended Architecture at a Glance

| Decision | Choice | Why |
|---|---|---|
| Runner | Vitest 4 (installed) | Shares Vite transform → aliases/JSX/CSS work; node-only |
| DOM env | **jsdom** (not happy-dom) | Mantine documents jsdom; happy-dom's weak `getComputedStyle` breaks overlays |
| Config | **separate `vitest.config.ts`** | `vite.config.ts`'s `ViteRuby()`/`inertia()` fail under Vitest (vitest#436) |
| Backend seam | **`vi.mock('@inertiajs/react')`** | Props are injected, not fetched → module is the truthful seam |
| Realtime | mock `@rails/actioncable` in baseline | `getConsumer()` opens a WS at mount on many pages |
| Fixtures | hand-rolled typed builders over `@/types/generated` | return-type annotation = compile-time drift contract (proven) |
| Assertions | role/accessible-name, **never** Mantine HTML snapshots | hashed `.m-*` classes flap on every minor bump |
| Visual | deferred (see Goal-Fit) | OS-fragile, baseline churn — but the only CSS-aware layer |

### Goal-Fit: does this actually "validate UI when libraries are upgraded"?

This is the sharpest honest point in the research. The stated #1 goal is upgrade-UI-validation,
yet the recommended Phase-1/2 net (jsdom + role assertions + `css: false`) is **structurally
blind to visual/CSS regressions** — the class of breakage library upgrades most often cause (the
motivating example, Mantine 9's light-variant transparency→solid CSS-variable change, passes
`tsc` *and* every role-based jsdom test). The layers cover **logic and runtime mount** breakage,
not **appearance**.

So the priority ordering depends on which failure mode you actually fear:

- **If "does the app still work / not crash on upgrade" is the fear** → the layered jsdom plan as
  written is correct and lowest-maintenance. Ship it; treat visual as later.
- **If "does the app still look right on upgrade" is the real fear** → the ROI ordering flips. A
  thin **visual layer** on ~12 `shared/ui` primitives + 2–3 signature pages catches the exact
  Mantine-CSS regressions role assertions miss, and is arguably a *stronger primary tool* than 30
  role-assertion tests for that goal. Two viable forms: **Vitest 4 browser mode**
  (`toMatchScreenshot`, same runner you already have) or **Storybook + visual snapshots** (adds
  dev-time component-isolation value, collapses the L2+L4 split). Both require a **pinned
  Linux/Docker job** for stable baselines (font rendering differs by OS) — operational weight, not
  a backend, but real.

**Recommendation:** do Phase 1–2 now for the crash/logic safety net (cheap, high-leverage), and
make an explicit, near-term decision on a *minimal* visual slice rather than burying it at
"Phase 5, later." Until that slice exists, state plainly in the team's docs that **pure-CSS
Mantine regressions will ship green**.

> **Decision recorded (2026-06-25, Artem):** prioritize **functional verification** — "does the
> functionality still work" over "does it still look right." The target is therefore **behavioral
> component/page tests** (validation branches, filtering/sorting, form submission, mount), not
> just bare "renders without crashing" smoke and not visual snapshots. Visual regression (Layer
> 4) is **deferred/optional**, and the team accepts that pure-CSS Mantine regressions can ship
> green until/unless a minimal visual slice is added later. This sharpens the build target:
> every L2 test should assert *behavior*, not appearance; `css: false` stays; visual tooling is
> out of the initial scope.

### What This System Does NOT Catch (honest limitations)

Mocking the backend buys speed and isolation at the cost of these blind spots — all are design
facts, not bugs, and should be stated openly so jsdom-green is never mistaken for app-correct:

- **Visual / CSS** — nothing in L0–L3 validates appearance (see Goal-Fit). 
- **Route correctness** — mocked `router.post('/login')` proves the call, not that the path/verb
  exist or the redirect is right; `tsc` doesn't check string literals either. A server-side route
  rename leaves FE tests green while the app 404s. (MSW flow tests close this for chosen flows.)
- **Prop reactivity on partial reloads** — the `usePage` stub is static; real `usePage()`
  re-renders on `router.reload({ only })` and realtime updates. jsdom covers *initial-render*
  prop consumption only.
- **Layout-level behavior** — `renderPage` renders page bodies; `AuthLayout` (flash toasts,
  `currentUser` auth-gate loader, sidebar) is skipped unless you opt into `{ withLayout: true }`.
- **Inertia-mock divergence** — the `@inertiajs/react` stub can pass against a fiction if Inertia
  changes a hook's shape; the `tsc` type-guard is the mitigation.
- **Fixtures protect nothing until a page shares the type** — today no page imports the generated
  types, so a serializer change can't break any current frontend file regardless of fixtures.

### Open Decisions for You

1. **CI execution mode.** *Recommend:* fold `fe-test` into the existing Docker `check_all` (one
   known-good resolved environment; the image already carries devDeps) rather than a separate
   bare-runner job that resolves `yarn.lock` on a divergent platform.
2. **Rails-side `typelize` annotations + `TaskDetail`→`BoardTask` remap?** The only way the ~35%
   `unknown` fields (and `TaskDetail` wholesale) join the drift contract. Touches backend code —
   confirm appetite.
3. **Migrate pages off local interfaces onto `@/types/generated`?** Highest-value structural
   change (makes serializer drift a real frontend compile error), but broad. *Recommend:* pull a
   thin slice forward (LoginPage/IndexPage) so Phase-0 fixtures aren't hollow; defer the rest.
4. **Visual-regression appetite (the Goal-Fit decision).** ✅ **RESOLVED (2026-06-25):**
   prioritize functional verification; visual regression deferred/optional; "CSS ships green"
   accepted for now. Build target = behavioral L1/L2 tests. (Revisit a minimal Vitest-browser or
   Storybook slice only if a Mantine bump later causes a visible regression that hurts.)
5. **MSW flow tier?** Keep out of the default; adopt only for a few login-422 / create-then-
   redirect flows where the router round-trip is the actual assertion.

### Research Methodology & Source Verification

This report was produced via the BMAD technical-research workflow (scope → tech-stack →
integration → architecture → implementation → synthesis), backed by a parallel multi-agent
research run: **four codebase-evidence streams** (testing surfaces; type drift; mock seams;
CI/infra), **four external best-practice streams** (Vitest/Mantine setup; Inertia mocking; typed
fixtures; upgrade validation), a synthesis pass, and **three adversarial reviews** (maintenance,
false-confidence, simpler-alternative). External claims were verified against current public
sources (Mantine 9 Vitest guide, Vitest 4 docs, Inertia testing docs/discussions, happy-dom vs
jsdom comparisons) and context7; library versions were confirmed against the npm registry on
2026-06-25; the fixture compile-time drift contract was **empirically verified** by running this
repo's `tsc` against the real `BoardTask.ts`.

The adversarial reviews materially changed the recommendation: they corrected the flagship
LoginPage example (the `useForm` stub is non-reactive — test the failure branch / pre-seed the
happy path), flipped the CI recommendation toward the existing Docker job, moved the
`@rails/actioncable` mock into the baseline, broadened the `unknown` finding (35% of lines / 38 of
42 types), reclassified `loginSchema` as an extract-then-test item, and elevated the visual/CSS
gap to a first-class Goal-Fit decision.

**Confidence:** high on the tooling/setup decisions (version-pinned, Mantine-canonical, contract
empirically proven) and the seam choice (codebase-invariant: props injected, not fetched);
medium on the visual-layer recommendation (depends on the user's failure-mode priority) and on
the `unknown`-field remediation effort (Rails-side work not yet scoped).

### Conclusion

The architecture is sound and the anti-brittleness instincts (jsdom over happy-dom, separate
config, role-not-snapshot, deferring visual) are the decisions that actually determine whether
the suite survives — and they are right. The remaining work is sequencing and honesty: build the
crash/logic net now (Phases 0–2), wire it into CI as a required gate, decide deliberately on the
visual layer that alone serves the upgrade-UI goal, and land the Rails-annotation + page-type-
migration that turn the Typelizer investment into a live drift contract. Done this way, the suite
is simple, readable, runs in seconds with no backend, and tells you in CI whether a Mantine/React
bump still mounts and behaves — with its appearance coverage an explicit, owned choice rather than
a silent gap.

---

**Technical Research Completion Date:** 2026-06-25
**Source Verification:** All external claims cited; versions confirmed via npm registry 2026-06-25; fixture contract empirically verified against this repo's `tsc`.
**Technical Confidence Level:** High on tooling/seam decisions; medium on visual-layer and `unknown`-remediation scope.

_This document is an authoritative technical reference for standing up a backendless frontend test system for this Inertia + React + Mantine + Vitest application._

---

## Implementation Status (2026-06-25)

Phases 0–2 are **implemented and green**. Everything runs in Docker per the team convention.

**Built:**

- `vitest.config.ts` (jsdom, `tsconfigPaths()` + `reactSwc()` only — no `ViteRuby()`/`inertia()`).
- `app/frontend/test/setup.ts` — Mantine jsdom polyfills + baseline mocks for `@rails/actioncable`
  and `@inertiajs/react` (the mock state lives in `app/frontend/test/inertiaMock.ts` and is pulled
  into the mock factory via a lazy `import()` to avoid the `vi.mock` hoisting restriction).
- `app/frontend/test/renderPage.tsx` — provider-mirroring render (`MantineProvider` +
  `ModalsProvider` + `Notifications`, `env="test"`).
- `app/frontend/test/factories/{project,boardTask}.ts` — typed builders over `@/types/generated`
  (Phase 0 drift contract).
- Tests: pure-logic (`searchIndex`, `navStructure`, `formatDate`, `urlValidation`,
  `formatElapsedTime`), factories, and behavioral component/page: `ProjectCard`; `LoginPage`
  (validation-failure branch + pre-seeded happy path, asserting `form.post('/login')`); and
  `SkillsContent`'s `RegistrySearchModal` — **asserts that typing in search fires the backend
  request** `router.reload({ data: { q }, only: [...] })` (and that a single char does not). The
  internal `RegistrySearchModal` was given a named `export` for testability.

**Result:** **9 files / 27 tests pass**; `yarn tsc` → exit 0 (factories type-check against the
real generated types). Verified inside the running `web` container.

**Run (Docker-only):**

- `make check_all` — the verification path; runs `yarn test` (added to the parallel block)
  alongside tsc/eslint/rails-test in the Docker container.
- `make fe-test` — inner target (`yarn test`); run frontend tests alone inside the `web` container.
- Dev iteration: `docker compose exec -T web yarn test`.

**Asserting backend calls:** because `router.*` and `useForm.*` are `vi.fn()` spies, a test can
assert that a UI interaction triggered the expected backend request — e.g. search → `router.reload`,
form submit → `form.post('/login')` — all without a real backend.

**Coverage:** `@vitest/coverage-v8` added; `vitest.config.ts` `coverage` block writes to
`coverage/frontend/` (separate from SimpleCov's `coverage/`), `include: app/frontend/**` so
untested files count as 0%. `check_all` runs `yarn test --coverage`, and its summary now prints a
**Coverage (line %)** section reading SimpleCov's `coverage/.last_run.json` (backend) and vitest's
`coverage/frontend/coverage-summary.json` (frontend). Current frontend line coverage: **3.15%**
(only ~10 of ~150 files have tests yet — expected for a starting suite). Backend line coverage is
whatever the last full `rails test` produced (SimpleCov "rails" profile).

**Dependencies added** (`package.json` / `yarn.lock`): `jsdom`, `@testing-library/react`,
`@testing-library/dom`, `@testing-library/user-event`, `@testing-library/jest-dom`. The image
must be rebuilt (or the entrypoint's `yarn install` re-run) so the container carries them.

**Not yet done (follow-ons):** Phase 3 extract-and-test buried logic
(`sortAndFilterProjects`/`matchesBoardFilters`/`loginSchema`); Phase 4 Rails `typelize`
annotations + `TaskDetail` remap + migrating pages onto `@/types/generated`; Dependabot grouping
+ marking `typescript`/`fe-test` as required checks on `develop`; visual regression (deferred per
the Goal-Fit decision).
