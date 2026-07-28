# Deferred Work

Pre-existing or out-of-scope issues surfaced during reviews. Not blockers for the story that logged them.

## From spec-multi-company-membership (2026-07-02 review)

- **Session-cookie last-writer-wins race on `current_company_id`** — a slow request started before `POST /company/switch` can commit its cookie after the switch response and revert it. Inherent to cookie sessions; would need server-side session store or a version guard. (Blind Hunter m1)
- **Last-admin concurrent race** — two admins demoting/revoking each other concurrently can leave a company with zero active admins; the guard is validation-only. Needs `company.with_lock` around admin-exit transitions or a DB-level constraint. (Edge Hunter #8)
- **Project-less (auth_setup) sessions have no home company** — currently fan out to every company where the user is an active member (list + broadcast aligned). Product decision pending: tag sessions with the company they were launched under (`terminal_sessions.company_id` hardening step from the research report) and scope to it. (Blind Hunter M5 residual)
- **Zero-downtime deploy story for the users-table contract** — old app instances selecting `users.role/company_id` during a rolling deploy will raise `UndefinedColumn` once migration 20260727100004 runs. Fine for single-instance deploys; revisit if rolling deploys arrive (`ignored_columns` two-step). (Blind Hunter M7 residual)
- **Admin "Activate" on an invited membership accepts on the invitee's behalf** — parity with the legacy manual-activation flow, but it bypasses the emailed-link ownership proof. Product decision whether to restrict to resend-only. (Blind Hunter m9 / Auditor F8a)

## From spec-session-terminal-replay (2026-07-20 review)

- source_spec: `docs/implementation-artifacts/spec-session-terminal-replay.md`
  summary: `AixleBuilderControllerTest#test_show_does_not_issue_N+1_queries_when_multiple_sessions_exist` is cache-sensitive and flaky (cold/isolated run issues ~24 queries vs the `<= 15` budget; passes warm in a full suite run).
  evidence: Reproduces identically on clean `develop` with all story changes stashed (still got 24), so it is pre-existing, not caused by this story. The `terminal_log_url` attribute added here is state-gated (a column read) and adds zero queries — confirmed by disabling the attribute (still 24). The budget assertion should either warm the query cache before counting or raise/track the real baseline.
