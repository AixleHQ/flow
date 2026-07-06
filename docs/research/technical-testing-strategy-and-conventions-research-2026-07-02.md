---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - ai/research/technical-backendless-frontend-testing-research-2026-06-25.md
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Testing strategy and conventions for the Rails + Inertia/React app (backend minitest + frontend Vitest)'
research_goals: 'Audit current backend and frontend test approaches (especially ad-hoc mocking in backend tests), research industry best practices, and propose a coherent testing doctrine: what to test at which layer, mocking rules, and conventions'
user_name: 'Artem_Petrov'
date: '2026-07-02'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-02
**Author:** Artem_Petrov
**Research Type:** technical

---

## Research Overview

This research audits the app's backend (minitest, 236 test files) and frontend (Vitest, 87 test
files) suites against current industry doctrine, and proposes a single written testing doctrine
for the repository. The trigger was the owner's observation that backend tests "mock everything
randomly, with no rule for what and how to test." The audit largely confirms that instinct but
sharpens it: the suite's *median* test is decent (sociable service tests on a real DB, behavior
assertions, clean Inertia integration tests), while a heavy tail of container/Temporal/LLM-adjacent
tests has drifted into deep mock towers — third-party classes stubbed directly, internal services
mocked as a habit, six files stubbing the class under test, and zero written rules preventing any
of it. The frontend has the opposite profile: a strong written doctrine (2026-06-25 research doc)
that the infrastructure follows, but two of its load-bearing rules (typed factories, lint-enforced
query bans) were never operationalized.

The output is: (1) an evidence-based audit of both suites with file:line examples; (2) a
boundary-by-boundary map of how external systems (Docker/K8s, Temporal, GitLab/GitHub, Slack,
agent CLIs) are faked today versus the verified best-practice pattern (app-owned adapter + one
canonical fake + contract tests); (3) a compact eight-rule mocking doctrine and a per-layer
"what to test where" table; (4) an enforcement and migration plan whose first deliverable is a
`docs/testing.md` conventions file — critical here because most code in this repo is written by
AI agents, and unwritten conventions do not survive agent turnover. The full executive summary is
in the Research Synthesis section at the end of this document.

---

## Technical Research Scope Confirmation

**Research Topic:** Testing strategy and conventions for the Rails + Inertia/React app (backend minitest + frontend Vitest)
**Research Goals:** Audit current backend and frontend test approaches (especially ad-hoc mocking in backend tests), research industry best practices, and propose a coherent testing doctrine: what to test at which layer, mocking rules, and conventions

**Technical Research Scope:**

- Current-state audit (codebase) — what is actually tested at each backend and frontend layer, mocking patterns, factories, brittle/meaningless tests
- Best practices (web, verified sources) — Rails/minitest doctrine, mocking discipline, test-suite shape, RTL guiding principles, Inertia testing
- Boundary/integration patterns — Temporal, LLM/agent containers, GitLab/Slack APIs, ActionCable
- Final proposal — target doctrine "what to test at which layer," mocking rules, gap analysis, migration plan, conventions-doc draft

**Research Methodology:**

- Codebase evidence gathered by direct inspection (grep taxonomies + representative file reads), quantified where possible
- Web claims verified against live primary sources (Rails guides, testing-library docs, Fowler, thoughtbot, Temporal docs, inertia-rails docs, Mocha README); URLs cited inline
- Confidence levels marked where sources are thin or claims are extrapolated
- Note: this research was planned as an 8-agent parallel workflow; the org's monthly spend limit killed all subagents, so the audit was executed inline with a narrower but targeted sample. Sampling bias is possible in per-file characterizations; the grep-derived counts are exact.

**Scope Confirmed:** 2026-07-02 (auto-confirmed: the user's request explicitly covered the full scope; user was AFK at the checkpoint)

---

## Technology Stack Analysis — Current Testing Stack and Practices Audit

### Backend testing stack (as installed)

| Concern | Tool | Notes |
|---|---|---|
| Runner | minitest + minitest-rails, minitest-hooks | standard |
| Assertions | minitest-power_assert | loaded in `test/test_helper.rb` |
| Mocking | **mocha** (`mocha/minitest`) | global monkey-patch style; **not thread-safe** per its README (process-parallel is fine) |
| HTTP edge | webmock (`WebMock.disable_net_connect!`) | good: net is fenced globally |
| Test data | factory_bot_rails | fixtures dir effectively unused (only `fixtures/files`) |
| Coverage | simplecov (`rails` profile, line) | **no `minimum_coverage` floor** |
| Inertia | `inertia_rails/minitest` + local `assert_inertia_page` (`test/test_helper.rb:68`) | |
| Browser | capybara `>= 3` in Gemfile | **zero system tests exist** — dead dependency |
| E2E | Playwright (`test/playwright/`) | **helpers only (auth/navigation), zero `.spec.ts`** |
| Absent | VCR, rubocop-minitest, factory lint, parallelize | `parallelize(...)` is commented out in `test_helper.rb` → 236 files run serially |

### Layer map: tests vs. source (gap analysis)

| Layer | Test files | Source files | Reading |
|---|---|---|---|
| models | 40 | 47 | good coverage |
| services | 99 | 168 | main body of the suite; ~40% of services untested |
| controllers | 38 | 111 | **~⅓ covered**; 25 of 38 still use legacy `ActionController::TestCase` (functional style, patched in `test_helper.rb` to force `format: :json`) — Rails guides use `ActionDispatch::IntegrationTest` for new work (_Source: https://guides.rubyonrails.org/testing.html_) |
| integration | 36 | — | clean, behavior-first (see below) |
| policies | **5** | **61** | **the single biggest gap** — Pundit authorization is effectively untested |
| jobs | 4 | 8 | thin |
| temporal | 10 | — | workflow/activity tests exist but mock-heavy |
| state_machines | 2 | — | |
| channels | 1 | — | |
| mailers / helpers / system | 0 | — | |
| Playwright e2e | 0 specs | — | helpers checked in, never used |
| Frontend (Vitest) | 87 | — | see frontend section |

Zero uses of `travel_to`/`freeze_time` anywhere in the suite — time-dependent code is handled by
stubbing (e.g. `SessionContextService.stubs(:sleep)`), the wrong tool for it.

### Backend mocking audit (the "random mocking" diagnosis)

70 of 236 files (~30%) use Mocha `stubs`/`expects`; `any_instance` appears 23 times. The
distribution is extremely skewed — the top-5 files account for ~330 of the stub call sites:

| File | stub/expect sites |
|---|---|
| `test/services/session_context_service_test.rb` | 103 |
| `test/services/container_strategies/agent_session_strategy_test.rb` | 91 |
| `test/services/temporal_service_test.rb` | 55 |
| `test/services/container_strategies/base_strategy_test.rb` | 42 |
| `test/services/container_runtime/kubernetes_runtime_test.rb` | 37 |

**Taxonomy of stub targets** (exact counts from grep over `Class.(stubs|expects)(`):

1. **Third-party classes stubbed directly** — `Slack::Client.expects` ×28, `Octokit::Client.expects` ×7,
   `Docker::Container.stubs` ×5, `Temporalio::Testing::WorkflowEnvironment.stubs` ×11, `Resolv.stubs` ×9,
   Kubeclient mocks throughout `StubSupport`. This violates "don't mock what you don't own": the mock
   encodes your *guess* about the vendor API, so tests stay green when the real API breaks you
   (_Sources: https://hynek.me/articles/what-to-mock-in-5-mins/, https://testing.googleblog.com/2020/07/testing-on-toilet-dont-mock-types-you.html, https://thoughtbot.com/blog/testing-third-party-interactions_).
   Stubbing `Temporalio::Testing::WorkflowEnvironment` is the most ironic case — mocking the SDK's own testing tool instead of using it.
2. **Internal services mocked as collaborators** — `WorkflowService.expects` ×39, `TemporalService.expects` ×20 + `.stubs` ×9,
   `TaskService.expects` ×15, `SessionService.stubs` ×7, `SessionContextService` ×6, `AgentCredentialsService.stubs` ×5,
   `UsageStatisticsService.stubs` ×5. Some of these are legitimate seam assertions ("creating a task on an
   auto-bound column starts the workflow" — `test/jobs/…`, `test/services/task_service_test.rb`), but the
   volume shows mocking is the *default* reflex, not a deliberate seam choice.
3. **Config/environment stubbing** — `Settings.stubs` ×16 (centralized in `StubSupport#stub_container_settings`),
   const-swapping via `set_const` for timeouts (`test/support/stub_support.rb:209-224`). Works, but mutates
   global constants with manual restore — a leak hazard.
4. **Stubbing the SUT itself** (worst category) — 6 files stub or expect on the very class under test:
   - `test/services/temporal_service_test.rb:365-369` — `TemporalService.expects(:delete_schedules)` … `TemporalService.expects(:create_schedule)` *inside TemporalService's own test*: the test asserts the SUT calls itself, i.e. it tests the implementation's call graph, not behavior.
   - `test/services/session_context_service_test.rb:778,820` — `SessionContextService.stubs(:sleep)`: patching out the SUT's waiting instead of injecting time/timeouts.
   - also `url_safety_validator_test.rb`, `webhooks/slack_controller_test.rb`, `bmad_method_injector_test.rb`, `container_runtime_test.rb`.
   Per Fowler's Practical Test Pyramid: "Test for observable behaviour instead… if I enter values x and y, will the result be z" (_Source: https://martinfowler.com/articles/practical-test-pyramid.html_).

**What is actually good (keep and bless):**

- The *median* service test is sociable and behavioral: `test/services/task_service_test.rb` creates real records via factories, exercises the service, asserts persisted state and `BoardActivity` side effects.
- Integration tests are clean: `test/integration/web/sessions_controller_test.rb` signs in through the real login POST (`AuthHelper#sign_in_as`) and asserts redirects + `assert_inertia_page "Auth/LoginPage"`.
- Factories are minimal-by-default with traits (`test/factories/companies.rb`, `workflows.rb`) — no deep default graphs. This matches fixture/factory best practice ("default data for the common case", _Source: https://guides.rubyonrails.org/testing.html_).
- `test/support/stub_support.rb` is a genuine **fake** of the container runtime — a virtual filesystem plus command routing (`route_exec_docker/k8s`, tar building, per-agent auth fixtures). The *instinct* is exactly right (fake at the boundary); the *mechanics* are wrong: it's built from `any_instance.stubs`, `define_method` monkey-patching with manual `cleanup_runtime_overrides` teardown, and const swapping — global mutable state that leaks if a teardown is missed.
- `TemporalHelper` (`test/helpers/temporal_helper.rb`) gives everyone one seam for "Temporal started OK" — right idea, but the canned `{ok:, workflow_id:, run_id:}` hash is hand-maintained with **no contract test** pinning it to what `TemporalService.start_workflow` really returns, so it can silently drift.

**Root cause assessment:** there is no written rule for (a) which seams are blessed, (b) when
`.expects` is acceptable, (c) who owns third-party fakes. Each test file re-derives its own answer;
mock towers accrete in exactly the areas where the real dependency is painful (containers, Temporal,
vendor APIs) because no sanctioned fake exists to reach for. Confidence: High (grep counts are exact;
per-file readings sampled).

### Frontend testing stack and conformance audit

Stack (decided by the 2026-06-25 research, shipped): Vitest 4 + jsdom, `@testing-library/react` 16 +
`user-event` 14 + `jest-dom`, central `app/frontend/test/{setup.ts,inertiaMock.ts,renderPage.tsx}`,
`vitest.config.ts` with `css:false`, honest `coverage.all:true`, slow-runner timeout handling for
Docker/CI. 87 test files. Sampled tests (`pages/Projects/IndexPage.test.tsx`,
`Company/Sessions/Show.test.tsx`, `shared/components/RunWorkflowModal.test.tsx`) follow RTL doctrine:
role/label queries, `userEvent`, behavior assertions (empty states, filtering, submit side effects via
router/form spies) — consistent with the decided "functional-not-visual" target.

**Doctrine drift found (both are rules the 2026-06-25 doc marked load-bearing):**

1. **Typed factories are ~unused.** Only 3 factories exist (`boardTask.ts`, `project.ts`, `sharedProps.ts`)
   and only **2 of 87** test files import them, while **40 files** hand-roll local untyped literal
   builders (`(overrides: Record<string, unknown>) => ({...})` — e.g. `pages/Projects/IndexPage.test.tsx:9-24`).
   The drift-as-compile-error contract (fixture return-type = generated Typelizer type) is therefore
   inactive: a serializer change breaks nothing at compile time. This was Recommendation #1/Phase 0 of
   the FE research and it silently didn't stick.
2. **The lint bans were never added.** `eslint.config.js` has no `no-restricted-syntax` for
   `toMatchSnapshot`/`querySelector` and no `eslint-plugin-testing-library` (verified: absent from
   `package.json`). Result: **64 `querySelector` call sites** across ~10 test files
   (`shared/resources/tools/ToolsContent.test.tsx:116` queries `svg.${iconClass}` — a hashed-class
   assertion of exactly the kind the doctrine bans). RTL's own priority puts role/label first and
   testid "only… where you can't match by role or text"; `container.querySelector` is called out as a
   high-importance mistake (_Sources: https://testing-library.com/docs/queries/about/#priority,
   https://kentcdodds.com/blog/common-mistakes-with-react-testing-library_).

Verdict: the FE suite is in good shape *because* it has a doctrine; its two failures are precisely the
rules that relied on humans remembering instead of a linter enforcing. Confidence: High.

### Test infrastructure and quality gates audit

- `make check_all` (in Docker) runs BE (rails test ‖ rubocop ‖ brakeman) then FE (eslint ‖ tsc, then
  Vitest alone — deliberately serialized after a documented CPU-starvation flake; `Makefile:27-50`).
- **No coverage floor anywhere**: SimpleCov has no `minimum_coverage`; Vitest coverage has no
  `thresholds`. Coverage is printed, never enforced.
- **No test-focused static analysis**: no rubocop-minitest, no factory_bot cops, no
  eslint-plugin-testing-library.
- **No backend parallelization**: `parallelize` commented out in `test_helper.rb`. Rails parallelizes
  by forked processes by default, which is safe with Mocha (its thread-safety warning applies to
  threads, _Source: https://github.com/freerange/mocha_). With 236 files serial, this is free speed
  being left on the table. Confidence: High for facts, Medium for how much speedup (depends on DB
  setup cost per worker).
- Dead weight: capybara installed with zero system tests; Playwright helpers with zero specs.

---

## Integration Patterns Analysis — Boundary Testing Patterns

The app's external boundaries, how each is handled today, and the verified target pattern.
The umbrella principle for all rows: **wrap the vendor in an app-owned adapter, give the adapter one
canonical fake, and contract-test the adapter itself** — thoughtbot's four options for third-party
APIs (stub adapter methods / swap backend / stub HTTP / fake local service) all presuppose the
adapter exists (_Sources: https://thoughtbot.com/blog/testing-third-party-interactions,
https://www.germanvelasco.com/blog/faking-external-services-in-tests-with-adapters,
https://martinfowler.com/articles/practical-test-pyramid.html — contract tests_).

| Boundary | Today | Target |
|---|---|---|
| **Container runtimes (Docker/K8s)** | `StubSupport` fake via `any_instance` + `define_method` patching + manual teardown | Keep the virtual-FS fake, re-house it as a real class: `ContainerRuntime::FakeRuntime` implementing the same runtime interface, selected by test config. No monkey-patching, no teardown bookkeeping; `stub_container_runtime` becomes one line. The interface seam (`ContainerRuntime` resolving a runtime by name) already exists. |
| **Temporal** | Callers stub `TemporalService`/`TemporalWorkflowRegistry` class methods (TemporalHelper); workflow tests stub `Temporalio::Testing::WorkflowEnvironment` itself | Callers: keep the `TemporalService` seam (it IS the app-owned adapter) + add a **contract test** pinning the canned return shape to the real method. Workflows: use the SDK's time-skipping `WorkflowEnvironment.start_time_skipping` with **mocked activities**; activities: plain unit tests via `ActivityEnvironment`; `WorkflowReplayer` for determinism when workflows change (_Source: https://docs.temporal.io/develop/ruby/testing-suite_). Stop stubbing the SDK's test tooling. |
| **GitLab / GitHub** | `Gitlab::TokenService.expects` ×8, `Github::TokenService.expects` ×8 (adapter-ish, OK), but also raw `Octokit::Client.expects` ×7 and a globally configured gitlab gem endpoint in `test_helper.rb` | Everything above the token/repository services stubs those services; the services themselves get WebMock `stub_request` contract tests against realistic recorded payloads. No test outside the adapter's own test may reference `Octokit`/`Gitlab` constants. |
| **Slack** | `Slack::Client.expects` ×28 spread across tests | Same recipe: `SlackClient`-owning adapter + fake capturing posted messages in memory (thoughtbot's FakeSMS pattern), WebMock contract tests underneath. |
| **LLM / agent CLIs** | Faked via container virtual FS + canned terminal-output fixtures per agent type (`StubSupport::AUTH_CONFIGS`, `terminal_output_fixture`) — actually a sound record-replay-style fake | Keep; formalize fixtures as named scenario files. Unit/functional tests assert *pipeline behavior* on deterministic canned outputs; quality-of-output belongs to evals, not the test suite (industry consensus on testing LLM apps; Confidence: Medium — field still young). |
| **HTTP in general** | WebMock global fence ✅; `stub_request` in only 7 files | Keep the fence. `stub_request` is the tool *inside adapter contract tests only*. VCR deliberately not adopted: cassette rot + secret handling outweigh benefits at this scale (Confidence: Medium — community sentiment, not hard data). |
| **ActionCable** | 1 channel test | Fine at this size; `ActionCable::Channel::TestCase` + broadcast assertions where realtime logic grows. FE side already mocks `@rails/actioncable` in setup. |
| **Inertia (BE↔FE)** | Server: `assert_inertia_page` component asserts; props rarely asserted. FE: props injected via mocked `usePage` | This is the app's most important internal contract; see doctrine below. inertia_rails ships `assert_inertia_props`/`assert_inertia_component` for exactly this (_Source: https://inertia-rails.dev/guide/testing_), and the docs recommend the same three-layer split this doctrine adopts (endpoint tests + client-side unit tests + thin e2e). |

---

## Architectural Patterns and Design — The Testing Doctrine (Proposal)

### Suite shape

For a Rails+Inertia monolith the classic pyramid applies with one Inertia-specific twist: the
"integration" middle belongs to **request tests asserting the Inertia contract** (component name +
props), and the FE component suite is the *other half of the same contract*, fed by typed factories
derived from the serializers. Lots of unit/sociable tests → some request tests → very few e2e
(_Sources: https://martinfowler.com/articles/practical-test-pyramid.html,
https://inertia-rails.dev/guide/testing_). Rails guides: system tests only for critical paths
(_Source: https://guides.rubyonrails.org/testing.html_) — for this app that layer is Playwright, and
its budget is ~5–10 specs total.

### What to test at which layer

| Layer | Owns | Asserts | Must NOT |
|---|---|---|---|
| Model | validations, scopes, state machines, domain methods | real DB, behavior | stub anything except time |
| Service | use-case behavior | real DB + real internal collaborators; outcomes (persisted state, enqueued jobs, outbox rows, activities) + at most one seam expectation for orchestration | mock internal collaborators by default; stub the SUT |
| Request (integration) | auth, authorization wiring, status, redirects, **Inertia component + key props** | `sign_in_as` through real login; `assert_inertia_page` + `assert_inertia_props` | re-test service logic in depth |
| Policy | every Pundit policy | permit/forbid matrix per role | — (pure unit, no mocks needed) |
| Job | enqueue + perform | ActiveJob helpers + fakes at boundaries | — |
| Temporal workflow | orchestration logic | time-skipping env + mocked activities | stubbing the SDK test env |
| Temporal activity | side effects | plain unit test (`ActivityEnvironment`), adapter fakes | — |
| Adapter (one per vendor) | translation to vendor API | WebMock `stub_request` contract tests with realistic payloads | leak vendor constants upward |
| FE component/page | rendering + interaction given props | RTL role/label queries, `userEvent`, typed factories | querySelector, snapshots, style asserts |
| FE pure lib | logic | plain vitest | DOM |
| E2E (Playwright) | 5–10 critical paths (login, create project, run session/workflow) | real stack | broad regression duty |

### Mocking rules (R1–R8) — the core of the doctrine

- **R1. Never stub or mock the class under test.** No exceptions; if you need to, extract the
  collaborator you wanted to control. (Kills the 6-file pattern; e.g. `TemporalService.expects(...)`
  inside `temporal_service_test.rb`.)
- **R2. Don't mock what you don't own.** Tests outside an adapter's own test file must not mention
  `Octokit`, `Gitlab`, `Slack::Client`, `Docker::*`, `Kubeclient`, `Temporalio` — stub/fake the
  app-owned adapter instead (_Sources: hynek.me, Google Testing Blog, thoughtbot — above_).
- **R3. One canonical fake per boundary, owned in `test/support/fakes/`.** Real classes implementing
  the adapter interface (like the container virtual-FS fake, re-housed) — never `any_instance` +
  `define_method` patchwork.
- **R4. Contract-test every adapter and every canned seam.** WebMock `stub_request` with realistic
  payloads for HTTP adapters; a pin-test asserting `TemporalHelper`'s canned hash matches
  `TemporalService.start_workflow`'s real return shape.
- **R5. Internal collaborators are real by default (sociable tests).** `.expects` on an internal
  service is allowed only to assert an orchestration *seam* (one level deep, one expectation), and
  only when the outcome isn't observable as state. Prefer asserting outcomes.
- **R6. `any_instance` is banned in new code.** Current 23 uses become a frozen allowlist that only
  shrinks.
- **R7. Time is controlled, not stubbed away.** `travel_to`/`freeze_time` for clock logic;
  injectable/config timeouts for waiting loops (replaces `stubs(:sleep)` and `set_const` swapping).
- **R8. Frontend: mock only the module seams** (`@inertiajs/react`, `@rails/actioncable`) already in
  `setup.ts`; props come from typed factories; queries follow RTL priority (role > label > text >
  testid); no `querySelector`, no `toMatchSnapshot`, no `vi.mock` of app components
  (_Sources: testing-library.com priority, Kent C. Dodds common-mistakes — above_).

### Assertion style

Assert observable behavior ("given x and y, result is z"), not call graphs — Fowler, above. In
practice: DB state, response/redirect, Inertia props, enqueued jobs, rendered roles/text; an
`.expects` chain longer than one method is a design smell to refactor, not to test harder.

---

## Implementation Approaches and Technology Adoption

### Enforcement (make the doctrine self-executing — nothing here relies on memory)

1. **`docs/testing.md`** — the conventions doc (draft outline below) + a pointer from `CLAUDE.md`.
   In this repo most code is written by AI agents; a rule that isn't in the repo text does not exist.
2. **Backend static gates:** add `rubocop-minitest` + `rubocop-factory_bot`; add a small custom cop
   (or CI grep) banning `any_instance` and vendor constants (`Octokit|Slack::Client|Kubeclient|Docker::`)
   under `test/**` outside `test/support/fakes/` and adapter contract tests.
3. **Frontend static gates:** `eslint-plugin-testing-library` (flags `container` querying, wrong
   queries, missing `await`) + `no-restricted-syntax` bans for `toMatchSnapshot`/`querySelector` in
   `*.test.tsx` — the exact enforcement the 2026-06-25 doc called for.
4. **Coverage ratchet:** set SimpleCov `minimum_coverage` and Vitest `coverage.thresholds` at the
   *current* levels (no aspirational jumps), raise quarterly. Enforced floor beats reported number.
5. **Parallelize the backend suite:** enable `parallelize(workers: :number_of_processors)` —
   process-based, Mocha-safe; expect DB-per-worker setup cost once per run.
6. **Trim dead weight:** drop capybara (or write the first system test deliberately); either write
   the first Playwright spec or delete the helpers until the e2e phase starts.

### `docs/testing.md` draft outline

```
# Testing Conventions
1. Suite shape & budgets (pyramid; e2e ≤ 10 specs)
2. What to test at which layer (the table from this research)
3. Mocking rules R1–R8 (verbatim)
4. Blessed seams & fakes registry: TemporalService, ContainerRuntime::FakeRuntime,
   fakes in test/support/fakes/, FE mocks in app/frontend/test/setup.ts
5. Test data: BE factories minimal-by-default + traits; FE typed factories over
   @/types/generated (return-type annotation is the contract)
6. Assertion style: outcomes not call graphs; power-assert; RTL query priority
7. Time: travel_to / injectable timeouts; never stub sleep
8. Checklist for new PRs (what a test reviewer rejects)
```

### Migration roadmap (each phase independently shippable)

- **Phase 0 (≈1 day): write the doctrine + turn on the gates.** `docs/testing.md`, eslint additions,
  rubocop-minitest, coverage floors at current levels, `parallelize`. No test rewrites.
- **Phase 1 (highest-risk gap first): policy test backfill.** 61 policies / 5 tested; authorization
  bugs are silent security bugs. Table-driven permit/forbid tests per role; pure unit tests, fast to
  mass-produce.
- **Phase 2: adapters + fakes for Slack and GitHub/GitLab.** Extract/complete app-owned adapters,
  build in-memory fakes, write WebMock contract tests, migrate the 28 `Slack::Client.expects` and 7
  `Octokit` sites. Add the TemporalHelper contract pin-test.
- **Phase 3: re-house the container fake.** `StubSupport`'s virtual FS → `ContainerRuntime::FakeRuntime`
  proper class; delete `define_method`/teardown machinery; the 5 worst mock-tower files shrink
  dramatically as a side effect.
- **Phase 4: Temporal tests onto the SDK harness.** Time-skipping env + mocked activities for the 10
  temporal tests; `ActivityEnvironment` for activities; stop stubbing `Temporalio::Testing`.
- **Phase 5: FE factory adoption + first e2e.** Generate typed factories for the ~10 most-tested
  resources (pairs with the Rails-side `typelize` cleanup of `unknown` fields from the FE research);
  boy-scout rule migrates the 40 literal-builder files; 5 Playwright critical-path specs on the
  existing helpers.
- **Standing rule:** legacy tests are migrated opportunistically (boy-scout), not big-bang; the
  linters stop new debt at the door.

### Risks

- Doctrine too strict → friction: R5 deliberately permits one-level seam expectations; the goal is a
  default, not a prohibition.
- Fake drift: mitigated by R4 contract tests — a fake without a contract test is the same trap as a
  mock, just better organized.
- Parallelization may surface order-dependent tests (global consts, `set_const` leaks) — fix is the
  same direction as Phase 3 (remove global mutation), and failures will name the leaky files.

---

## Research Synthesis

### Executive Summary

The backend suite's problem is not "bad tests everywhere" — the median service/integration test is
sociable, behavioral, and clean. The problem is **the absence of a doctrine**, which let three
specific rots grow unchecked: (1) third-party classes (Slack, Octokit, Docker, Kubeclient, even
Temporal's own *test tooling*) are mocked directly instead of through app-owned adapters with
canonical fakes; (2) internal services are mocked by reflex (39 `WorkflowService.expects` alone), so
many tests assert call graphs instead of outcomes; (3) six files stub the class under test — tests
that can only ever agree with the implementation. Meanwhile the highest-risk gap isn't mocking at
all: **56 of 61 Pundit policies have no tests**, controllers sit at ~⅓ coverage on a legacy test
base class, and the e2e layer is two years of good intentions (capybara installed, Playwright
helpers checked in, zero specs between them). Infrastructure enforces nothing: no coverage floors,
no test linting, no parallelization.

The frontend proves the thesis in reverse: it has a written doctrine (2026-06-25), and the suite is
correspondingly healthy — except exactly where the doctrine relied on memory instead of tooling
(typed factories: 2/87 files; querySelector: 64 sites; the planned lint bans: never added).

The proposal is therefore doctrine-first: an eight-rule mocking discipline (never stub the SUT;
don't mock what you don't own; one canonical fake per boundary; contract-test every fake; sociable
tests by default; ban `any_instance`; control time, don't stub it; FE mocks only at module seams), a
per-layer "what to test where" table, and — critically — **self-executing enforcement** (rubocop-minitest,
eslint-plugin-testing-library + syntax bans, coverage ratchet, vendor-constant grep) captured in
`docs/testing.md` and pointed to from `CLAUDE.md`, because in an agent-written codebase unwritten
conventions decay within weeks. Migration is five independently shippable phases ordered by risk:
gates → policy backfill → vendor adapters/fakes → container-fake re-housing → Temporal SDK harness
+ FE factories + first e2e.

### Key Technical Findings

- Mocking is concentrated, not uniform: top-5 files hold ~330 of the stub sites; the tail is fine.
- The suite already contains the *right* patterns in embryo: `StubSupport` is a real boundary fake
  with wrong mechanics; `TemporalHelper` is a blessed seam missing only a contract test.
- Policies 5/61, controllers 38/111 (25 on `ActionController::TestCase`), e2e 0 — the coverage gaps
  outrank the mocking cleanup in risk.
- FE doctrine held where infrastructure enforced it and failed where it didn't — enforcement, not
  documentation alone, is the operative variable.
- All quality gates are advisory today (coverage printed not enforced; no test cops; serial suite).

### Top Recommendations

1. Ship Phase 0 this week: `docs/testing.md` + lint gates + coverage floors + `parallelize` — one
   day of work that stops new debt.
2. Backfill policy tests (Phase 1) before any mock refactoring — it's the only gap with security
   consequences.
3. Adopt the adapter+fake+contract pattern for Slack/GitHub/GitLab (Phase 2); re-house the container
   fake (Phase 3); move Temporal tests onto the SDK harness (Phase 4).
4. Activate the FE typed-factory contract and lint bans (Phase 5 + Phase 0) — the 2026-06-25
   research already designed this; it just needs enforcement.
5. Keep e2e tiny and deliberate: 5–10 Playwright critical-path specs, no more.

### Source Documentation

Primary sources fetched and verified 2026-07-02: Rails Testing Guide
(guides.rubyonrails.org/testing.html) · Fowler, The Practical Test Pyramid
(martinfowler.com/articles/practical-test-pyramid.html) · Testing Library query priority
(testing-library.com/docs/queries/about/#priority) · Kent C. Dodds, Common Mistakes with RTL
(kentcdodds.com/blog/common-mistakes-with-react-testing-library) · thoughtbot, Testing Third-Party
Interactions (thoughtbot.com/blog/testing-third-party-interactions) · Velasco, Faking External
Services with Adapters (germanvelasco.com/blog/faking-external-services-in-tests-with-adapters) ·
Hynek, Don't Mock What You Don't Own (hynek.me/articles/what-to-mock-in-5-mins) · Google Testing
Blog, Don't Mock Types You Don't Own (testing.googleblog.com/2020/07) · Temporal Ruby test suites
(docs.temporal.io/develop/ruby/testing-suite) · Inertia Rails testing (inertia-rails.dev/guide/testing)
· Mocha README (github.com/freerange/mocha). Codebase evidence: exact grep counts + file reads cited
inline as `path:line`. Limitations: per-file quality characterizations are sampled (~15 files read of
236+87); subagent-based exhaustive audit was blocked by the org spend limit; VCR-sentiment and
LLM-testing claims are Medium confidence.

### Conclusion

Adopt the doctrine, wire the enforcement, and migrate opportunistically. The suite doesn't need a
rewrite — it needs rules, three sanctioned fakes, and gates that make the rules cheaper to follow
than to ignore.

**Technical Research Completion Date:** 2026-07-02
