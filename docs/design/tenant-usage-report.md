# Admin dashboard and tenant usage — technical design

**Status:** Implemented.
**Date:** 2026-10-19
**Code baseline:** `3f13b930`
**Audience:** Engineers changing the admin dashboard, the rollup behind it or the billing rules it reports on; platform operators who read it.
**Related:** [session-admission-queue/](./session-admission-queue/) (what a worker is, admission and release), [operations/stripe-setup.md](../operations/stripe-setup.md) (the meter that bills worker-minutes).

## 1. Request and decisions

Leadership asked for a report of usage across tenants, **to track adoption and to track billing**. The mock-up they shared is a table with one row per tenant for a day, week, month or custom range. Its columns are worker hours, min and max workers, utilization, average and maximum queue wait, and successful and failed sessions, each with the change from the previous period.

Decisions taken on 2026-10-19:

1. **The report is the mock-up**, as the admin's home page: one table, the same periods, the same comparison with the previous period. Two columns are added to it: the billing status of each tenant, and its peak workers. Above it, tiles give the platform at a glance (§7).
2. **Usage is measured for every company**, including companies with no worker limit and companies flagged `managed_by_aixle`. What reaches a provider is unchanged: Stripe in `saas`, AWS Marketplace metering in `aws_marketplace`, nothing in `self_hosted`. The report says for each tenant whether its usage is billed and, if not, why. Free usage made visible is what lets us move a demo tenant onto a paid plan.
3. **Measure by the hour; days, weeks and months are sums.** No daily table.
4. **The dashboard lives in the superadmin area**, as the home page of `/admin`, and the whole admin takes on the Aixle Flow theme (§7).
5. **Free means managed.** Where we host, a company runs without paying only when it is flagged `managed_by_aixle`. Every other company is paying, on a trial, or blocked; there is no other way to run free or unlimited (§8).
6. **One pull request.** Not in it: tracking active people (adoption beyond sessions), recording who changed a worker limit, a CSV export, an agent breakdown. §10 lists them.

## 2. What existed before

| Need | What we had | Gap |
| --- | --- | --- |
| Billed capacity per company | `company_capacity_usages`, written hourly by `Billing::CapacityMeter`: the limit integrated over the hour (`CapacityWindow`, time-weighted). | A company with no limit offers 0 and is dropped (`capacity_window.rb:61`), so it gets **no row at all**. The 2026-10-09 backfill made Dualboot Partners, Acme and Microsoft-Dualboot managed and left their limits unset, so unless a limit has been set on them since, they have no usage rows. |
| Workers actually busy | Nothing aggregated. `session_admissions.admitted_at → released_at` holds every slot held, since #325 (2026-09-25). | Needs a rollup. |
| Queue wait | `session_admissions.created_at → admitted_at`. | Needs a rollup. |
| Session outcomes | `terminal_sessions.state` and `finished_at`, set for `finished`, `failed` and `cancelled` alike. | None. |
| Limit history | `company_capacity_changes`: `company_id`, `max_sessions` (null means cleared), `occurred_at`. | No actor and no source (§10). |
| Superadmin UI | Administrate 1.0 (ERB) under `namespace :admin`, rooted at `users#index`. | No overview page. The theme and React live in the Inertia app. |

## 3. Definitions

- **Worker.** One admitted session in a **project** pool. Agent logins queue in `user:<id>` pools and draw on no company budget (`SessionAdmissionService::AUTH_POOL_LIMIT`), so they are not workers. This is exactly what the company limit governs.
- **Limit.** The company's configured `SessionConcurrencyLimit`, read the way the meter reads it: the change log where the company has an entry, its live row where it has none. **Unlimited** means no limit.
- **Worker hours** (offered). The billing ledger's quantity for the hour: the limit integrated over time, clamped by billing ceilings. It is 0 when the company is unlimited, blocked or inactive. This is what a paying tenant is charged for, used or not.
- **Busy hours** (occupied). For each worker, the overlap of `admitted_at … (released_at or the end of the hour)` with the hour. A slot is held until release is confirmed, so a container still being torn down counts.
- **Peak workers.** The most workers held at one moment in the hour. A release and an admission at the same instant are a hand-over, not two workers.
- **Utilization.** Busy ÷ worker hours. It has no value for a tenant with no worker hours.
- **Unlimited time on the page.** The ledger offers 0 while a company has no limit, which would leave an unlimited tenant with no worker hours and no utilization. The page counts that time's busy hours as its worker hours instead, so it shows as fully used. The stored rows keep the ledger's number; the page splits a day the limit was set or cleared on by `unlimited_seconds ÷ (hours × 3600)`, so busy time on such a day is attributed in proportion rather than by the hour.
- **Wait.** `admitted_at − created_at` for each admission granted in the hour. A session still waiting is counted as queued only.
- **Outcome.** Sessions of type `agent_session` or `workflow_step` (`AnalyticsPeriod::USAGE_SESSION_TYPES`), counted in the hour of `finished_at`: succeeded is `finished`, failed is `failed`. A `cancelled` session is neither.
- **Periods.** Hours are UTC. Weeks start on Monday, as in the mock-up. Because the stored grain is the hour, moving the report to another time zone later only shifts the day boundary; nothing is re-measured.

## 4. Data model

`company_usage_hours`: one row per company per closed UTC hour, unique on `(company_id, period_start)` and indexed on `period_start`.

| Column | Meaning |
| --- | --- |
| `limit_min`, `limit_max` | The smallest and largest limit in the hour, over the seconds it had one. Null if it had none. |
| `unlimited_seconds` | Seconds of the hour with no limit. |
| `offered_seconds` | Copied from `company_capacity_usages` for the same hour, or 0 if there is no row. |
| `billing_class` | Why the hour is or is not billed (§6). |
| `occupied_seconds`, `peak_workers` | Busy worker-seconds and the peak. |
| `sessions_queued`, `sessions_admitted` | Admissions created in the hour; admissions granted in it. |
| `wait_seconds_total`, `wait_seconds_max` | Over the admissions granted in the hour. |
| `sessions_succeeded`, `sessions_failed` | |
| `computed_at` | |

A row is written for every `active` company every hour, used or not: an idle hour of a paying company is still an hour it was billed for. A suspended or archived company gets a row only for an hour in which something of it still ran. Volume is companies × 8,760 rows a year.

**Separate from the billing ledger on purpose.** `company_capacity_usages` stays the ledger the free allowance is counted from and the Billing tab reads. Billing runs as one attempt per hour because AWS Marketplace double-bills a retry; a reporting bug must never be able to fail that run, and measuring an hour again must never change a billed number. So the report copies `offered_seconds` from the ledger instead of measuring it again, which also means filling in history never has to rebuild billing ceilings that are not stored.

Two indexes were added for the rollup's reads: `session_admissions.released_at` and `terminal_sessions.finished_at`.

## 5. Rollup

`Usage::HourlyRollup.call(from:, to:)` measures closed hours and upserts their rows. It is pure over the database, so measuring an hour again rewrites the same row. It works a day at a time: one query each for the admissions overlapping the day, the sessions that ended in it, the ledger rows and the limit changes, then every hour of the day in memory.

- `usage_rollup_workflow` runs at `10 * * * *`, five minutes after metering so the ledger row exists, with overlap skipped. Unlike metering it retries.
- **Each run measures the hours not yet measured, and the last three again.** Remeasuring the trailing hours picks up a ledger row written late and any transition committed after its hour closed. Measuring from the last measured hour means a run after the worker was down fills in the hours it missed.
- **History needs no backfill step.** On the first run the table is empty, so the run measures every hour since the first session admission or the first metered hour, whichever is earlier. No migration and no button are involved. A migration was rejected because it would carry app code that `db/migrate` has to keep replaying from zero (`SchemaParityTest`), and because a production deploy should not wait on a data job.
- **Rebuilding after a fix to the rollup:** start `usage_rollup_workflow` with `{"from_hour": "<ISO hour>"}` (and optionally `to_hour`) from the Temporal CLI or UI. It measures that range again.
- **What history exists.** Busy hours, peak and wait exist from 2026-09-25 (#325), when every session started having an admission row. Worker hours exist from the hour metering first ran in each environment (production: 2026-09-30). Outcomes are counted from the same start, since earlier hours are not measured. The billing class of a history hour is the company's class at the time of the first run, since no history of it is kept; it is accurate from this release on.

## 6. Billing class

Computed when a row is written; the first rule that matches wins.

| Class | Rule | Shown as |
| --- | --- | --- |
| `not_metered` | `self_hosted` deployment | Not metered |
| `inactive` | The company is suspended or archived | Inactive |
| `paying` | `aws_marketplace` deployment: every active company is billed | Paying |
| `managed` | `managed_by_aixle` | Free · managed |
| `blocked` | `billing_state = blocked` | Blocked |
| `trial` | `billing_state = trialing` | Trial |
| `unlimited` | No limit for the whole hour | Not billed · no limit |
| `no_customer` | Billable, but no `stripe_customer_id` (`Meter::Stripe` skips it) | Not billed · no Stripe customer |
| `paying` | Anything else | Paying |

A period shows the class of its last measured hour. `unlimited` and `no_customer` are a company running free without being managed, which §8 makes impossible from here on; they stay in the report, in red, so that a company that gets there anyway is seen.

## 7. The dashboard

`Admin::DashboardsController#show` is the root of `namespace :admin` and the first link in its navigation, so the dashboard sits inside the superadmin area with Administrate's layout.

- **Tiles.** Six of them sit above the table. Three describe the platform as it stands: active companies with their split by billing class, active members, and active projects. Three describe the selected period, each with its change from the period before: worker hours, busy hours with the share of them not on a paid plan, and successful sessions with how many failed.
- **The data.** The ERB view renders one mount point carrying it. `Usage::TenantReport` sums hours into one row per company per UTC day for the last 400 days, and counts the platform's size. The browser sums days into weeks, months and custom ranges and compares each with the period before, the way the mock-up does. A period still in progress is compared with the same number of days of the one before.
- **The island renders no Mantine.** `entrypoints/admin_dashboard.tsx` mounts React without `MantineProvider` and without Mantine's global CSS, which would restyle Administrate's chrome. The code lives in `app/frontend/pages/Admin/Dashboard/`: the aggregation and comparison in `aggregate.ts`, the tiles in `Tiles.tsx`, the table in `Dashboard.tsx`. Its CSS module scopes every rule under `.root`, a class above Administrate's element selectors and its `[type=button]:not(.link):hover`.
- **The admin's theme.** `app/views/administrate/application/_stylesheet.html.erb` loads `entrypoints/admin.css` and the brand fonts after Administrate's own stylesheet on every admin page. That skin gives the admin the Aixle Flow light theme: Figtree and Hanken Grotesk, the orange accent for links, buttons and the active navigation entry, Primer-like neutrals, rounded cards, and the logo at the top of the navigation. With no Mantine to inject them, the skin declares the light-scheme `--app-*` tokens it and the dashboard use. `test/config/admin_skin_tokens_test.rb` fails when one of them differs from `mantineTheme.ts`, or when either file uses a token the skin does not declare.

| Mock-up column | Here | Note |
| --- | --- | --- |
| Worker hours | Worker hours, and Busy hours beside it | A paying tenant is billed for capacity offered, not used, so both are needed. |
| Min / max workers | The limit's min and max (∞ when unlimited), and Peak workers | The mock-up reads like an autoscaled pool; ours is a configured limit, and the actual concurrency goes beside it. |
| Utilization % | Busy ÷ worker hours | |
| Average / max wait | Average and p95 admission wait | The p95 replaced the maximum on 2026-10-30, which one outlier decides (§7.1). |
| Successful / failed sessions | `finished` / `failed` | |

### 7.1 A company's breakdown

Added 2026-10-30. The table raised a question it could not answer: a company with low utilization whose sessions still waited for long stretches. On production every hour with a wait over 30 s had its peak at the limit — the queue was full in working hours and empty at night, and a period's utilization averages the two. Leadership then asked for the wait measured from the moment an item joins the queue, for how many items stood ahead of it, and for the p95 wait rather than the maximum, which one outlier decides.

The company's name in the table opens a dialog for the selected period. It fetches `GET /admin/dashboard/companies/:id.json?from=&to=` (`Admin::DashboardCompaniesController`), which `Usage::CompanyBreakdown` answers from the admissions themselves: a percentile and a queue position cannot be summed from hours. Every aggregate is computed in Postgres, so a year of a busy company never reaches Ruby.

| Figure | Definition |
| --- | --- |
| Wait | `admitted_at − created_at` of each project session admitted in the period. The admission is created the moment the session joins the queue (`SessionService` enqueues and drains back to back), so this is already the wait from joining. |
| Waited | A wait over 30 s. Anything shorter was granted on the first drain after it joined. |
| Percentiles | Average, median, p90, p95, p99 and max of every session's wait, and p95 among only those that waited. p95 over all sessions alone hides a queue that most sessions skip: when only a few percent of a company's sessions wait, p95 reads a second or two however long those few waited. |
| Already waiting | For each session, how many of the company's sessions — and of its project's — were waiting when it joined. A running sum over join and leave events: leaving sorts before joining at the same instant, simultaneous joins go by id, and sessions waiting across the start of the period count. |
| Per workflow run | A run queues once per step, each time at the back of the line, so its wait is the sum of its steps' waits. |
| Time at capacity | The share of the hours the company had workers (`offered_seconds > 0`) during which every one was held at once. A sweep over admit and release events, with each hour's start as an event too, so a stretch is always read against its own hour's offered workers. An hour's peak would not do: with a limit of one, any session at all makes the peak the limit. |
| Waits that began at capacity | Of the sessions that waited, how many joined while every worker was held. The rest waited for their project's limit. |
| Waits by day | Each UTC day of the period that had sessions: how many waited, out of how many, and that day's p95. A chart of hours of the day averaged over the period was tried first and dropped: it averages the bursts away again, the way utilization does. |
| Projects | Each project's sessions, waits and longest line, with its queue limit — its reservation or the default — as it stands now. |

A company with no worker limit in the period gets no utilization: nothing capped it, and its waits come from its projects' limits alone.

**The table's p95.** For the same reason the table's wait column is the p95 rather than the maximum, and it is not in the page's data either. For the selected period, and for the period it is compared with, the page fetches `GET /admin/dashboard/waits.json?from=&to=` (`Usage::TenantWaits`): every company's p95 over the sessions admitted in those days, the same sessions the breakdown counts. Each range is fetched once while the page is open.

## 8. Free means managed

Where we host, a company is paying, on a trial, blocked, or carried by Aixle (`managed_by_aixle`). Before this change it could also run free in two other ways, both through the admin:

- **Without a worker limit.** Unlimited is never metered. The admin required a limit when a company was created but not when it was edited, and a limit row could be deleted from the admin's list of limits.
- **`active` without a Stripe customer.** The admin form moved a company to `active` by hand, a path kept from before Stripe was wired up. The Stripe meter skips a company with no customer, so it ran free from then on.

Now:

| Path | Rule | Where |
| --- | --- | --- |
| Clearing the limit of a company that is not managed (company admin form, settings, console) | Refused: `is required for a company that pays — tick Managed by Aixle for one that does not` | `Company#session_concurrency_limit_is_a_positive_integer`, when the limit is assigned |
| Deleting a company's limit row (admin list of limits, console) | Refused | `SessionConcurrencyLimit#refuse_to_unbound_a_metered_company`, which already refused it on AWS Marketplace |
| Setting a company that is not managed running by hand (`active` or `trialing`) with no Stripe customer — typically letting a blocked one back in | Starts a new trial instead: `trialing`, `trial_started_at` now, and `Billing::Trial` counts the allowance from then, so the company runs again and needs a card once it is spent | `Admin::CompaniesController#update`. A form rule, not a model one: the Stripe webhook moves companies to `active` on its own terms. |

`db/migrate/20261019100200_mark_free_active_companies_managed.rb` flags, where we host, every `active` company that is not managed but has no limit or no Stripe customer. Such a company already runs free; the flag makes that deliberate, and nothing it can run changes. Trialing and blocked companies are left alone. An operator who would rather bill one unticks the flag, which starts it on the trial (#456).

`trial_started_at` is null for every existing company, so the allowance it is spending is still counted over everything it ever used. Only an operator's restart starts a count of its own; unticking Managed by Aixle still does not (#456).

Elsewhere nothing changes: self-hosted installations bill nobody, and AWS Marketplace already required a limit for every company.

**Checked against production on 2026-10-19** (read-only `psql`): the deployment is `saas`, every one of its six companies is managed, so the migration flags none; no company is trialing or blocked without a limit; the first rollup run reaches back to the first admission on 2026-09-05, about 6,200 rows from 24,800 admissions; the two new indexes go on tables of 25 MB and 242 MB, built concurrently.

## 9. Verification

Model, service and activity tests cover occupancy and peak, waits, agent logins, outcomes, limits, every billing class, idempotency, the closed-hours rule and catching up on unmeasured hours. The workflow is run through the time-skipping test server. Request and model tests cover the dashboard and the rules of §8. Vitest covers the period and comparison arithmetic, the tiles and the table's behavior.

On a local stack seeded with nine companies across the billing classes and seven weeks of queued sessions run through the real meter and the real rollup, the dashboard and the restyled admin were checked in a browser.

## 10. Not in this change

1. **Active people.** Adoption beyond sessions needs a record of who used the product on which day. Sessions cannot stand in for it: a run a schedule or a webhook started carries its trigger owner's `user_id` with nobody present, and `workflow_runs` does not record what started a run. The cheap way to record it is a `(user_id, company_id, day)` row written from the existing five-minute `UserSession#touch_if_stale!`, at most one write per person per company per day.
2. **Who changed a worker limit.** `company_capacity_changes` records when and the new value, but no actor and no source. Adding `actor_id`, `impersonator_id` and `source`, filled from `Current`, would make the history answerable.
3. **CSV export** — not needed while the page is live in the admin.
4. **Agent mix.** Sessions and busy hours by `agent_type` and model, read from `terminal_sessions` for the period.
