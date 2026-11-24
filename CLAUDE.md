# CLAUDE.md

Guidance for AI agents working in this repository.

## Documentation index

`docs/index.md` is the index of all architecture/design/research docs. Whenever you
add, remove, or move a document under `docs/`, update `docs/index.md` in the same change.

## Keeping docs in step with the code

People and agents act on what the docs say, so a change is finished only when every
place that states the changed fact says the same thing. Same change, same PR.

- **Code → docs.** When you rename, remove or change something a reader acts on — an
  env var or its default, a route or webhook URL, an agent tool, a UI label or where a
  screen lives, a setting, a limit, a state, a runtime — search for the old name before
  you finish and fix every hit:
  `grep -rn '<old name>' docs references app/frontend/pages/Docs/data/pages`.
  An empty result is the check passing, not a step to skip.
- **Mirror pairs.** The `/docs` portal serves `app/frontend/pages/Docs/data/pages/<name>.md`,
  not `docs/`. `docs/user-guide/`, `docs/reference/` and `docs/product/` hold hand-kept
  copies of those pages, mostly under the same file name; the exceptions are
  `reference/api.md` ↔ `api-guide.md`, `reference/cli.md` ↔ `cli-ref.md`,
  `reference/configuration.md` ↔ `config-schema.md`, `reference/index.md` ↔ `reference.md`,
  `user-guide/index.md` ↔ `user-guide.md` and `quickstart.md` ↔ `quick-start.md`. Edit both
  files of a pair together. They may differ only in link form (relative `.md` links in
  `docs/`, `/docs/<slug>` or plain text in the portal), never in content.
- **Design docs.** When a designed feature ships, its doc says so at the top
  (`Built <date> (#PR)`), and where the build departs from the proposal goes into the doc
  in the same PR. A dropped proposal says it was dropped. Research reports
  (`docs/research/`, `docs/planning-artifacts/research/`) are dated snapshots: leave them.
- **One fact, one home.** A list that more than one doc needs (runtimes, trigger sources,
  env vars) lives in one place and the others link to it. Where a doc does restate it,
  the change updates every copy.

## Before pushing a branch or opening/updating a PR

Run the cheap checks locally, then let CI run the full suite on the PR.

Before a push:

- the tests for what you changed — `docker compose exec -T web bin/rails test <files>`,
  `docker compose exec -T web ./node_modules/.bin/vitest run <files>`
- the static checks — `docker compose exec -T web make lint_check_all` (rubocop, brakeman,
  eslint, `tsc`, `fsd` via steiger, the watcher test; no database, all in parallel — CI's
  lint job)

Once the PR is open, CI runs everything: lint, system tests, sharded Rails and Vitest,
the merged coverage floors and the secret scan. Watch it (`gh pr checks <n> --watch`).
When a check is red, fix it on the branch and push again. A PR is done when CI is green,
not when it is opened.

`make check_all` still runs the whole CI suite in one local pass. Use it to reproduce a
CI failure locally, not as a gate before every push.

## Docker is required

**NEVER run `ruby`, `bundle`, `rails`, `rake`, or any gem/node-dependent command directly on the host.**
This rule applies to Claude itself AND to every subagent Claude spawns — include it explicitly in every subagent prompt.

Rails, tests, and migrations run **only inside the `web` container** — the host
has no bundled gems, and its `node_modules` is Linux-built (native bindings fail
on the host). If the container isn't running: `docker compose up -d`.

- Backend tests: `docker compose exec -T web bin/rails test <files>`
- Frontend tests: `docker compose exec -T web ./node_modules/.bin/vitest run <files>` (`npx` is not on the container PATH)
- The whole CI suite in one local pass, when you need it: `docker compose exec -T web make check_all`

**Never run two backend test invocations at the same time** (including from another
agent session or a git worktree that shares a Postgres — overlapping runs corrupt
each other's `aixle_test` and the per-worker databases). `make`-driven runs are
flock-serialized; direct `bin/rails test` runs are not — check nothing else is
running first.

### Working in a git worktree

A worktree brings up the *same* stack as the main checkout by default — same
`app_default` network, same `web` image tag, same host ports — so the two fight,
and a branch can quietly run against the main checkout's database. Before
starting Compose from a worktree, give it its own stack: copy the
"Running a second stack from a git worktree" block out of `.env.example` into a
`.env` in the worktree root (Compose reads `.env` only, never `.env.development`).

Full procedure and the traps — Google sign-in, the repo-relative test flock, two
Traefiks on one Docker socket — are in **`docs/project/worktree-stack.md`**. Read
it before running the stack or the suite from a worktree.

### Test parallelization

Parallelization is **on** (task #288, `parallelize(workers: :number_of_processors)` in
`test/test_helper.rb`). Rails forks one worker per core, each with its own database
(`aixle_test-0`, `aixle_test-1`, …), and skips forking for runs under its threshold
(50 cases) — so a single-file `bin/rails test <file>` stays serial while the full suite
does not. The flock is what keeps that safe: concurrent `make` runs never fight over the
shared per-worker databases.

`PARALLEL_WORKERS=1` forces a serial run when one is needed.

## Generated files

`app/frontend/types/generated/` (Typelizer) and `app/frontend/shared/routes.ts` (ts_routes) are generated. **Never edit them by hand**, not even for one union or one route: a later generation reverts the edit or shows the drift.

- Regenerate types with `bin/rails typelizer:generate` after changing an Alba resource, or the enumerize / AASM values a resource exposes.
- Regenerate routes with `bin/rails ts:routes` after changing routes.
- Commit the output with the change that caused it.
- Both need the migrated database schema, so run them in the `web` container (`docker compose exec -T web …`) or in a Coder workspace. If a generator can't run in your environment (no schema, route generation off), don't edit its output: run it where it works, or say in your result that it could not run.

## Writing commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <subject>`.

- **type** — one of `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `style`, `perf`, `build`.
- **scope** — optional, the area touched (e.g. `onboarding`, `web`, `ci`). Omit if the change is broad or scope would be redundant with the subject.
- **subject** — imperative mood ("add", not "added"/"adds"), no trailing period, under ~72 chars.
- A breaking change gets a `!` after the type/scope (`feat(onboarding)!: ...`) and/or a `BREAKING CHANGE:` footer explaining the migration.
- Body (optional, blank line after the subject): explain *why*, not what — the diff already shows what changed.

Examples: `fix(onboarding): guard complete event without configured agent`,
`refactor(state-machine): collapse onboarding to two steps`.

## Writing the changelog

Every PR with a change a user or an operator can notice adds its entry under
`## [Unreleased]` in `CHANGELOG.md`, in the same PR. Releases are cut from that
section (`docs/operations/releasing.md`), so an entry left out is a change the
release notes never mention.

- Prefix the entry with its product area from
  `docs/product/changelog-product-areas.md` (`- **Workflows**: …`). Repository-level
  entries (licensing, contributor rules) carry none. `test/lib/changelog_test.rb` fails
  on an area the taxonomy does not define — add a new sidebar area there, don't invent one.
- Put it under `### Added`, `### Changed`, `### Fixed` or `### Removed`. Say what the
  user can do now, or what changed for an operator (a variable, a migration step), in
  one or two lines — not how it was built.
- Internal-only changes (refactors, tests, CI) get no entry.

## Writing comments

Default to no comment. Code, names and tests carry the *what*; a comment is for
what they cannot carry.

Write one only when it survives this test: **a competent reader of this code
would get it wrong without it.** That is usually a constraint from outside the
file — a protocol quirk, a vendor bug, an ordering requirement, a measured
number, why the obvious approach was rejected. Link the issue, PR or doc when
one exists.

Do not write a comment that restates the line, labels a section, narrates the
diff ("changed to…", "new:"), or explains code that a clearer name or a smaller
method would have explained. Do not leave commented-out code. Do not add a
comment to a file just because the surrounding lines have them.

When a comment is warranted, keep it to what a reader needs: the constraint and
its consequence, not the history of how it was found. Delete it with the code it
describes.

## Writing tests

**Read `docs/testing.md` before writing or changing any test.** It defines what to test at
which layer, the mocking rules (never stub the class under test; don't mock vendor gems —
stub the app-owned adapter or its fake; no `any_instance`), test-data conventions, and the
blessed seams/fakes. Parts of the doctrine are linter-enforced (custom `Testing/*` rubocop
cops, `eslint-plugin-testing-library`); the frozen allowlists in `.rubocop.yml` and
`eslint.config.js` only ever shrink — never add files to them.
