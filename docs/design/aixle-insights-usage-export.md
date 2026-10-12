# Aixle Insights usage export — technical design

**Status:** Proposed. Multitenant model (company ↔ Insights org). Tasks 1 and 5 detailed; 1b and 2–8 outlined.
**Date:** 2026-10-09
**Code baseline:** `7b3c8c7b` (branch `feature/371-llm-calls-view`, rebased on `develop`)
**Audience:** Backend engineers implementing the Flow → Insights export.

## 1. Decision and intended behaviour

Flow pushes the usage of its completed agent sessions to Aixle Insights (`db90-rails`)
over the Insights OTLP/JSON logs collector, so Flow spend appears in Insights dashboards
next to Copilot, Cursor and Claude. Everything is implemented on the Flow side
(`palad-app`).

**Multitenant:** each Flow **company** is linked to its own Insights **organization**,
with its own ingest token. A company admin connects Insights from the integrations list
(the token identifies that company's Insights org). Sharing is additionally opt-in per
project. Insights attributes each event to a user and project by `user_email` +
`project_name`.

Two levels of control:
- **Company level** — the Insights connection (org token). No connection ⇒ nothing is
  sent for that company.
- **Project level** — the opt-in toggle. A connected company still sends only the
  projects that turned sharing on.

### Verified contract (read from `db90-rails`)

- Ingest endpoint: `POST <base_url>/v1/logs`, `Content-Type: application/json`,
  `Authorization: Bearer <INGEST_TOKEN>`. Collector returns `200 {"partialSuccess":{}}`
  on accept — including for an invalid token, so success is not proof of a valid token.
  (`Api::V1::OtelController#logs`.)
- Token is an Insights `OrganizationConnector` of type `otel` (`find_by_ingest_token`,
  SHA256), scoped to the Insights **organization** (`SCOPE_BY_TYPE["otel"] => "org"`).
  So one token = one Insights org. This is exactly the company↔org link Flow needs: a
  per-company token routes that company's events to its own Insights org.
- Tool detection is by `service.name` (`OtelEvents::EventBuilder`). Only
  `ClaudeCodeEventBuilder` reads the Claude shape (`event.name=api_request`,
  `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`,
  `cost_usd`). The codex/cursor/gemini builders expect their own event shapes and do
  **not** read `cost_usd`.
- User/project attribution is asynchronous (`AttributionJob` →
  `Ai::CorrelationService`): `user_email`/`email` → org member (confidence 0.95),
  `project_name` → case-insensitive exact project-name match within that org (ambiguous
  = unmatched). Lookback window is **7 days**. The per-company token selects the org;
  `project_name`/`user_email` still resolve the project/user inside it.

### Decisions

- **D1 — data granularity:** per-call, sourced from `llm_calls` (one `api_request`
  logRecord per `LlmCall`, grouped into one OTLP batch per session).
- **D2 — service.name:** always `claude-code`, with the real agent type carried in a
  separate resource attribute `aixle.agent_type`. Guarantees Insights parses tokens and
  our `cost_usd` through `ClaudeCodeEventBuilder`. Revisit if Insights adds first-class
  agent-type mapping (the builder stays configurable).
- **D3 — project opt-in:** per-project boolean on `projects.settings` (jsonb), surfaced
  in the project settings UI.
- **D4 — token storage (multitenant):** per-company ingest token stored on an
  `Integration` row (provider `aixle_insights`), company-wide (`project_id: nil`),
  encrypted in `credentials` (`integrations_key`). NOT in Settings — it is tenant data,
  one Insights org per company. Connected and removed from the integrations list by a
  company admin, exactly like the company-wide Slack install. See §4 Q1/Q3.
- **D5 — collector URL:** `base_url` (prod/staging collector origin) stays in `Settings`
  per environment — it is deployment infrastructure, not tenant data. The `Integration`
  holds only the company's token. See §4 Q2.
- **D6 — delivery model:** asynchronous — a scheduled Temporal sweep reads the ledger and
  pushes in the background, never on the session's finalize path. See §4 Q4.

## 2. Existing code and required changes

| Existing component | Observed behaviour | Change |
| --- | --- | --- |
| [app/models/integration.rb](../../app/models/integration.rb) | `provider` enum; `encrypted_column :credentials` (`integrations_key`); `belongs_to :company`, optional `:project`; `company_wide`/`visible_for_project` scopes; API-key providers (coder/jira/linear) already live here | Add `aixle_insights` provider + accessors (Task 1b) |
| [app/controllers/web/company/projects/integrations_controller.rb](../../app/controllers/web/company/projects/integrations_controller.rb) | Lists `visible_for_project` (incl. company-wide); `create` dispatches per provider; company-wide rows removable only by a company admin | Add connect/remove for `aixle_insights` (Task 1b) |
| [config/settings.yml](../../config/settings.yml) | `config` gem; `ENV[...]` via ERB; staging mirrors production (`settings_parity_test`) | Add `aixle_insights` block — `base_url`, timeouts, batch_size, global `enabled` (Task 1) |
| [config/settings/staging.yml](../../config/settings/staging.yml), [production.yml](../../config/settings/production.yml) | Only override what differs | Add Insights `base_url` defaults (Task 1) |
| [.env.example](../../.env.example) | Documents every ENV knob | Add `AIXLE_INSIGHTS_*` (Task 1) |
| [app/models/capacity_meter_report.rb](../../app/models/capacity_meter_report.rb) | Ledger pattern: states, replay window, settle methods, scopes | Mirror for `InsightsUsageExport` (Task 5) |
| [db/migrate/20260923100000_create_capacity_metering_tables.rb](../../db/migrate/20260923100000_create_capacity_metering_tables.rb) | Ledger migration shape | Mirror for `insights_usage_exports` (Task 5) |
| [app/models/llm_call.rb](../../app/models/llm_call.rb) | Per-call usage: model, tokens, `total_cents_precise`, `occurred_at`, FK session/run/step | Export source (Task 6) |
| [app/services/slack/client.rb](../../app/services/slack/client.rb) | Faraday bearer-JSON client; per-call token argument | Template for `AixleInsights::Client` — token passed in per company (Task 3) |
| [app/services/billing/capacity_meter.rb](../../app/services/billing/capacity_meter.rb) | Periodic push + ledger replay | Template for `UsageExporter`, grouped by company (Task 6) |
| [app/temporal/schedules.yml](../../app/temporal/schedules.yml), [workflows.yml](../../app/temporal/workflows.yml) | Temporal cron schedules + workflow/activity registry | Add export schedule/workflow/activity (Task 7) |

## 3. Task list

Tasks 1 and 5 are detailed; 1b and 2–8 are summarised (to be detailed before each is
picked up). Suggested start order: Task 1 (Settings) and Task 5 (ledger) — independent
foundations — then Task 1b (company connection), then 3/4/6/7, then 8.

---

### Task 1 — Settings (collector URL, tuning, global switch)

**Objective:** configure the collector origin, timeouts, batch size and a global
on/off switch through `Settings.aixle_insights.*`. The **token is NOT here** (it is
per-company, Task 1b). No behaviour yet.

**Files**
- `config/settings.yml` — add the `aixle_insights` block (no token).
- `config/settings/production.yml`, `config/settings/staging.yml` — `base_url` defaults.
- `.env.example` — document the ENV knobs.
- `test/config/settings_parity_test.rb` — stays green.

**`config/settings.yml` (append near the `otel:` block):**
```yaml
# Aixle Insights (DB90) usage export. Flow pushes completed agent-session usage to the
# Insights OTLP/JSON logs collector so Flow spend shows up next to Copilot/Cursor/Claude.
# Multitenant: each company connects its own Insights org (token lives on an
# Integration row, not here). This block holds only deployment-level config: the
# collector origin (the client appends `/v1/logs`), timeouts, batch size, and a global
# kill switch. `enabled:false` disables the sweep for the whole deployment regardless of
# any company connection.
aixle_insights:
  enabled: <%= ENV['AIXLE_INSIGHTS_ENABLED'] == 'true' %>
  base_url: <%= ENV['AIXLE_INSIGHTS_BASE_URL'] %>
  open_timeout: <%= (ENV['AIXLE_INSIGHTS_OPEN_TIMEOUT'] || 5).to_i %>
  read_timeout: <%= (ENV['AIXLE_INSIGHTS_READ_TIMEOUT'] || 30).to_i %>
  # Sessions sent per sweep, bounding outbound requests per scheduled run.
  batch_size: <%= (ENV['AIXLE_INSIGHTS_BATCH_SIZE'] || 200).to_i %>
```

**`config/settings/production.yml` and `config/settings/staging.yml`:**
```yaml
# production.yml
aixle_insights:
  base_url: <%= ENV['AIXLE_INSIGHTS_BASE_URL'] || 'https://otel.insights.aixle.com:4318' %>

# staging.yml
aixle_insights:
  base_url: <%= ENV['AIXLE_INSIGHTS_BASE_URL'] || 'https://otel-staging.insights.aixle.com:4318' %>
```

**`.env.example` (new block):**
```
# --- Aixle Insights usage export ---
# Push completed agent-session usage to the Aixle Insights OTLP/JSON collector.
# Global switch for the whole deployment; each company still connects its own
# Insights org (token entered in the integrations list, not here).
AIXLE_INSIGHTS_ENABLED=false
# Collector origin (the client appends /v1/logs). Defaults per environment.
AIXLE_INSIGHTS_BASE_URL=
# Optional tuning.
AIXLE_INSIGHTS_OPEN_TIMEOUT=5
AIXLE_INSIGHTS_READ_TIMEOUT=30
AIXLE_INSIGHTS_BATCH_SIZE=200
```

**Tests (TDD)** — decision [2]=b: no dedicated settings test (matches how most Settings
blocks are covered). The only guard is parity:
1. `settings_parity_test` stays green — `aixle_insights.base_url` is present in BOTH
   `production.yml` and `staging.yml` so their key sets still match. (This is why
   `base_url` must appear in both per-env files, not just one.)

**Global switch (decision [1]=a):** `Settings.aixle_insights.enabled` is an independent
deployment-wide kill switch, default `false` everywhere, flipped on in prod/staging via
`AIXLE_INSIGHTS_ENABLED=true`. The Temporal sweep (Task 7) does not start while it is
`false`, regardless of any company connection. Pattern mirrors `temporal.enabled`.

**`required_env.rb` (confirmation 1.5):** NOT added — the feature is optional (a company
may never connect Insights) and `base_url` has per-env defaults, so no boot-time check.

**Demo:** `bin/rails runner 'p Settings.aixle_insights.to_h'` prints the block (no token).

**Verification**
- `bin/rubocop config/`
- `bin/rails test test/config/settings_parity_test.rb`

---

### Task 1b — Per-company Insights connection (Integration provider) — OUTLINE

**Objective:** let a company admin link the company to its Insights org by entering the
org ingest token, stored on an `Integration` row (`provider: aixle_insights`,
company-wide), encrypted. Removable like the company-wide Slack install.

**Sketch**
- `Integration`: add `aixle_insights` to the `provider` enum and to
  `CONNECTABLE_PROVIDERS`; add `insights_ingest_token` reader over
  `credentials_data["ingest_token"]` (never serialized to the browser); predicate
  `aixle_insights?`. The row is company-wide (`project_id: nil`).
- Connect/remove in `Web::Company::Projects::IntegrationsController` (`create` dispatch +
  the existing company-admin gate on company-wide `destroy`); surface a card on
  `Projects/Integrations/IntegrationsPage`. Verify the token on connect with a minimal
  probe (a tiny OTLP batch, or accept-on-save with a note that validity is confirmed on
  first real sweep — the collector returns 200 even for a bad token, so a probe can only
  confirm reachability).
- `IntegrationResource` must not expose the token.
- Helper: `Integration.aixle_insights_for(company)` → the company's active connection or
  nil (the exporter uses this per company).
- Tests: provider enumerized; token encrypted and absent from the resource/props; connect
  persists company-wide; only a company admin can remove; `aixle_insights_for` returns the
  active row.

---

### Task 5 — Export ledger (migration + model)

**Objective:** a per-session ledger recording what was sent to Insights, so a failed push
is replayed on the next sweep rather than lost or double-sent, and a session too old to be
attributed (7-day window) is abandoned. Mirrors `CapacityMeterReport`. No sending yet.

**Files**
- `db/migrate/<ts>_create_insights_usage_exports.rb`
- `db/schema.rb` (regenerated)
- `app/models/insights_usage_export.rb`
- `test/models/insights_usage_export_test.rb`
- `test/factories/insights_usage_exports.rb`

**Migration (mirror `capacity_meter_reports`):**
```ruby
# frozen_string_literal: true

class CreateInsightsUsageExports < ActiveRecord::Migration[8.1]
  def change
    # One row per terminal session we attempt to export to Aixle Insights,
    # claimed before the push and settled after it. Insights attributes an event
    # only within 7 days of its timestamp, so a push that fails has to be
    # replayable within that window rather than lost — and abandoned past it.
    create_table :insights_usage_exports do |t|
      t.references :terminal_session, null: false,
                   foreign_key: { on_delete: :cascade }, index: { unique: true }
      # Denormalized from the session so the ledger stays queryable per company
      # even while diagnosing why a company's events are not arriving (decision
      # [3]=b). nullify (not cascade) — a company is a far heavier object than a
      # session, and losing the audit row with it is not wanted; the session FK
      # already cascades the row away on the common path.
      t.references :company, null: true, foreign_key: { on_delete: :nullify }
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :records_sent, null: false, default: 0
      t.text :error
      t.datetime :exported_at
      t.timestamps

      t.index [ :state, :created_at ]
    end
  end
end
```

Notes:
- Unique index on `terminal_session_id` ⇒ one row per session; the exporter claims via
  `find_or_initialize_by` (idempotency).
- `terminal_session` FK `on_delete: :cascade` — a deleted session takes its export row
  with it (the common cleanup path).
- `company_id` (decision [3]=b) is denormalized from `terminal_session.company` at claim
  time, so the ledger can be filtered by company without a join when diagnosing a
  multitenant routing problem ("why did company X get nothing?"). `on_delete: :nullify`
  so an export row's audit value survives even if the company row is later removed.
  Correctness never reads it — the exporter still resolves the live company from the
  session; it is a diagnostics/index column.
- `records_sent` — how many `LlmCall` logRecords went in the batch (diagnostics).
- No `period_start` (unlike capacity): the replay bound is the session's `finished_at`,
  read via the association in the exporter.
- Target Insights org is NOT stored (decision [4]=a): where an export goes is defined by
  the company's current connection, not recorded per row.

**Model:**
```ruby
# frozen_string_literal: true

class InsightsUsageExport < ApplicationRecord
  STATES = %w[pending exported failed skipped].freeze

  # Insights attributes an event only within 7 days of its timestamp (see
  # Ai::CorrelationService::LOOKBACK in db90-rails). A session whose work ended
  # longer ago than this can never be attributed, so it is abandoned (skipped)
  # rather than retried against a collector that will drop it.
  REPLAY_WINDOW = 7.days

  belongs_to :terminal_session
  # Denormalized diagnostics column (optional — nullified if the company is
  # deleted). Correctness resolves the live company from the session.
  belongs_to :company, optional: true

  validates :state, inclusion: { in: STATES }
  validates :attempts, :records_sent,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :unsent, -> { where(state: %w[pending failed]) }
  scope :for_company, ->(company) { where(company_id: company) }

  def exported!(records_sent)
    update!(state: "exported", records_sent: records_sent, error: nil,
            exported_at: Time.current)
  end

  def failed!(message)
    update!(state: "failed", error: message.to_s.truncate(1000), attempts: attempts + 1)
  end

  def skipped!
    update!(state: "skipped")
  end
end
```

**Factory:**
```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :insights_usage_export do
    terminal_session
    # Mirror the session's company by default, as the exporter will at claim time.
    company { terminal_session&.company }
    state { "pending" }
    attempts { 0 }
    records_sent { 0 }

    trait :exported do
      state { "exported" }
      records_sent { 3 }
      exported_at { Time.current }
    end

    trait :failed do
      state { "failed" }
      error { "collector unavailable" }
      attempts { 1 }
    end

    trait :skipped do
      state { "skipped" }
    end
  end
end
```

**Tests (TDD)**
1. `state` validated against `STATES`.
2. unique index: second row for the same session raises `ActiveRecord::RecordNotUnique`.
3. `exported!(n)` sets state/records_sent/exported_at, clears error.
4. `failed!(msg)` sets state/error (≤1000 chars), increments `attempts`.
5. `skipped!` sets state.
6. `unsent` returns pending+failed only.
7. `REPLAY_WINDOW == 7.days`.
8. `for_company(company)` scopes to rows with that `company_id`; `company` may be nil
   (optional) and the row still saves.

**Demo:** console — create a session, `InsightsUsageExport.create!(...)`, exercise
`exported!/failed!/skipped!`, show `unsent`.

**Verification**
- `bin/rails db:migrate` then `bin/rails db:test:prepare`
- `bin/rubocop app/models/insights_usage_export.rb db/migrate/<ts>_create_insights_usage_exports.rb test/models/insights_usage_export_test.rb test/factories/insights_usage_exports.rb`
- `bin/rails test test/models/insights_usage_export_test.rb`

**Dependency note:** Task 6 assumes `llm_calls` is populated at runtime. The branch's
`TerminalSession#materialize_llm_calls` calls an undefined `reload_usage_statistic` under
a `rescue StandardError`; model tests pass (they call the method directly), but confirm
rows appear at runtime before relying on per-call export.

---

### Task 2 — Project opt-in (outline)

`projects.settings` (jsonb) reader/writer on `Project` (`insights_sharing_enabled?` +
setter), strong params + prop in `Web::Company::Projects::SettingsController`, React
toggle in `Projects/Settings/SettingsPage`. Admin gating via `SettingsPolicy` if wanted.
Note: the toggle is meaningful only when the company has an Insights connection (Task 1b);
the UI may show it disabled with a hint otherwise. Tests: model reader/writer, controller
permits + persists, policy.

### Task 3 — Faraday client (outline)

`AixleInsights::Client` (template: `Slack::Client`): `POST <base_url>/v1/logs`,
`Authorization: Bearer <token>` where **token is a per-call argument** (the company's
token from Task 1b), base_url from `Settings.aixle_insights.base_url`, timeouts from
Settings, retry. Treats `200 {"partialSuccess":{}}` as accepted; logs non-2xx. Tests:
WebMock asserts header/body/path and response parsing.

### Task 4 — OTLP builder (outline)

`AixleInsights::OtlpLogsBuilder`: session + its `llm_calls` → `resourceLogs`. Resource
attrs once per batch: `service.name=claude-code`, `user_email`, `project_name`,
`aixle.agent_type`. One `api_request` logRecord per `LlmCall`: `model`, `input_tokens`,
`output_tokens`, `cache_read_tokens`, `cache_creation_tokens` (= `cache_write_tokens`),
`cost_usd` (= `total_cents_precise`/100), `timeUnixNano` (from `occurred_at`),
`session.id`. Guards nil user/project. Tests: payload shape from a 2-call session.

### Task 6 — Exporter service (outline)

`AixleInsights::UsageExporter` (template: `Billing::CapacityMeter`): select terminal
(`finished`/`failed`/`cancelled`) `agent_session`s whose project has opt-in on, with
usage, `finished_at` within 7 days, not yet `exported`. **Group candidates by company**;
for each company resolve its Insights connection (`Integration.aixle_insights_for`) and
token — a company with no connection is skipped entirely. In batches of
`Settings.aixle_insights.batch_size`, build via Task 4, send via Task 3 with that
company's token, record in the Task 5 ledger. Replay `unsent`; `skipped!` past the 7-day
window. Idempotent. Tests: success→exported, no double-send, fail→failed→replay,
>7d→skipped, project opt-off→nothing, company without connection→nothing.

### Task 7 — Temporal workflow/activity/schedule (outline)

`Workflows::InsightsUsageExportWorkflow` (overlap: skip) → activity → `UsageExporter`;
register in `workflows.yml` and `schedules.yml` (e.g. `*/15 * * * *`), gated on
`Settings.aixle_insights.enabled`. Tests: workflow runs the activity, returns a summary
(template: `capacity_metering_workflow_test`).

### Task 8 — Staging verification (outline)

Connect a staging company to a staging Insights org (its token), send a real batch to
`otel-staging.insights.aixle.com:4318/v1/logs`; confirm the event appears in that org and
is attributed to the user/project within an hour. Validates D1/D2 and the per-company
routing on the live collector before production.

## 4. Questions and answers

### Q1 — Is there one Insights key for Flow, and is it deployment-wide?

No — **multitenant**: one key per Flow **company**, each pointing at that company's own
Insights **organization**. On the Insights side the ingest token is an
`OrganizationConnector` of type `otel`, org-scoped (`SCOPE_BY_TYPE["otel"] => "org"`), so
a token *is* an org selector. Flow therefore stores the token **per company**, on an
`Integration` row (`provider: aixle_insights`, `project_id: nil`), encrypted in
`credentials` — not in `Settings` and not shared across companies (decision D4). A
company with no such connection sends nothing.

Inside a company's org, projects and users are still resolved by `project_name` /
`user_email` (`Ai::ProjectCorrelationService`, `Ai::CorrelationService`). The token picks
the org; names/emails resolve the rest. Caveats to validate on staging (Task 8): a project
whose name has no active match in that org stays unattributed; duplicate project names in
the org are ambiguous → unattributed.

### Q2 — Where does the collector URL live, given per-company keys?

In `Settings` per environment (decision D5). The collector origin (prod vs staging) is
deployment infrastructure shared by every company, not tenant data. The `Integration` row
holds only the company's token. If a future need arises for companies on different Insights
instances, a per-connection base_url can be added then; not now.

### Q3 — Who configures the connection?

A **company admin**, from the integrations list (decision D4/§1). The Insights connection
is company-wide (`project_id: nil`), shown on the project integrations page like the
company-wide Slack install, and — per the existing controller rule — removable only by a
company admin. The project opt-in toggle (Task 2) is the separate, per-project control.

### Q4 — Asynchronous or synchronous export?

Asynchronous (decision D6). Sessions are not pushed on their finalize path
(`on_finished`/`on_failed`/`on_cancelled` stay cheap). A scheduled Temporal sweep (Task 7,
`overlap: skip`, ~15 min) reads candidates and the ledger and pushes in the background —
the `capacity_metering` pattern. Insights itself attributes within an hour, so end-to-end
real-time is neither needed nor possible. Reliability is the ledger (replay `failed`
within 7 days; `skipped` past it), not inline execution. The latency cost (a sweep
interval plus up to an hour of attribution) is acceptable for a usage/cost feed.

## 5. Decisions

### Resolved
- **D1 granularity** — per-call from `llm_calls`.
- **D2 service.name** — `claude-code` for all agents, real type in `aixle.agent_type`.
- **D3 project opt-in** — per-project boolean on `projects.settings`, React toggle.
- **D4 token storage** — per-company, on an `aixle_insights` `Integration` row (encrypted).
- **D5 collector URL** — in `Settings` per environment; token not in Settings.
- **D6 delivery** — asynchronous Temporal sweep + ledger replay.
- **[1] global `enabled`** — independent deployment-wide kill switch, default `false`
  (Task 1).
- **[2] settings test** — none; parity test only (Task 1).
- **[3] ledger `company_id`** — denormalized column, nullify on company delete (Task 5).
- **[4] target org in ledger** — not stored; defined by the company's current connection.
- **1.5 required_env** — no boot-time check (feature optional, `base_url` has defaults).
- **5.4 7-day window** — `REPLAY_WINDOW = 7.days` mirrors `Ai::CorrelationService::LOOKBACK`
  by hand (cross-repo; a comment records the dependency, a test pins the constant).

### Still open (needed before the owning task)
- **Admin-only project opt-in?** — whether the project toggle is company-admin gated
  (the company connection already is). Decide in Task 2.
- **Token verification on connect** — probe reachability vs accept-on-save (collector
  returns 200 even for a bad token). Decide in Task 1b.
- **`reload_usage_statistic`** — confirm `llm_calls` populates at runtime before Task 6.
