# CLAUDE.md

Guidance for AI agents working in this repository.

## Documentation index

`docs/index.md` is the index of all architecture/design/research docs. Whenever you
add, remove, or move a document under `docs/`, update `docs/index.md` in the same change.

## Before pushing a branch or opening/updating a PR

**before push final results to repo - run the full check suite in Docker first, and only push once it is green:**

```bash
docker compose exec -T web make check_all
```

`check_all` mirrors CI in a single pass and never short-circuits — it captures
each result and prints a summary of all failures:

- **Backend:** `rails test`, `rubocop`, `brakeman`
- **Frontend:** `eslint`, `typescript` (`tsc`), `fsd` (Feature-Sliced Design check via steiger), `vitest`

(CI splits this into `be_check_all` + `fe_check_all`; `check_all` covers both
locally.) Don't push a branch or open/update a PR until `check_all` is green —
it catches what a partial, hand-picked test run misses.

## Docker is required

**NEVER run `ruby`, `bundle`, `rails`, `rake`, or any gem/node-dependent command directly on the host.**
This rule applies to Claude itself AND to every subagent Claude spawns — include it explicitly in every subagent prompt.

Rails, tests, and migrations run **only inside the `web` container** — the host
has no bundled gems, and its `node_modules` is Linux-built (native bindings fail
on the host). If the container isn't running: `docker compose up -d`.

- Backend tests: `docker compose exec -T web bin/rails test <files>`
- Frontend tests: `docker compose exec -T web ./node_modules/.bin/vitest run <files>` (`npx` is not on the container PATH)
- Full suite before push: `docker compose exec -T web make check_all`

**Never run two backend test invocations at the same time** (including from another
agent session or a git worktree that shares a Postgres — overlapping runs corrupt
each other's `aixle_test` and the per-worker databases). `make`-driven runs are
flock-serialized; direct `bin/rails test` runs are not — check nothing else is
running first.

### Test parallelization

Parallelization is **on** (task #288, `parallelize(workers: :number_of_processors)` in
`test/test_helper.rb`). Rails forks one worker per core, each with its own database
(`aixle_test-0`, `aixle_test-1`, …), and skips forking for runs under its threshold
(50 cases) — so a single-file `bin/rails test <file>` stays serial while the full suite
does not. The flock is what keeps that safe: concurrent `make` runs never fight over the
shared per-worker databases.

`PARALLEL_WORKERS=1` forces a serial run when one is needed.

## Writing commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <subject>`.

- **type** — one of `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `style`, `perf`, `build`.
- **scope** — optional, the area touched (e.g. `onboarding`, `web`, `ci`). Omit if the change is broad or scope would be redundant with the subject.
- **subject** — imperative mood ("add", not "added"/"adds"), no trailing period, under ~72 chars.
- A breaking change gets a `!` after the type/scope (`feat(onboarding)!: ...`) and/or a `BREAKING CHANGE:` footer explaining the migration.
- Body (optional, blank line after the subject): explain *why*, not what — the diff already shows what changed.

Examples: `fix(onboarding): guard complete event without configured agent`,
`refactor(state-machine): collapse onboarding to two steps`.

## Writing tests

**Read `docs/testing.md` before writing or changing any test.** It defines what to test at
which layer, the mocking rules (never stub the class under test; don't mock vendor gems —
stub the app-owned adapter or its fake; no `any_instance`), test-data conventions, and the
blessed seams/fakes. Parts of the doctrine are linter-enforced (custom `Testing/*` rubocop
cops, `eslint-plugin-testing-library`); the frozen allowlists in `.rubocop.yml` and
`eslint.config.js` only ever shrink — never add files to them.
