# CLI reference

Aixle Flow exposes its lifecycle through a single `Makefile`. Where a
target runs depends on what it calls:

- **On the host**, from the repo root: everything under *Lifecycle* and
  *Images*, `make restore-dump` and `make secret-scan`. These drive Docker;
  `make setup` and `make build-agents` also need `jq`.
- **Inside the `web` container**: everything else. These call `bundle`,
  `yarn` and `rails` directly, and those exist only in the container.

With the stack up, run a container target through it:

```bash
docker compose exec -T web make <target>
```

## Lifecycle

| Command         | What it does                                                                       |
| --------------- | ---------------------------------------------------------------------------------- |
| `make setup`    | One-shot setup: build images, install deps, prepare DB, build agent images.        |
| `make up`       | Start all services (web, worker, db, redis, traefik, temporal).                    |
| `make down`     | Stop and remove the containers. Volumes stay.                                      |
| `make reset`    | `docker compose down -v`: also removes the volumes. **Destroys local data.**       |
| `make worker`   | Start only the Temporal worker. Back-compat alias — `make up` already starts it.   |
| `make shell`    | Open a bash shell inside the web container.                                        |
| `make git-hooks`| Point git at `.githooks`, which signs every commit off (DCO). `make setup` runs it. |

## Dependencies and database

| Command            | What it does                                                       |
| ------------------ | ------------------------------------------------------------------ |
| `make deps`        | `bundle install` + `yarn install`.                                 |
| `make db-prepare`  | `db:create db:migrate db:seed`.                                    |
| `make db-reset`    | `db:drop db:create db:migrate db:seed`. **Destroys local data.**   |
| `make restore-dump`| Replace the local dev database with `/db_dumps/latest.sql.gz` (refuses any other database). Runs `make db_restore` in a one-off web container. |
| `make license-report` | Ruby gem and npm production license reports, written to `tmp/license-reports/`. `license-report-ruby` and `license-report-js` write one each. |

## Checks and linters

| Command            | What it does                                                                |
| ------------------ | --------------------------------------------------------------------------- |
| `make check`       | Same as `check_all`. Changes nothing; `make fix` is the autocorrecting pass. |
| `make default`     | Same as `make check`.                                                       |
| `make check_all`   | The local one-pass equivalent of CI: every Rails and frontend check, coverage floors included. Never short-circuits, prints the full log of any failed check, exits non-zero if any fail. CI runs the same checks split into the lint, system, Rails, Vitest and coverage jobs below, plus the secret scan and the Go runner tests. |
| `make be_check_all` | The backend half of `check_all`: boot checks, the Rails and system suites, rubocop, brakeman. |
| `make fe_check_all` | The frontend half of `check_all`: eslint, typescript, fsd, the watcher test, then Vitest. |
| `make lint_check_all` | CI's lint job: rubocop, brakeman, eslint, typescript, fsd and the watcher test in parallel. No database. |
| `make system_check_all` | CI's system job: the boot checks and the system suite.                  |
| `make rails_check_all` | CI's Rails job: shard `SHARD` of `TOTAL_SHARDS` of the Rails suite.       |
| `make vitest_check_all` | CI's Vitest job: shard `FE_SHARD` of `FE_TOTAL_SHARDS` of the frontend suite. |
| `make coverage_merge` | CI's coverage job: merges the shards' coverage and enforces both floors.  |
| `make secret-scan` | The gitleaks scan CI runs. Runs on the host: it needs Docker.               |
| `make be_check`    | `rails-test`, `rubocop` and `brakeman`.                                     |
| `make fe_check`    | `eslint`, `typescript`, `fsd` and `fe-test`.                                |
| `make lint`        | All linters: eslint, rubocop, brakeman, typescript — no autocorrect.        |
| `make fix`         | Autocorrect: rubocop -a, eslint --fix, steiger --fix.                       |
| `make test`        | Rails tests (`bundle exec rails test`).                                     |
| `make rails-test`  | Same as above.                                                              |
| `make fe-test`     | Frontend tests (`yarn test`, Vitest).                                       |
| `make worker-boot` | Boot the Temporal worker far enough to prove it starts.                     |
| `make rubocop`     | Ruby linter.                                                                |
| `make rubocop-fix` | Ruby linter with `-a` autocorrect.                                          |
| `make eslint`      | JS/TS linter.                                                               |
| `make eslint-fix`  | JS/TS linter with autofix.                                                  |
| `make fsd`         | Feature-Sliced Design check (steiger).                                      |
| `make fsd-fix`     | Feature-Sliced Design check with autocorrect.                               |
| `make typescript`  | `yarn tsc` — TypeScript compile check.                                      |
| `make brakeman`    | Rails security analysis.                                                    |

## Images

| Command                 | What it does                                                       |
| ----------------------- | ------------------------------------------------------------------ |
| `make build-web`        | Build the web image.                                               |
| `make build-otlp-ingest`| Build the OpenTelemetry ingest image.                              |
| `make build-agents`     | Build all eight agent runtime images (`claude_code`, `cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`, `kiro_cli`, `copilot_cli`) plus the shared `agent-base-core`. Agents build in parallel. |

## Help

```bash
make help
```

Prints most targets with a short description. It leaves out `build-web`,
`secret-scan`, `worker-boot`, `be_check`, `fe_check`, `coverage_merge` and
the `*_check_all` targets.
