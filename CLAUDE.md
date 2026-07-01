# CLAUDE.md

Guidance for AI agents working in this repository.

## Before pushing a branch or opening/updating a PR

**ALWAYS run the full check suite in Docker first, and only push once it is green:**

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
