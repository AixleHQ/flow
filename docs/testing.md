# Testing Conventions

The testing doctrine for this repository. Most code here is written by AI agents, so the rules
live in the repo and in linters — not in anyone's memory. Background and evidence:
`docs/research/technical-testing-strategy-and-conventions-research-2026-07-02.md`.

**The one-sentence doctrine: test observable behavior through real collaborators, fake only at
app-owned boundaries, and let linters — not reviewers — hold the line.**

## 1. Suite shape and budgets

```
        system e2e (Capybara   ≤ 10 specs, critical paths only
          + Cuprite/Chromium)
      ──────────────────
      FE component/page       behavior given props (Vitest + RTL, jsdom)
      request/integration     auth + policy + Inertia component/props
      ──────────────────
      model / service /       the bulk of the suite: real DB, real internal
      policy / job / unit     collaborators, fakes at boundaries
```

- The backend suite runs in parallel: `parallelize(workers: :number_of_processors)` in
  `test/test_helper.rb` forks one worker per core, each with its own database
  (`aixle_test-0`, `aixle_test-1`, …). Runs below Rails' threshold (50 cases) — a single
  file, the system suite — stay serial; `PARALLEL_WORKERS=1` forces a serial run. Run the
  whole gate before every push (`make check_all`, see CLAUDE.md).
- **One suite run at a time.** Sessions and git worktrees that share a Postgres share
  `aixle_test` and the per-worker databases; overlapping runs corrupt each other. `make`
  targets are flock-serialized; direct `bin/rails test` is not — check nothing else is running.
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
| Temporal workflow | orchestration logic | full-execution tests run the real workflow through the SDK time-skipping `WorkflowEnvironment` with fake activities, via the `run_workflow` helper (`test/support/temporal_workflow_helper.rb`) — the in-memory test server boots ~5s once then is instant, and time-skips retry backoff; it does NOT touch the shared Postgres. The helper's worker sets `workflow_failure_exception_types: [Exception]`, so an unexpected exception fails the workflow and surfaces as `WorkflowFailedError` — without it Temporal retries the workflow task forever (no RetryPolicy governs that), and the test hangs silently until CI kills the job. White-box tests of orchestration internals (signal races, decision logic) stay plain unit tests. Callers of `TemporalService` keep the `TemporalHelper` seam. Replay safety: every recorded history under `test/fixtures/files/temporal_histories/` must replay on the current code (`history_replay_test.rb`); record new ones as `docs/architecture/temporal-versioning.md` describes. | stub `Temporalio::Testing` itself (outside `temporal_service_test`, its own contract test) |
| Temporal activity | side effects | run the activity through `Temporalio::Testing::ActivityEnvironment` via the `run_activity` helper (serverless — no boot/hang risk); boundaries stay behind their fakes | — |
| Adapter (one per vendor) | translation to the vendor API | WebMock `stub_request` contract tests with realistic payloads | leak vendor constants upward |
| FE component/page | rendering + interaction given props | RTL role/label queries, `userEvent`, typed factories | `querySelector`, snapshots, style assertions |
| FE pure lib | logic | plain Vitest, no DOM | — |
| E2E (Capybara + Cuprite, SitePrism page objects in `test/system/pages/`) | login, create project, run session/workflow — critical paths | the real stack (headless Chromium against built Vite assets) | broad regression duty |

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
| Temporal | `TemporalService` / `TemporalWorkflowRegistry` via `TemporalHelper` (`mock_temporal_start`) | contract pin-test (`test/helpers/temporal_helper_contract_test.rb`) |
| Container runtimes | `stub_container_runtime` (`test/support/stub_support.rb`) injects `ContainerRuntime::FakeRuntime` via the `ContainerRuntime.build` seam | `test/support/fakes/fake_runtime.rb` (real `BaseRuntime`, in-memory FS) |
| Slack | `Slack::Client` (app-owned, `app/services/slack/client.rb`) | `FakeSlackClient` + `SlackTestHelper` (`stub_slack_client!`) + WebMock contract test |
| GitHub / GitLab | `Github::*Service` / `Gitlab::*Service` | `FakeGithub`/`FakeGitlab` + WebMock contract tests |
| Azure DevOps | `AzureDevops::{Repository,PullRequest,WorkItem,Build}Service` via `stub_azure_devops!` | `FakeAzureDevops` (`test/support/fakes/fake_azure_devops.rb`) + WebMock contract tests in `test/services/azure_devops/`. `CredentialProvider` and `Client` stay REAL — the authorization chain is usually what is under test |
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

## 9. Test tags: running a test only when it matters

A tag changes **when** a test runs in CI, and nothing else. Marking a test, a test class or a test
file with a tag is all it takes: nobody edits a list of tests in a workflow. A test without a tag
runs everywhere, as it always did.

**The rules live in one file, `config/test_tags.json`**, one entry per tag, read by the Rails suite
(`test/support/test_tags.rb`), the Vitest suite (`vitest.config.ts`, `Makefile`) and CI
(`bin/test-tags`). An entry has a `description` and one of two rules:

| Rule | A pull request runs the tag | A push runs it |
|---|---|---|
| `develop` | never | always |
| `paths` (with a `paths` list of globs) | when a changed file matches a glob | always |

A push means every event that is not a pull request (`develop`, `staging`, a manual run), so the
full suite still runs on every integrated commit. When CI cannot read the pull request's diff, it
runs everything.

### Tags that exist

| Tag | Rule | Tests |
|---|---|---|
| `schema_parity` | `paths`: `db/migrate/**/*`, `db/schema.rb`, `test/db/schema_parity_test.rb` | `SchemaParityTest`, which replays every migration (about 40 s) |

### Put a test under a tag

- **Rails (Minitest).** In the class: `tags :schema_parity` tags every test of the class and of its
  subclasses. `tag :schema_parity` on the line before a `test "..." do` tags that test only.
  A name that is not in `config/test_tags.json` raises when the file loads.
- **Vitest.** Per test: `test('...', { tags: ['name'] }, () => {})`. Per suite:
  `describe('...', { tags: ['name'] }, () => {})`. For the whole file, a `@module-tag name` line in
  a JSDoc comment at the top of the file. Vitest refuses a tag the config does not list;
  `vitest.config.ts` lists every tag of the JSON file.

### Add a tag

Add an entry to `config/test_tags.json` (a lower-case word, a description, a rule). Nothing else:
the Rails and Vitest sides, the CI step and `TestTags`' own test read the file. Choose `paths` for a
test that only a known set of files can break, and `develop` for one that nothing in a pull request
is likely to break and that costs more than it tells.

**Moving a test under a tag, or changing a test to make it faster, is a change to the test:** it
needs the owner's ok in review, like any other change that could narrow what a test checks.

### Run tagged tests

- Locally every test runs, tagged or not: `make check_all`, `bin/rails test` and `yarn test` ignore
  tags unless told otherwise. To run one tag's tests, run their file: `bin/rails test
  test/db/schema_parity_test.rb`. For Vitest, `yarn test --tags-filter=name`.
- To leave tags out the way a pull request does: `TEST_EXCLUDE_TAGS="schema_parity" bin/rails test`,
  or `make rails-test TEST_EXCLUDE_TAGS=schema_parity` (the Makefile turns the list into one
  `--tags-filter='!tag'` per tag for Vitest).
- To see what a pull request would leave out: `bin/test-tags exclude --event pull_request --base
  origin/develop`.

### Why our own for Rails

Minitest filters by test name only. The maintained tag gems do not fit: `minitest-tagz` was last
released in 2019 and requires minitest ~> 5. The Rails side is a declaration plus a filter in
`runnable_methods`, which is where Minitest picks a class's tests, about 40 lines. Vitest has tags
built in (4.1 and later) and uses them as they are. For choosing by changed files, a
`dorny/paths-filter` step would put each tag's paths in the workflow, once per tag, and not beside
the tag; `bin/test-tags` reads them from the same file as the tag.

## Roadmap after Phase 0

- **Phase 1 — done.** Authorization backfill at the **request layer**: a dedicated
  `test/integration/**/*_authorization_test.rb` per controller, driving the real endpoint as each
  role, via the `AuthorizationMatrix` harness (`test/support/authorization_matrix.rb`).
- **Phase 2 — done.** App-owned adapters get canonical in-memory fakes
  (`test/support/fakes/fake_{slack_client,github_service,gitlab_service}.rb`) + WebMock contract
  tests; Slack/GitHub/GitLab caller stubs migrated onto them; `TemporalHelper` pin-test added.
- **Phase 3 — done.** The container fake is re-housed as `ContainerRuntime::FakeRuntime`
  (`test/support/fakes/fake_runtime.rb`), injected via the `ContainerRuntime.build` seam;
  `StubSupport`'s vendor-stub/monkeypatch machinery is gone.
- **Phase 4 — done.** Activity tests run through `ActivityEnvironment` (`run_activity`).
  Full-execution workflow tests run through the time-skipping `WorkflowEnvironment` (`run_workflow`,
  in `check_all` — the test server proved stable, ~5s one-time boot); white-box orchestration-internal
  workflow tests stay unit. `TemporalService` callers keep the `TemporalHelper` seam + Phase 2 pin-test.
- **Phase 5 — done.** FE typed-factory adoption (`app/frontend/test/factories/`, migrated the
  hand-rolled literal builders) + the first system e2e specs: Capybara + Cuprite (headless
  Chromium, no chromedriver) with SitePrism page objects (`test/system/`), driving the real
  Rails+Inertia+React stack against built Vite test assets. Run in `check_all` via `rails
  test:system` (chromium is in the Docker image; `VITE_RUBY_MODE=test bin/vite build` runs first
  because the test env uses built assets, not a dev server).

Details in the research report.
