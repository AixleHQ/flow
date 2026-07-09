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
- **Frontend:** `eslint`, `typescript` (`tsc`), `vitest`

(CI splits this into `be_check_all` + `fe_check_all`; `check_all` covers both
locally.) Don't push a branch or open/update a PR until `check_all` is green —
it catches what a partial, hand-picked test run misses.

## Docker is required

Rails, tests, and migrations run **only inside the `web` container** — the host
has no bundled gems, and its `node_modules` is Linux-built (native bindings fail
on the host). If the container isn't running: `docker compose up -d`.

- Backend tests: `docker compose exec -T web bin/rails test <files>`
- Frontend tests: `docker compose exec -T web ./node_modules/.bin/vitest run <files>` (`npx` is not on the container PATH)
- Full suite before push: `docker compose exec -T web make check_all`

**Never run two backend test invocations at the same time** (including from another
agent session or a git worktree — worktrees share the same Postgres and the same
`aixle_test` database, so overlapping runs corrupt each other). `make`-driven runs
are flock-serialized; direct `bin/rails test` runs are not — check nothing else is
running first. Test parallelization is deliberately off — see the note in
`test/test_helper.rb` before re-enabling.

## Writing tests

**Read `docs/testing.md` before writing or changing any test.** It defines what to test at
which layer, the mocking rules (never stub the class under test; don't mock vendor gems —
stub the app-owned adapter or its fake; no `any_instance`), test-data conventions, and the
blessed seams/fakes. Parts of the doctrine are linter-enforced (custom `Testing/*` rubocop
cops, `eslint-plugin-testing-library`); the frozen allowlists in `.rubocop.yml` and
`eslint.config.js` only ever shrink — never add files to them.
