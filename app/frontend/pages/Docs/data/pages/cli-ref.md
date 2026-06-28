# CLI reference

Aixle Flow exposes its lifecycle through a single `Makefile`. Run any
of these from the repo root.

## Lifecycle

| Command         | What it does                                                                       |
| --------------- | ---------------------------------------------------------------------------------- |
| `make setup`    | One-shot setup: build images, install deps, prepare DB, build agent images.        |
| `make up`       | Start all services (web, worker, db, redis, traefik, temporal).                    |
| `make worker`   | Start only the Temporal worker. Back-compat alias — `make up` already starts it.   |
| `make shell`    | Open a bash shell inside the web container.                                        |

## Dependencies and database

| Command            | What it does                                                       |
| ------------------ | ------------------------------------------------------------------ |
| `make deps`        | `bundle install` + `yarn install` inside the web container.        |
| `make db-prepare`  | `db:create db:migrate db:seed`.                                    |
| `make db-reset`    | `db:drop db:create db:migrate db:seed`. **Destroys local data.**   |
| `make restore-dump`| Restore from `/db_dumps/latest.sql.gz`.                            |

## Checks and linters

| Command            | What it does                                                                |
| ------------------ | --------------------------------------------------------------------------- |
| `make check`       | Run backend + frontend checks sequentially, stop on first failure.          |
| `make check_all`   | Run all checks in parallel (this is what CI runs), never short-circuit, print the full log of any failed check, exit non-zero if any fail. |
| `make lint`        | All linters: eslint-fix, rubocop-fix, brakeman, typescript.                 |
| `make test`        | Rails tests (`bundle exec rails test`).                                     |
| `make rails-test`  | Same as above.                                                              |
| `make rubocop`     | Ruby linter.                                                                |
| `make rubocop-fix` | Ruby linter with `-a` autocorrect.                                          |
| `make eslint`      | JS/TS linter.                                                               |
| `make eslint-fix`  | JS/TS linter with autofix.                                                  |
| `make typescript`  | `yarn tsc` — TypeScript compile check.                                      |
| `make brakeman`    | Rails security analysis.                                                    |

## Images

| Command                 | What it does                                                       |
| ----------------------- | ------------------------------------------------------------------ |
| `make build-web`        | Build the web image.                                               |
| `make build-otlp-ingest`| Build the OpenTelemetry ingest image.                              |
| `make build-agents`     | Build all four agent runtime images (`claude_code`, `cursor_cli`, `codex`, `gemini_cli`) plus the shared `agent-base-core`. Agents build in parallel. |

## Help

```bash
make help
```

Lists every target with a short description.
