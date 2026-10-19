# Tenant usage report — technical design

**Status:** Implemented.
**Date:** 2026-10-19
**Code baseline:** `3f13b930`
**Audience:** Engineers changing the report or the rollup behind it; platform operators who read it.
**Related:** [session-admission-queue/](./session-admission-queue/) (what a worker is, admission and release), [operations/stripe-setup.md](../operations/stripe-setup.md) (the meter that bills worker-minutes).

## 1. Request and decisions

Leadership asked for a report of usage across tenants, **to track adoption and to track billing**. The mock-up they shared is a table with one row per tenant for a day, week, month or custom range. Its columns are worker hours, min and max workers, utilization, average and maximum queue wait, and successful and failed sessions, each with the change from the previous period.

Decisions taken on 2026-10-19:

1. **The report is the mock-up.** One table, the same periods, the same comparison with the previous period. Two columns are added to it: the billing status of each tenant, and its peak workers.
2. **Usage is measured for every company**, including companies with no worker limit and companies flagged `managed_by_aixle`. What reaches a provider is unchanged: Stripe in `saas`, AWS Marketplace metering in `aws_marketplace`, nothing in `self_hosted`. The report says for each tenant whether its usage is billed and, if not, why. Free usage made visible is what lets us move a demo tenant onto a paid plan.
3. **Measure by the hour; days, weeks and months are sums.** No daily table.
4. **The report lives in the superadmin area**, as the home page of `/admin`, in the Aixle Flow theme.
5. **One pull request.** Not in it: tracking active people (adoption beyond sessions), recording who changed a worker limit, a CSV export, an agent breakdown. §9 lists them.

## 2. What existed before

| Need | What we had | Gap |
| --- | --- | --- |
| Billed capacity per company | `company_capacity_usages`, written hourly by `Billing::CapacityMeter`: the limit integrated over the hour (`CapacityWindow`, time-weighted). | A company with no limit offers 0 and is dropped (`capacity_window.rb:61`), so it gets **no row at all**. The 2026-10-09 backfill made Dualboot Partners, Acme and Microsoft-Dualboot managed and left their limits unset, so unless a limit has been set on them since, they have no usage rows. |
| Workers actually busy | Nothing aggregated. `session_admissions.admitted_at → released_at` holds every slot held, since #325 (2026-09-25). | Needs a rollup. |
| Queue wait | `session_admissions.created_at → admitted_at`. | Needs a rollup. |
| Session outcomes | `terminal_sessions.state` and `finished_at`, set for `finished`, `failed` and `cancelled` alike. | None. |
| Limit history | `company_capacity_changes`: `company_id`, `max_sessions` (null means cleared), `occurred_at`. | No actor and no source (§9). |
| Superadmin UI | Administrate 1.0 (ERB) under `namespace :admin`, rooted at `users#index`. | No overview page. The theme and React live in the Inertia app. |

## 3. Definitions

- **Worker.** One admitted session in a **project** pool. Agent logins queue in `user:<id>` pools and draw on no company budget (`SessionAdmissionService::AUTH_POOL_LIMIT`), so they are not workers. This is exactly what the company limit governs.
- **Limit.** The company's configured `SessionConcurrencyLimit`, read the way the meter reads it: the change log where the company has an entry, its live row where it has none. **Unlimited** means no limit.
- **Worker hours** (offered). The billing ledger's quantity for the hour: the limit integrated over time, clamped by billing ceilings. It is 0 when the company is unlimited, blocked or inactive. This is what a paying tenant is charged for, used or not.
- **Busy hours** (occupied). For each worker, the overlap of `admitted_at … (released_at or the end of the hour)` with the hour. A slot is held until release is confirmed, so a container still being torn down counts.
- **Peak workers.** The most workers held at one moment in the hour. A release and an admission at the same instant are a hand-over, not two workers.
- **Utilization.** Busy ÷ worker hours. It has no value for a tenant with no worker hours.
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

**Separate from the billing ledger on purpose.** `company_capacity_usages` stays the ledger the free allowance is counted from and the Billing tab reads. Billing runs as one attempt per hour because AWS Marketplace double-bills a retry; a reporting bug must never be able to fail that run, and a recompute must never change a billed number. So the report copies `offered_seconds` from the ledger instead of measuring it again, which also means a backfill never has to rebuild billing ceilings that are not stored.

Two indexes were added for the rollup's reads: `session_admissions.released_at` and `terminal_sessions.finished_at`.

## 5. Rollup

`Usage::HourlyRollup.call(from:, to:)` measures closed hours and upserts their rows. It is pure over the database, so measuring an hour again rewrites the same row. It works a day at a time: one query each for the admissions overlapping the day, the sessions that ended in it, the ledger rows and the limit changes, then every hour of the day in memory.

- `usage_rollup_workflow` runs at `10 * * * *`, five minutes after metering so the ledger row exists, with overlap skipped. Unlike metering it retries. Each run measures the **last three closed hours**, which picks up a ledger row written late and any transition committed after its hour closed.
- **Recompute** on the report page starts the same workflow with a start date, under the stable id `usage_rollup_workflow-recompute`, so a second click while one runs is refused by Temporal. It is how history is filled in after a deploy; the production web pod cannot run `rails runner`.
- **What history can be recomputed.** Busy hours, peak and wait exist from 2026-09-25 (#325), when every session started having an admission row. Outcomes exist for every session. Worker hours exist from the hour metering first ran in each environment (production: 2026-09-30). The billing class of a recomputed hour is the company's class now, since no history of it is kept; it is accurate from this release on.

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
| `unlimited` | No limit for the whole hour | Free · unlimited |
| `no_customer` | Billable, but no `stripe_customer_id` (`Meter::Stripe` skips it) | No Stripe customer |
| `paying` | Anything else | Paying |

A period shows the class of its last measured hour.

## 7. The page

`Admin::TenantUsagesController#show` is the root of `namespace :admin` and the first link in Administrate's navigation, so the report sits inside the superadmin area with its layout and navigation.

- The ERB view renders one mount point carrying the data, and adds the island's bundle and the Aixle fonts through Administrate's `content_for(:javascript)` and `content_for(:stylesheet)` hooks.
- **The data is the daily rows.** `Usage::TenantReport` sums hours into one row per company per UTC day for the last 400 days, and the browser sums days into weeks, months and custom ranges and compares each with the period before, the way the mock-up does. A period still in progress is compared with the same number of days of the one before.
- **The island renders no Mantine.** `entrypoints/admin_tenant_usage.tsx` mounts React without `MantineProvider` and without Mantine's global CSS, which would restyle Administrate's chrome. It sets the light-scheme `--app-*` tokens from `cssVariablesResolver` on the mount point, so the colors are the theme's own. Administrate styles bare elements, and colors every hovered button with `[type=button]:not(.link):hover`; the CSS module scopes every rule under `.root`, a class above those.
- The code lives in `app/frontend/pages/Admin/TenantUsage/`: the aggregation and comparison in `aggregate.ts`, the table in `TenantUsageReport.tsx`.

| Mock-up column | Here | Note |
| --- | --- | --- |
| Worker hours | Worker hours, and Busy hours beside it | A paying tenant is billed for capacity offered, not used, so both are needed. |
| Min / max workers | The limit's min and max (∞ when unlimited), and Peak workers | The mock-up reads like an autoscaled pool; ours is a configured limit, and the actual concurrency goes beside it. |
| Utilization % | Busy ÷ worker hours | |
| Average / max wait | Admission wait | |
| Successful / failed sessions | `finished` / `failed` | |

## 8. Verification

Model, service and activity tests cover occupancy and peak, waits, agent logins, outcomes, limits, every billing class, idempotency and the closed-hours rule. The workflow is run through the time-skipping test server. A request test covers the admin page and the recompute trigger. Vitest covers the period and comparison arithmetic and the table's behavior.

On a local stack seeded with nine companies, one per class the hosted product can have, and seven weeks of queued sessions run through the real meter and the real rollup, the page was checked in a browser by day, week, month and sort.

## 9. Not in this change

1. **Active people.** Adoption beyond sessions needs a record of who used the product on which day. Sessions cannot stand in for it: a run a schedule or a webhook started carries its trigger owner's `user_id` with nobody present, and `workflow_runs` does not record what started a run. The cheap way to record it is a `(user_id, company_id, day)` row written from the existing five-minute `UserSession#touch_if_stale!`, at most one write per person per company per day.
2. **Who changed a worker limit.** `company_capacity_changes` records when and the new value, but no actor and no source. Adding `actor_id`, `impersonator_id` and `source`, filled from `Current`, would make the history answerable.
3. **CSV export** — not needed while the page is live in the admin.
4. **Agent mix.** Sessions and busy hours by `agent_type` and model, read from `terminal_sessions` for the period.
5. **Starting a recompute with Temporal unreachable** raises a 500 instead of an alert: `TemporalService.start_workflow` rescues `Temporalio::Error`, and a connection failure raises `Temporalio::Internal::Bridge::Error`, which is not one. Catalog syncs behave the same way.
