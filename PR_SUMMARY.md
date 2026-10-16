<!-- Suggested PR title:
fix(analytics): include aggregate-only sessions in mixed token totals
Base branch: develop
Head branch: fix/analytics-mixed-token-totals
-->

## Summary

Token totals undercount sessions when a group mixes detailed usage with sessions
that report only an aggregate token count. For example, a session with 100 tokens
in its breakdown plus an aggregate-only session with 200 tokens currently reports
100 instead of 300: the fallback is applied after summing the whole group.

Apply the fallback per session before summing, using a shared SQL expression in
`UsageStatistic`. Update all 12 affected services so project, company and user
summaries, agent breakdowns, time series, workflows and task statistics agree.
The calculation includes input, output and cache tokens, and uses aggregate
`tokens` only when the breakdown is zero.

Add 22 regression tests covering mixed formats, cache tokens, avoiding double
counting, empty summaries and sessions without usage. Update the changelog.
No database migrations are required.

## Related issues

No issue linked.

## Type of change

- [x] Bug fix
- [ ] New feature
- [x] Documentation
- [ ] Refactor / chore
- [ ] Breaking change

## How was this tested?

- Before the fix, the regression suite had 12 failures reporting 100 instead of
  300 tokens. After the fix: **22 tests, 58 assertions**, no failures or errors.
- Isolated run before the develop merge, including the regressions and the three GitHub test files
  affected by local credential configuration: **64 tests, 159 assertions**, no
  failures, errors or skips. `GITHUB_APP_PRIVATE_KEY` was cleared only for that
  process so GitHub tests could use their temporary PEM fixtures.
- The full Rails run completed **8,121 tests and 25,226 assertions**, with
  **3 failures and 25 errors**, all in those three GitHub test files because the
  local inline key took precedence over their fixture keys.
- System tests passed: **9 tests, 51 assertions**. RuboCop, Brakeman, ESLint,
  TypeScript, FSD, watcher tests, Vite build, worker boot and Zeitwerk passed.
- **`make check_all` did not complete:** the web container exited with code 137
  during frontend tests. It was restarted; the full gate still needs a complete
  passing run before submission.
- Independent code review found no actionable issues; `git diff --check` passed.
- After merging `origin/develop` at `3f13b930` (1.3.0), the regression suite,
  existing analytics and task-statistics suites, and analytics controller tests
  passed: **72 tests, 165 assertions**, no failures, errors or skips. The only
  merge conflict was in the changelog; the token fix remains under `[Unreleased]`.
  The schema matches develop, and the fix's diff against develop passes
  `git diff origin/develop --check`. The complete gate remains pending.

Isolated command before the develop merge:

```sh
docker compose exec -T web env GITHUB_APP_PRIVATE_KEY= SKIP_COVERAGE=1 PARALLEL_WORKERS=1 bin/rails test test/services/analytics_token_totals_test.rb test/services/github/repository_service_test.rb test/services/github/check_status_service_test.rb test/services/github/token_service_test.rb
```

## Checklist

- [x] I read [CONTRIBUTING.md](../CONTRIBUTING.md).
- [x] All my commits are signed off for the [DCO](../DCO) (`git commit -s`).
- [ ] I have signed (or will sign) the [CLA](../CLA.md) when the bot prompts me — or my
      organization has executed the [Corporate CLA](../CLA-CORPORATE.md).
- [ ] `make check_all` passes locally (tests, rubocop, brakeman, eslint, typescript).
- [x] I added/updated tests where it makes sense.
- [x] I updated documentation where it makes sense.
- [x] User-visible changes have an entry under `[Unreleased]` in [CHANGELOG.md](../CHANGELOG.md).
- [x] My commits use clear, descriptive messages.
