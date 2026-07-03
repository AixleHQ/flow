# Testing Conventions

The testing doctrine for this repository. Most code here is written by AI agents, so the rules
live in the repo and in linters — not in anyone's memory. Background and evidence:
`ai/research/technical-testing-strategy-and-conventions-research-2026-07-02.md`.

**The one-sentence doctrine: test observable behavior through real collaborators, fake only at
app-owned boundaries, and let linters — not reviewers — hold the line.**

## 1. Suite shape and budgets

```
        Playwright e2e        ≤ 10 specs, critical paths only
      ──────────────────
      FE component/page       behavior given props (Vitest + RTL, jsdom)
      request/integration     auth + policy + Inertia component/props
      ──────────────────
      model / service /       the bulk of the suite: real DB, real internal
      policy / job / unit     collaborators, fakes at boundaries
```

- The backend suite runs serially (~55s full) — fast enough to run before every push
  (`make check_all`, see CLAUDE.md). Parallelization was tried and deliberately parked:
  see the note in `test/test_helper.rb` (worker-DB reconstruct instability + several
  agent sessions sharing one Postgres). Don't re-enable it casually.
- **One suite run at a time.** All sessions and git worktrees share the same
  `aixle_test` database; overlapping runs corrupt each other. `make` targets are
  flock-serialized; direct `bin/rails test` is not — check nothing else is running.
- Coverage floors are enforced ratchets: backend `COVERAGE_MIN` in the `Makefile`, frontend
  `coverage.thresholds` in `vitest.config.ts`. Raise them as coverage grows; never lower them.

## 2. What to test at which layer

| Layer | Owns | Asserts | Must NOT |
|---|---|---|---|
| Model | validations, scopes, state machines, domain methods | real DB, behavior | stub anything except time |
| Service | use-case behavior | real DB + real internal collaborators; outcomes (persisted state, enqueued jobs, outbox rows, activities); at most one seam expectation for orchestration | mock internal collaborators by default; stub the SUT |
| Request (integration) | auth, authorization wiring, status, redirects, Inertia contract | `sign_in_as` through the real login POST; `assert_inertia_page` + `assert_inertia_props` for key props | re-test service logic in depth |
| Policy | every Pundit policy | permit/forbid matrix per role (pure unit tests) | — |
| Job | enqueue + perform | ActiveJob test helpers + boundary fakes | — |
| Temporal workflow | orchestration logic | *today:* stub the `TemporalService` seam via `TemporalHelper` (§4); *target (Phase 4):* SDK time-skipping env + mocked activities | stub `Temporalio::Testing` itself |
| Temporal activity | side effects | *today:* plain unit test with adapter fakes; *target (Phase 4):* `ActivityEnvironment` | — |
| Adapter (one per vendor) | translation to the vendor API | WebMock `stub_request` contract tests with realistic payloads | leak vendor constants upward |
| FE component/page | rendering + interaction given props | RTL role/label queries, `userEvent`, typed factories | `querySelector`, snapshots, style assertions |
| FE pure lib | logic | plain Vitest, no DOM | — |
| E2E (Playwright) | login, create project, run session/workflow — critical paths | the real stack | broad regression duty |

New controllers get `ActionDispatch::IntegrationTest` request tests; do not add new
`ActionController::TestCase` subclasses (legacy API tests are grandfathered).

## 3. Mocking rules (R1–R8)

- **R1. Never stub or mock the class under test.** No exceptions. If you feel the need, extract
  the collaborator you wanted to control and inject it.
- **R2. Don't mock what you don't own.** Tests must not stub/expect on `Octokit`, `Kubeclient`,
  `Docker::*`, `Temporalio`, or the gitlab gem's `Gitlab`/`Gitlab::Client` — stub the app-owned
  adapter (`Github::RepositoryService`, `ContainerRuntime`, `TemporalService`, …) or use its
  fake. *Enforced by `Testing/NoVendorStubbing` (rubocop).*
- **R3. One canonical fake per boundary**, owned in `test/support/` — a real class implementing
  the adapter interface, never `any_instance` + `define_method` patchwork.
- **R4. Contract-test every fake and canned seam.** HTTP adapters get WebMock `stub_request`
  contract tests with realistic payloads; a canned return shape (e.g. `TemporalHelper`'s
  `{ok:, workflow_id:, run_id:}`) gets a pin-test against the real method's shape. A fake
  without a contract test is a mock with better furniture.
- **R5. Internal collaborators are real by default** (sociable tests on the real DB). An
  `.expects` on an internal service is allowed only to assert an orchestration seam — one level
  deep, one expectation — and only when the outcome is not observable as state. Prefer asserting
  outcomes: DB rows, enqueued jobs, responses.
- **R6. `any_instance` is banned in new code.** *Enforced by `Testing/NoAnyInstance` (rubocop);
  the Exclude list in `.rubocop.yml` is frozen and only ever shrinks.*
- **R7. Time is controlled, not stubbed away.** Use `travel_to`/`freeze_time` for clock logic
  and injectable/config timeouts for waiting loops. Never `stubs(:sleep)`.
- **R8. Frontend: mock only the module seams** already in `app/frontend/test/setup.ts`
  (`@inertiajs/react`, `@rails/actioncable`, `@uppy/core` + `@uppy/aws-s3`, and an inert
  global `fetch`). Props come from typed factories (`app/frontend/test/factories/`).
  Query by role/label/text per RTL priority; no `querySelector`, no snapshots, no
  `vi.mock` of app components. *Lint-enforced part: node-access/container rules
  (`eslint-plugin-testing-library`) and the `toMatchSnapshot` ban; the query priority,
  factory usage, and no-`vi.mock`-of-app-components rules are reviewer-enforced.*

## 4. Blessed seams and fakes

| Boundary | Seam to stub in callers | Backing |
|---|---|---|
| Temporal | `TemporalService` / `TemporalWorkflowRegistry` via `TemporalHelper` (`mock_temporal_start`) | contract pin-test (Phase 2, pending) |
| Container runtimes | `stub_container_runtime` (`test/support/stub_support.rb`) | legacy fake; becomes `ContainerRuntime::FakeRuntime` in Phase 3 |
| Slack | `Slack::Client` (app-owned, `app/services/slack/client.rb`) | in-memory fake + WebMock contract tests (Phase 2, pending) |
| GitHub / GitLab | `Github::*Service` / `Gitlab::*Service` | WebMock contract tests (Phase 2, pending) |
| HTTP in general | WebMock global fence (`disable_net_connect!`) | `stub_request` belongs in adapter contract tests only |
| FE backend | `@inertiajs/react` + `@rails/actioncable` mocks in `setup.ts` | keep the mock surface minimal; don't extend it per-test |

Adding a new external service? Wrap it in an app-owned adapter first, give it a fake here, and
contract-test the adapter. Don't scatter `stub_request`/vendor stubs through feature tests.

## 5. Test data

- **Backend:** FactoryBot, minimal-by-default factories + traits (see `test/factories/`). A
  factory must not create associated records the common case doesn't need. Fixtures are not
  used in this repo.
- **Frontend:** typed builders over the Typelizer-generated types
  (`app/frontend/test/factories/`) — the return-type annotation is the drift contract:
  `export const buildProject = (o: Partial<Project> = {}): Project => ({ ...defaults, ...o })`.
  Prefer extending these over per-file `Record<string, unknown>` literal builders (40 legacy
  files predate this rule; migrate opportunistically when touching them).

## 6. Assertion style

- Assert observable behavior — "given x and y, the result is z" — never internal call graphs.
  An `.expects` chain longer than one method is a design smell to refactor, not to test harder.
- Prefer the specific assertion (`assert_equal`, `assert_match`, `assert_difference`)
  over a bare `assert`; `assert record.valid?, record.errors.full_messages.to_sentence`
  is the blessed idiom for validity. (`assert_predicate` is *not* house style — the
  `Minitest/AssertPredicate` cop is deliberately parked; `assert { }` power-assert
  blocks already give rich failure output.)
- When the contract is an exact boolean (JSON config values, documented `false`
  defaults), assert it exactly — `assert_equal false, x` with an inline
  `rubocop:disable Minitest/RefuteFalse` — because `refute x` also passes on `nil`.
- `assert_raises` takes exception classes only — to check the message, capture the result:
  `error = assert_raises(ArgumentError) { … }; assert_match(/…/, error.message)` (a regexp
  second argument is silently treated as the failure message, not a matcher).
- Multiple assertions per test are fine — fewer, longer behavioral tests beat atomized ones
  (`Minitest/MultipleAssertions` is deliberately disabled).
- FE: follow the Testing Library query priority — role > label > placeholder > text >
  `data-testid` as last resort. `await findBy*` instead of `waitFor` + `getBy*`.

## 7. Time

`travel_to`/`freeze_time` (ActiveSupport) for anything time-dependent. Waiting loops take their
timeouts from `Settings`/constructor arguments so tests can set them to ~0 — never stub `sleep`
and never swap constants at runtime.

## 8. PR checklist (what a test reviewer rejects)

- [ ] New behavior comes with a test at the *right* layer (§2), not an e2e for a unit concern
- [ ] No stubbing of the SUT (R1), no `any_instance` (R6), no vendor stubbing (R2)
- [ ] Assertions state outcomes, not call sequences (R5, §6)
- [ ] New external service ⇒ adapter + fake + contract test (R3/R4), not inline `stub_request`
- [ ] FE tests query by role/label and use the typed factories (R8, §5)
- [ ] `docker compose exec -T web make check_all` is green — including the coverage floors
- [ ] Shrunk a frozen allowlist while you were in the area? Even better.

## Roadmap after Phase 0

Phase 1 — backfill Pundit policy tests (56/61 untested; the riskiest gap). Phase 2 — adapters +
fakes + contract tests for Slack/GitHub/GitLab; Temporal pin-test. Phase 3 — re-house the
container fake as `ContainerRuntime::FakeRuntime`. Phase 4 — Temporal tests onto the SDK
harness. Phase 5 — FE typed-factory adoption + first Playwright critical-path specs. Details in
the research report.
