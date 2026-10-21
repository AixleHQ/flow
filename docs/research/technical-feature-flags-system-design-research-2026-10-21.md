# Feature flags: ENV, admin toggle and per-company overrides in one small in-house system

**Status:** research spike (board task #164), no implementation
**Date:** 2026-10-21
**Scope:** how platform feature flags are declared, stored, resolved, shown in the admin panel
and sent to the frontend. Flags have three sources: ENV, a global admin toggle and a
per-company override.
**Related:** `ARCHITECTURE.md` (tenancy through `Company`), `docs/reference/configuration.md`
(the ENV surface), `docs/user-guide/configuration.md` (Config Items, which are not flags, see §9.3)

---

## Summary

- **Recommendation: build it in-house, small, on top of what the app already runs.**
  - Flags are declared in code, in `config/feature_flags.yml`.
  - Runtime values live in two Postgres tables: one global row per flag, and one override row
    per company.
  - Every process (Puma, Solid Queue, Temporal worker) holds an in-memory snapshot of those
    tables. A version token in Redis tells it when to reload.
  - ENV is read through `config/settings.yml` like every other knob.
  - The admin screen is a custom page in the existing Administrate admin, writing `Audit` rows.
  - Estimate: about 400–600 lines of Ruby, plus a page and a hook.
- **Precedence: ENV > company override > global admin value > declared default.** ENV is an
  operator lock and wins everywhere. The admin panel shows the flag as locked when ENV sets it.
  Of the two runtime layers, the more specific one (the company) wins. A flag that is set
  nowhere resolves to the `default` its declaration must state. There is no implicit `false`.
- **A flag check costs no I/O on the hot path.** A check is a hash lookup in a frozen snapshot.
  Each process does at most one Redis `GET` every 5 seconds. When the token changes, it runs two
  small `SELECT`s. A change reaches every process within about 5 seconds. If Redis is down,
  the change still arrives within 60 seconds.
- **Why not Flipper, Unleash, a SaaS, or OpenFeature?**
  - **Flipper** comes closest. But its gates only add up: any open gate enables the feature.
    So "on for everyone except company 42" is not a plain gate. It also has no ENV layer, and
    audit history is part of the paid Flipper Cloud.
  - **Unleash and the SaaS products** (LaunchDarkly, PostHog) put a second service, or a
    third-party dependency, into every self-hosted and AWS Marketplace deployment.
  - **OpenFeature** is an API, not a store. Its Ruby SDK is still 0.x.
  - The facade proposed here keeps the shape an OpenFeature provider would need, so we can
    adopt it later.
- **Targeting:** company-level only for now. A percentage rollout over companies has a reserved
  slot in the precedence order and one nullable column (§4.4). Per-user targeting is not
  designed for.
- **Effort:** about 8–10 developer-days across 7 tasks (§10).

---

## 1. Constraints from this codebase

These facts decide most of the design. Paths are relative to the repository root.

| Fact | Where | Consequence |
|---|---|---|
| The tenant is `Company`. Membership role is `employee \| admin \| viewer`. Platform staff are `users.super_admin`. | `app/models/company_membership.rb:37`, `app/models/user.rb` | Per-organization means per-`Company`. Only super admins reach `/admin`. |
| `current_company` is a controller helper, memoized in an ivar. Super admins have no membership, so for them it is `nil`. | `app/controllers/concerns/auth_concern.rb:133-137` | The call site passes the company explicitly. `company: nil` must be a legal input. |
| Jobs and Temporal activities carry record ids, not tenant context. `Current` holds only `user_session`. | `app/jobs/application_job.rb`, `app/temporal/temporal_input.rb`, `app/models/current.rb` | Background code must pass `company:` itself. There is no ambient tenant to read. |
| `app/**` may not read `ENV`. `config/settings.yml` is the reader. Every variable needs a row in `docs/reference/configuration.md`. | `.rubocop/cops/configuration/no_env_in_app.rb`, `test/config/configuration_reference_test.rb` | The ENV layer goes through `Settings`, like everything else. |
| `Rails.cache` is Redis in development and production (`expires_in: 1.day`) and `:null_store` in test. | `config/environments/{development,production,test}.rb` | Flag values must not live only in `Rails.cache`. Tests must not depend on the cache. |
| `Audit` rows are written explicitly where an admin action happens. Nothing is audited by callback. | `app/models/audit.rb`, `app/controllers/admin/users_controller.rb:95` | Flag changes write `Audit.create!` with `user: true_user` from the admin controller. |
| Inertia shared props are built in `Web::ApplicationController`. A prop transformer camelizes all keys. | `app/controllers/web/application_controller.rb:21`, `config/initializers/inertia.rb` | The frontend gets a `features` prop. `board_ai_summary` arrives as `boardAiSummary`. |
| Hooks such as `useCanWrite` read shared props. | `app/frontend/shared/lib/hooks/useCanWrite.ts` | `useFeatureFlag` follows the same pattern. |
| The product ships `self_hosted`, `saas` and `aws_marketplace` deployments. | `app/services/deployment.rb` | Whatever we pick must run inside a customer's install with nothing new to operate. |
| There is no flag library today. About ten ENV booleans in `config/settings.yml` act as on/off switches. | `config/settings.yml:162, 189, 209, 303, 459, 484, 665, 689` | We have candidates to move over (§9.2). Most of them should stay settings. |

---

## 2. Build vs buy

### 2.1 Candidates

**In-house (recommended).**
- Pros:
  - The three sources map directly onto ENV, a table and a table.
  - Per-company "off" is a plain row.
  - Self-hosting costs nothing new.
  - Audit and permissions reuse `Audit` and the admin gate.
- Cons:
  - We own the code: the registry, resolver, snapshot store, admin page and test helpers.
  - We would build percentage rollout ourselves if we ever need it (about 1 day, §4.4).

**[Flipper](https://github.com/flippercloud/flipper)** (`flipper`, `flipper-active_record` and
`flipper-ui`, MIT, 1.4.2 on RubyGems as of 2026-05).
- Pros:
  - It is mature and Rails-native.
  - It has gates for boolean, actor, group, percentage of actors and percentage of time.
  - It has cache adapters (`ActiveSupportCacheStore`, `RedisCache`).
  - Its memoizer middleware preloads all features once per request
    ([Flipper optimization docs](https://www.flippercloud.io/docs/optimization)).
- It does not fit our requirements in these ways:
  - **Gates only add up.** A feature is on for an actor if any gate opens it. "Globally on, but
    off for company 42" cannot be expressed with boolean and actor gates. We would need a
    second "deny" feature per flag, or our own wrapper, and that wrapper becomes the resolver
    we would have written anyway.
  - **No ENV source.** We would wrap it again.
  - **Features are created by name on first use.** A typo in `Flipper.enabled?(:new_bord)`
    quietly creates a feature that is off. There is no declared registry with an owner and a
    description.
  - **The UI does not match ours.** `flipper-ui` is a separate Rack app with its own look. It
    needs its own auth wiring under `/admin`. It cannot show our ENV lock or company names
    without customizing it.
  - **Audit and rollback are Flipper Cloud features**, the paid hosted product. The open-source
    UI does not keep history.
  - **The default read is one adapter query per request**, through preload. Avoiding it means
    adding a cache adapter, which brings its own invalidation questions.
- Verdict: Flipper would give us storage and percentage gates. It would not give us the
  precedence model, ENV, audit or the admin page we need. Those are most of the work.

**[Unleash](https://github.com/Unleash/unleash)** (Apache-2.0 core, Ruby SDK `unleash` 6.7.1).
- Pros:
  - A real flag product with strategies, constraints, environments and a UI.
  - The SDK evaluates flags locally from a polled copy, so there is no network call per check
    ([Unleash Ruby SDK](https://docs.getunleash.io/sdks/ruby)).
- Cons:
  - It is a separate Node service with its own Postgres. Every self-hosted and AWS Marketplace
    install would have to run it. Making it optional means two code paths.
  - The open-source edition limits projects and environments. SSO, RBAC and change requests are
    Enterprise features, listed at $75/seat/month
    ([pricing](https://www.getunleash.io/pricing)).
  - A per-company override becomes a constraint list on `companyId` in the Unleash UI. It does
    not live next to the company in our admin, and its audit is Unleash's, not ours.
- Verdict: too much new infrastructure for three sources and one targeting dimension.

**LaunchDarkly / PostHog (SaaS).**
- Pros:
  - The richest targeting and experimentation.
  - Hosted.
- Cons:
  - A third party sits on the configuration path of a product we also ship self-hosted. Customer
    installs cannot depend on our vendor account.
  - Company ids leave our infrastructure.
  - Pricing is per seat or per MAU.
  - It would be the strongest lock-in of all the options.
  - ENV and per-company overrides would still be modelled in the vendor's terms.
- Verdict: rejected for the platform. Nothing in this design stops a team from using PostHog for
  product analytics.

**[OpenFeature](https://openfeature.dev/docs/reference/sdks/server/ruby)**, plus a provider
(`openfeature-sdk` 0.6.5, Apache-2.0).
- Pros:
  - A vendor-neutral evaluation API with hooks and an evaluation context.
  - Providers exist for Unleash, ConfigCat and others.
- Cons:
  - It is not a store and has no UI. Adopting it today still means writing every piece of the
    in-house design and then a provider for it.
  - The Ruby SDK is pre-1.0.
- Verdict: not now. `Feature.enabled?(key, company:)` maps one-to-one onto an OpenFeature boolean
  evaluation with `targeting_key = company.id`. Wrapping the resolver in a provider later is a
  small change, not a migration.

### 2.2 Comparison

| | In-house | Flipper (OSS) | Unleash (OSS) | LaunchDarkly / PostHog | OpenFeature |
|---|---|---|---|---|---|
| ENV source | yes, via `Settings` | wrapper needed | wrapper needed | wrapper needed | wrapper needed |
| Admin toggle at runtime | yes | yes (`flipper-ui`) | yes (own UI) | yes (vendor UI) | n/a, needs a provider |
| Per-company **on** | yes | actor gate | constraint | targeting rule | provider-dependent |
| Per-company **off** while global is on | yes, a row | not with boolean/actor gates | constraint | targeting rule | provider-dependent |
| Admin UI inside our `/admin` | yes | separate Rack app | separate service | external | none |
| Audit of who changed what | our `Audit` | no (paid Cloud) | Unleash's own | vendor's own | none |
| Self-hosted installs | nothing new | gems only | extra service + DB | not possible | n/a |
| Cost | dev time | free | free / $75 per seat | per seat or MAU | free |
| Hot-path read | in-memory, no I/O | 1 query per request (preload) | in-memory | in-memory | provider-dependent |
| Lock-in | none | low | medium | high | none |

---

## 3. Resolution model

### 3.1 Rules

Each flag has a declared **scope**:
- `company`: may differ per company.
- `global`: one value for the whole deployment, such as a maintenance banner or a background
  sweep.

`Feature.enabled?(key, company:)` returns the **first value that is set**, in this order:

1. **ENV.** `FEATURE_<KEY>` is set to a recognized value. It wins over everything, including
   company overrides. Use it as a deliberate lock.
2. **Company override.** The flag is `company`-scoped, the `company:` passed is not `nil`, and a
   `feature_flag_overrides` row exists for this flag and company.
3. **Rollout percentage.** Reserved, not built in v1 (§4.4).
4. **Global admin value.** `feature_flags.enabled` is not `NULL` for this key.
5. **Declared default.** The `default:` from `config/feature_flags.yml`. It is required. The
   registry fails to load without it.

Why this order:

- **ENV first.** ENV is what an operator controls before the app boots and without the database:
  a self-hoster turning off a feature they do not want, a per-environment difference, or an
  incident kill switch that must hold even if someone flips the admin toggle. An ENV value that a
  runtime toggle could override would not be a kill switch. The price is that ENV-locked flags
  cannot be changed at runtime, so the admin page shows them read-only and names the variable.
- **Company before global.** Overrides exist to be exceptions. They are a pilot company on a
  feature that is off for everyone, or a company held back from a rollout that is on for
  everyone. If global won, every override would stop working the moment the global value was
  set, and there would be no point storing them.
- **Default last, and explicit.** The default is the value that applies when the store cannot be
  read (§7.3). Forcing every declaration to state it makes the author choose the safe value. A
  release flag defaults to `false`. An operational switch for something that runs today defaults
  to `true`.

**Emergency off without a redeploy.** Company overrides beat global, so setting global to off
does not switch off companies that were turned on by override. The admin page offers
"Turn off everywhere". It sets global to off and deletes every override for that flag in one
transaction. The previous values are written to the `Audit` row so they can be restored. For a
lock that also holds against admins, use ENV.

### 3.2 Values and inputs

- **ENV values:** `on`, `true` or `1` mean on. `off`, `false` or `0` mean off. Case is ignored
  and surrounding whitespace is trimmed. Unset or empty means not set.
  - Any other value **fails boot** with an error that names the variable. A typo in a kill switch
    is better caught at deploy than silently ignored.
  - ENV is read once at boot. Changing it means a restart, which is how every other setting
    already works.
- **`company:` is a required keyword for `company`-scoped flags.**
  - `company: nil` is legal. It means "no company context": anonymous pages, super admins,
    system sweeps. It skips step 2.
  - Leaving the keyword out raises `ArgumentError`. This catches the "I forgot the tenant" bug at
    the call site.
  - For `global`-scoped flags, passing `company:` raises. A global flag that quietly ignores a
    company would mislead the reader.

### 3.3 A flag unknown to one layer

| Situation | Behaviour |
|---|---|
| Declared, but no DB row and no ENV | The declared default (step 5) |
| DB global row exists with `enabled = NULL` (admin chose "use default") | Skipped, so the declared default applies |
| ENV `FEATURE_X` set, but `x` is not declared (flag removed, or a typo) | Ignored. One warning at boot is logged and sent to Sentry, so stale infra config gets noticed. Boot does not fail, because removing a flag must not need an infra change first. |
| DB rows exist for a key that is not declared | Ignored by the resolver. Listed as **orphaned** in the admin with a delete button. The cleanup task (§5.3) also removes them. |
| A company override exists for a `global`-scoped flag | Cannot be created (model validation). Ignored if one exists from before a scope change. |
| Code calls an undeclared key, e.g. `Feature.enabled?(:board_ai_sumary)` | `FeatureFlags::UnknownFlag` is raised in development and test. In production it returns `false` and reports to Sentry, so a 500 is not the failure mode. A CI test (§5.3) stops this before merge. |

### 3.4 Worked examples

Flag `board_ai_summary`: `scope: company`, `default: false`.

| # | ENV `FEATURE_BOARD_AI_SUMMARY` | Global | Override for company 7 | Override for company 42 | Result for 7 | Result for 42 | Result for 99 | Result for `company: nil` | Deciding layer |
|---|---|---|---|---|---|---|---|---|---|
| 1 | unset | no row | — | — | off | off | off | off | default |
| 2 | unset | on | — | — | on | on | on | on | global |
| 3 | unset | on | — | off | on | **off** | on | on | override for 42 |
| 4 | unset | off | on | — | **on** | off | off | off | override for 7 (pilot) |
| 5 | `off` | on | on | — | **off** | off | off | off | ENV (admin shows "locked by ENV", the override is listed as shadowed) |
| 6 | `on` | no row | — | off | on | **on** | on | on | ENV beats the override for 42 |
| 7 | unset | `NULL` (cleared) | on | — | on | off | off | off | override for 7, default for the others |
| 8 | `maybe` | — | — | — | — | — | — | — | boot fails: `FEATURE_BOARD_AI_SUMMARY must be on/off/true/false/1/0` |

Flag `coder_reap`: `scope: global`, `default: true`, kind `ops`.

| # | ENV | Global | Call | Result |
|---|---|---|---|---|
| 9 | unset | no row | `Feature.enabled?(:coder_reap)` | on (default) |
| 10 | unset | off | `Feature.enabled?(:coder_reap)` | off (an admin paused the reaper at runtime) |
| 11 | unset | — | `Feature.enabled?(:coder_reap, company: c)` | `ArgumentError`: global flag |

---

## 4. Data model

### 4.1 Registry: `config/feature_flags.yml` (code, reviewed in PRs)

```yaml
# Every flag the app may check. Keys are snake_case; the ENV name is FEATURE_<KEY>.
board_ai_summary:
  description: AI summary panel on the board task drawer.
  owner: "@AixleHQ/board"          # GitHub team or handle; CODEOWNERS-style
  kind: release                     # release | ops
  scope: company                    # company | global
  default: false
  client: true                      # shipped to the frontend in the `features` prop
  introduced: 2026-11-03
  remove_by: 2027-01-31             # required for kind: release

coder_reap:
  description: Lets the Coder reaper delete dead workspaces.
  owner: "@AixleHQ/platform"
  kind: ops                         # long-lived operational switch; no remove_by
  scope: global
  default: true
  client: false
  env_setting: coder.reap_enabled   # optional legacy Settings path (§9.2)
```

- **Why YAML in the repo, and not a DB row or Ruby constants.**
  - The list of flags is a property of the code that checks them. It should change in the same
    PR as that code, be reviewed by its owner, and be the same in every environment.
  - DB-declared flags drift between staging and production, and nothing reviews them.
  - YAML over Ruby constants: CI tests, the rake task and the TS generator (§6.2) can read YAML
    without booting Rails.
- `FeatureFlags::Registry` loads the file once at boot, validates it and freezes it.
  - It checks that every key matches `/\A[a-z][a-z0-9_]*\z/`.
  - It checks that `description`, `owner`, `kind`, `scope` and `default` are present.
  - It checks that `remove_by` is present when `kind: release`.
  - Anything invalid fails boot.

**Kinds**
- `release`: temporary. It exists to ship something gradually and must be removed.
- `ops`: a long-lived kill switch or operational toggle.

There is deliberately **no `entitlement` kind**. Plan and billing logic (`Deployment.saas?`,
`Billing::*`) is product logic, not a rollout tool. Putting it behind flags would let a toggle
change what a customer pays for.

### 4.2 Runtime values: two tables

```ruby
create_table :feature_flags do |t|          # one row per declared key that an admin touched
  t.string  :key, null: false, index: { unique: true }
  t.boolean :enabled                        # NULL = "use the declared default"
  t.integer :rollout_percent               # reserved for §4.4; NULL in v1, no UI
  t.references :updated_by, foreign_key: { to_table: :users }
  t.timestamps
end

create_table :feature_flag_overrides do |t|
  t.references :feature_flag, null: false, foreign_key: { on_delete: :cascade }
  t.references :company,      null: false, foreign_key: { on_delete: :cascade }
  t.boolean :enabled, null: false
  t.text    :reason, null: false            # why this company is an exception
  t.references :created_by, foreign_key: { to_table: :users }
  t.timestamps
  t.index %i[feature_flag_id company_id], unique: true
end
```

- **Rows by key, not by id from the registry.** The registry is the source of declared keys. A
  row is created lazily the first time an admin sets a value or adds an override, so a fresh
  install has no rows.
- **Tenant hygiene.**
  - Overrides carry `company_id`.
  - Add `Company has_many :feature_flag_overrides, dependent: :delete_all`.
  - Add a line to `Users::PermanentDeletionService` and the company deletion path.
  - Overrides are never shown outside `/admin`, so no Pundit policy on the company side is needed
    in v1.
- **`reason` is required** on overrides and on every admin change (it goes into the `Audit`
  comment). An override nobody can explain is the hardest kind of flag debt to clean up.

### 4.3 ENV source

`config/settings.yml` stays the only ENV reader. It gets one block:

```yaml
feature_flags:
  # FEATURE_<KEY>=on|off for any declared flag; parsed and validated by FeatureFlags::EnvSource.
  env: <%= ENV.to_h.select { |k, _| k.start_with?('FEATURE_') }.to_json %>
  refresh_interval_seconds: <%= (ENV['FEATURE_FLAGS_REFRESH_INTERVAL'] || 5).to_i %>
  max_staleness_seconds:    <%= (ENV['FEATURE_FLAGS_MAX_STALENESS'] || 60).to_i %>
```

- JSON is valid YAML, so `Settings.feature_flags.env` is a hash that app code can read without
  touching `ENV`. That keeps `Configuration/NoEnvInApp` intact.
- `docs/reference/configuration.md` gets:
  - a row for each of the two refresh settings;
  - one row named `` `FEATURE_<KEY>` `` for the family.
- `ConfigurationReferenceTest` only counts rows whose first cell is a literal uppercase name. So
  the wildcard row passes "every documented variable is read" unchanged.
- `bin/rails docs:sync_config_reference` refreshes the portal copy.
- **The `FEATURE_FLAGS_` prefix is reserved for the system's own settings.** The registry rejects
  any flag key that would map to `FEATURE_FLAGS_*`.

### 4.4 Rollout targeting (assessed, not designed in)

- **Per-company only for v1.**
  - This is a B2B product where the unit of risk, support and billing is the company.
  - If two people in one company see different products, that confuses support. "Why does my
    colleague have the button?" has no good answer.
  - The work that needs gradual exposure today is company-shaped: new integrations, runtimes,
    board features.
- **Percentage of companies** is the only extension worth keeping room for, and it fits without
  a schema change.
  - `feature_flags.rollout_percent` (nullable, reserved above) is evaluated at step 3: after
    company overrides, before global.
  - It is stable per company: `Zlib.crc32("#{key}:#{company.id}") % 100 < rollout_percent`.
    Raising the percentage only ever adds companies.
  - It only applies when a company is given. With `company: nil` it falls through to global.
  - Cost: about one day, including the admin field. Build it when the first flag actually needs
    it.
- **Per-user targeting** is not designed for. It needs a user in every call site, a second
  override table, and frontend payloads keyed by user. Revisit it only for a real experiment,
  and at that point compare against PostHog experiments rather than growing this system.

---

## 5. Storage, caching and lifecycle

### 5.1 Snapshot store

```
            ┌──────────── per process (Puma worker / Solid Queue / Temporal worker) ────────────┐
check ─────▶│ Current.feature_snapshot (pinned per request/job) ──▶ frozen Snapshot             │
            │                                     ▲                                             │
            │   every ≥5 s: GET feature_flags:version (Redis) ── changed? ──▶ reload: 2 SELECTs  │
            │   every ≥60 s: reload regardless (Redis down, key evicted)                         │
            └────────────────────────────────────────────────────────────────────────────────────┘
admin write ──▶ transaction(update rows + Audit) ──▶ after_commit: SET feature_flags:version <uuid>
```

- **The snapshot** is a frozen
  `{ key => { global: true|false|nil, overrides: { company_id => bool } } }`, built from
  `SELECT key, enabled FROM feature_flags` and
  `SELECT feature_flag_id, company_id, enabled FROM feature_flag_overrides`.
  - Overrides are a few per flag, at most a few hundred in total, so the whole thing is
    kilobytes.
  - The process holds it in a module-level `Concurrent::AtomicReference`. A reload swaps the
    reference. Readers never lock.
- **One answer per request.** The first check in a request or job pins the current snapshot in
  `Current.feature_snapshot`. Rails resets `CurrentAttributes` around every request and every
  ActiveJob execution. So a flag that flips mid-request cannot make one page render half old and
  half new.
- **Hot-path cost.**
  - A check is a hash lookup on a pinned snapshot: no DB query, no Redis call.
  - The freshness check is one Redis `GET` per process every `refresh_interval_seconds` (5 s).
    It runs on whichever request first sees an expired timestamp, not on a timer thread.
  - A reload runs only when the token changed.
  - This meets the task's "no DB query per check" rule, and also avoids Flipper's one query per
    request.
- **Invalidation across processes.**
  - Writers set a new random token in Redis after commit.
  - The token is written with the Redis client directly, through `Settings.redis.url` like Action
    Cable, not through `Rails.cache`. Two reasons:
    - `Rails.cache` defaults to a 1-day expiry, and it is `:null_store` in test.
    - A token that silently expires would hide changes until the max-staleness reload.
  - Propagation: about 5 s normally, at most 60 s (`max_staleness_seconds`) if Redis is down or
    the key was evicted.
- **Rejected: Postgres `LISTEN/NOTIFY`.** It needs a long-lived dedicated connection in every
  process and does not survive a transaction-pooling proxy. Polling a token is simpler, and
  5 seconds is fast enough for flags.
- **Rejected: Action Cable broadcast.** It would push changes to processes immediately. But
  Solid Queue and Temporal workers do not subscribe to cable channels, and the polling path is
  needed anyway for missed messages.

### 5.2 Temporal

- **Workflow code must not read flags.** Temporal replays workflow code, and a flag that changed
  between the original run and the replay makes the history non-deterministic.
- Flags are read in **activities**. If a workflow must branch on a flag, it reads the flag
  through an activity, or receives it in its input when it starts. Then the value is recorded in
  history.
- Open question for implementation: whether activities run inside
  `Rails.application.executor`, which is what makes `Current` reset per activity. If they do
  not, the activity base class (`app/temporal/activities/base.rb`) should wrap execution in it.
  Otherwise, activities should not pin a snapshot.

### 5.3 Lifecycle: introduce → roll out → clean up

1. **Introduce** (one PR):
   - Add the entry to `config/feature_flags.yml`: owner, `remove_by`, `default: false`.
   - Guard the new code with `Feature.enabled?`.
   - Add tests for both branches using the helper (§7.4).
   - The flag ships off everywhere.
2. **Roll out** (admin panel, no deploys), each step audited with a reason:
   1. Override on for our own company (dogfood).
   2. Overrides on for pilot companies.
   3. Global on.
   4. Overrides off for any company that hits a problem.
3. **Clean up** (one PR, owned by the flag's owner):
   - Delete the losing branch in code and the registry entry.
   - The next deploy's `feature_flags:prune` (run from the release task) deletes that key's rows,
     with an `Audit` row. The admin also lists them as orphaned until then.

Finding stale flags:

- **CI** (`test/config/feature_flags_registry_test.rb`) checks structure and references:
  - **Structure:** every entry is valid (§4.1).
  - **References:** every declared key is referenced somewhere in `app/` or `lib/`. Every key
    referenced through `Feature.enabled?(:x` or `useFeatureFlag("x")` is declared.
  - It deliberately does **not** fail on dates. A test that turns red on a calendar date breaks
    unrelated PRs.
- **`bin/rails feature_flags:audit`** lists:
  - release flags past `remove_by`;
  - flags whose effective value has been the same for every company for more than 30 days (from
    `updated_at`), which are candidates for removal;
  - orphaned rows;
  - ENV variables for undeclared keys.
  Run it in the weekly ops review. Its output can also feed a scheduled CI job that opens an
  issue.
- **Admin index:** a "past remove-by" badge, and a "same everywhere for 30+ days" badge.

---

## 6. API surface

### 6.1 Backend

```ruby
# Company-scoped flag: the company is a required keyword; nil is legal and explicit.
Feature.enabled?(:board_ai_summary, company: current_company)
Feature.enabled?(:board_ai_summary, company: task.board.project.company)   # in a job/activity

# Global flag: no company argument (passing one raises).
Feature.enabled?(:coder_reap)

# For the admin page, logs and debugging: value plus where it came from.
Feature.explain(:board_ai_summary, company: company)
# => #<FeatureFlags::Resolution value=false source=:env env_var="FEATURE_BOARD_AI_SUMMARY"
#      shadowed=[{source: :company, value: true}, {source: :global, value: true}]>
```

- There is only `enabled?`. There is no `disabled?`, and no setter on the read API. Writes go
  through `FeatureFlags::Admin` (`set_global`, `clear_global`, `set_override`,
  `remove_override`, `turn_off_everywhere`), and each of those takes `actor:` and `reason:` and
  writes the `Audit` row.
- Keys are symbols that must be declared (§3.3). There is deliberately no block form like
  `Feature.with(:x) { }`. An `if` is easier to find, and easier to delete at cleanup.
- Structure:
  - `Feature` is a thin facade over `FeatureFlags::Resolver`, which takes a snapshot, the ENV
    source and the registry.
  - The resolver is a pure function of those three, so it can be unit-tested without a database.
  - The facade is the seam where an OpenFeature provider could sit later.

### 6.2 Frontend

- **The bootstrap payload, not an endpoint.** `Web::ApplicationController#inertia_share` adds:

  ```ruby
  features: InertiaRails.always { FeatureFlags.client_payload(company: current_company) }
  # => { board_ai_summary: true, ... }  — only flags declared `client: true`
  ```

  - `InertiaRails.always` re-evaluates the payload on partial reloads, including the
    cable-triggered ones. The page therefore picks up a flip on its next visit or reload, and no
    extra request is needed.
  - Only `client: true` flags are sent. Internal and ops flag names and values do not ship to
    browsers, and that includes anonymous visitors.
  - A per-request endpoint was rejected: it adds a round trip before render and a loading state
    for every guarded component.
  - Live push was rejected for v1. A flag flip does not need to reach an open tab within
    seconds.
- **The hook** is `app/frontend/shared/lib/hooks/useFeatureFlag.ts`, next to `useCanWrite`:

  ```ts
  import { usePage } from '@inertiajs/react';
  import type { SharedProps } from '@/shared/ui/types';
  import type { FeatureFlagName } from '@/types/generated/featureFlags';

  /** Server-resolved flag for the current company. Unknown names are a type error. */
  export function useFeatureFlag(name: FeatureFlagName): boolean {
    return usePage<SharedProps>().props.features?.[name] ?? false;
  }
  ```

  - `DeepKeyCamelizer` camelizes keys, so `board_ai_summary` arrives as `boardAiSummary`.
  - `bin/rails feature_flags:typescript` generates
    `app/frontend/types/generated/featureFlags.ts` (a union of the camelized `client: true`
    keys) into the already-prettier-ignored generated directory.
  - A misspelled flag name in TSX fails `tsc` in `lint_check_all`.
  - `SharedProps` in `app/frontend/shared/ui/types.ts` gains
    `features?: Partial<Record<FeatureFlagName, boolean>>`.
  - The frontend never decides precedence. It only reads the resolved boolean.

---

## 7. Admin UX, safety and operations

### 7.1 Admin panel (functional outline)

These are custom pages under the existing admin. They are not an Administrate dashboard over the
table, because most flags have no row and the page is about effective values. The controller
inherits `Admin::ApplicationController`, so it gets `authenticate_admin!` and the admin layout,
the same way `catalog_syncs` and `session_admission` do.

- **`GET /admin/feature_flags`** has one row per declared flag, with:
  - key, description, owner, kind and scope;
  - the declared default;
  - the ENV value, shown as "locked by `FEATURE_X`" when set;
  - the global value;
  - the number of overrides (on and off counted separately);
  - the effective value for companies without overrides;
  - badges: past remove-by, same everywhere for 30+ days, orphaned rows.
- **`GET /admin/feature_flags/:key`** shows:
  - A source matrix: ENV, global and default, with the winning source highlighted.
  - The global control: on, off, or use default. A reason is required.
  - "Turn off everywhere" (§3.1).
  - The override table: company, value, reason, who added it and when, and remove. Overrides
    shadowed by ENV are marked.
  - "Add override": a company search, on or off, and a reason.
  - A "check a company" box that shows `Feature.explain` for any company.
  - The audit history: `Audit` rows for this flag, newest first.
- **ENV-locked flags** show their controls disabled, with the variable name. An admin cannot
  create the illusion of a change.
- **The company show page** (`/admin/companies/:id`) gets a "Feature overrides" panel listing
  that company's overrides. Support will ask "what is different about this customer?", and this
  panel answers it.

### 7.2 Audit and permissions

- **Audit.** Every write goes through `FeatureFlags::Admin` and inserts an `Audit` row in the
  same transaction:
  - `auditable`: the `FeatureFlag` row, so the history is per flag.
  - `associated`: the company, for overrides.
  - `user`: `true_user`, so the real admin is recorded during impersonation.
  - `action`: one of `feature_flag.global_set`, `feature_flag.global_cleared`,
    `feature_flag.override_set`, `feature_flag.override_removed`,
    `feature_flag.turned_off_everywhere` or `feature_flag.pruned`.
  - `audited_changes`: `{ "enabled" => [old, new] }`. For turn-off-everywhere it also holds the
    removed overrides.
  - `comment`: the reason.
  - The change is also logged with Rails' tagged logger, so it can be found in Loki next to the
    errors it may cause.
- **Permissions.** Only super admins (`users.super_admin`), permanently. That is exactly who
  `/admin` admits today.
- **Product decision:** feature flags are a platform-wide setting. Company admins never manage
  or influence them, including their own company's overrides.
  - Flags are a platform rollout and safety tool. A company admin turning on a half-shipped
    feature, or turning off a kill switch, is a support incident.

### 7.3 When the store is unavailable

- **Fail to the last known value, then to the declared default.** We do not pick fail-open or
  fail-closed globally. Each flag picks, through its `default`.
- **Reload fails** (DB error during a refresh): keep serving the current snapshot, report to
  Sentry, and retry at the next interval. A flag never flips because of an outage.
- **No snapshot at all** (the DB is unreachable when the process first checks a flag): use an
  empty snapshot, so ENV and then the declared defaults apply. Retry at the next interval.
- So a release flag (`default: false`) fails **closed**: the half-shipped feature does not appear
  in an outage. An ops switch for something that runs today (`default: true`) fails **open**:
  the reaper keeps reaping.
- ENV is in memory from boot, so ENV locks hold through any outage.
- **Redis down:** propagation slows to `max_staleness_seconds`. Reads are not affected.

### 7.4 Flags in tests

- **No database, no Redis, no ENV.** In the test environment `FeatureFlags.store` is an in-memory
  store. A module included into `ActiveSupport::TestCase`, `ActionDispatch::IntegrationTest` and
  system tests resets it in `setup`. Every test starts from declared defaults.
- Helpers, in `test/support/feature_flags_helper.rb`:

  ```ruby
  with_feature(:board_ai_summary, true) { ... }                          # global value for the block
  with_feature(:board_ai_summary, false, company: companies(:acme)) { ... }   # one override
  stub_feature_env(:board_ai_summary, "off") { ... }                     # ENV layer, no real ENV
  ```

  - These are app-owned seams, so they are compatible with `Testing/NoVendorStubbing` and
    `Testing/NoAnyInstance`.
  - Minitest parallelizes with processes (`PARALLEL_WORKERS`), so the per-process store does not
    leak across tests that run in parallel.
- The DB-backed store and the admin writes get their own tests against real rows.
  - The version token sits behind a small app-owned interface: `FeatureFlags::VersionToken`,
    with `read` and `bump`. Tests inject an in-memory fake (in `test/support/fakes/`).
  - The reason: `docker-compose.ci.yml` defines no Redis service, and the suite must not need
    one.
- **Frontend:** Vitest renders with `props.features = { boardAiSummary: true }`. Nothing to mock
  beyond the existing `usePage` pattern.
- An unknown key raises in test (§3.3), so a test that guards on a typo fails loudly.

---

## 8. Proposed files (for the implementation tasks)

| Path | What |
|---|---|
| `config/feature_flags.yml` | The registry |
| `config/settings.yml` (+ `docs/reference/configuration.md`, portal copy) | The `feature_flags:` block; `FEATURE_<KEY>`, `FEATURE_FLAGS_REFRESH_INTERVAL`, `FEATURE_FLAGS_MAX_STALENESS` rows |
| `app/models/feature_flag.rb`, `app/models/feature_flag_override.rb` + migration | Runtime values |
| `app/services/feature.rb` | The facade: `enabled?`, `explain` |
| `app/services/feature_flags/{registry,resolver,env_source,snapshot,store,admin,client_payload}.rb` | Core |
| `app/models/current.rb` | `attribute :feature_snapshot` |
| `app/controllers/admin/feature_flags_controller.rb`, `admin/feature_flag_overrides_controller.rb` + views | Admin pages |
| `app/controllers/web/application_controller.rb` | The `features` shared prop |
| `app/frontend/shared/lib/hooks/useFeatureFlag.ts` (+ `.test.ts`), `shared/ui/types.ts` | Frontend |
| `lib/tasks/feature_flags.rake` | `audit`, `prune`, `typescript` |
| `test/support/feature_flags_helper.rb`, `test/config/feature_flags_registry_test.rb`, `test/services/feature_flags/*` | Tests |
| `docs/architecture/feature-flags.md` | How to add, roll out and remove a flag. A living doc, so it is checked by the drift test |

---

## 9. Migration and rollout plan

### 9.1 The first flag

1. Land the infrastructure (tasks 1–5 in §10) with an **empty registry**. The registry and the
   admin page must handle zero flags. Nothing changes in behaviour.
2. The first real flag is a `release` flag for the next user-facing feature in development. It
   is declared in that feature's first PR with `default: false`, an owner and a `remove_by`
   about 8 weeks out.
3. Roll it out as in §5.3:
   - our own company by override;
   - two or three pilot companies;
   - global on;
   - a removal PR before `remove_by`.
   This first lifecycle is the end-to-end test of the system, cleanup included.
4. In parallel, pilot the legacy-ENV path with **one** ops toggle (§9.2), so the `env_setting`
   path is exercised by a real flag.

### 9.2 Existing hardcoded conditionals

A survey of `app/` and `config/settings.yml` found no feature flags in the rollout sense. It
found three groups of switches.

**Leave as settings.** These describe what the deployment *is*, are read at boot, or are a
security posture. Making them runtime toggles would be a regression.
- `Deployment.mode` / `saas?` / `self_serve_signup?` (`app/services/deployment.rb`)
- `REGISTRATION_ENABLED`
- `AUTH_ENABLED_KINDS`
- `CSP_ENFORCE`
- `ENCRYPTION_BIND_PURPOSE`
- `TEMPORAL_ENABLED`
- the billing conditionals (`Billing::Trial`, `Billing::EffectiveCapacity`,
  `HostedBillingOnly`, `can_manage_billing`)
These are entitlement or deployment logic, not flags (§4.1).

**Candidates for `kind: ops, scope: global` flags.** These are runtime kill switches that today
need a restart to flip:
- `CODER_REAP_ENABLED` (`Settings.coder.reap_enabled`)
- `CODER_HEALTH_PROBE_ENABLED`
- `SESSION_PINNED_RELEASE_ENABLED`
- possibly `AZURE_DEVOPS_PAT_MODE_ENABLED`

How each one moves over, as its own task:
- Declare it with `env_setting: <settings path>` and the same default.
- The resolver treats the setting as the ENV layer for that flag, with the same precedence as
  `FEATURE_<KEY>`. So existing deployments keep their variable, and the ENV read stays in
  `settings.yml` unchanged (the configuration-reference test is unaffected).
- Replace `Settings.coder.reap_enabled` at the call sites with `Feature.enabled?(:coder_reap)`.
- What changes: an admin can now pause the reaper at runtime when the variable is unset.
- Suggested pilot: `coder_reap`. It is read in one place, defaults to `true`, and an operator
  wanting to pause it during an incident is the exact use case.

### 9.3 Config Items are not flags

Config Items (`app/models/config_item.rb`) are project-scoped variables and
secrets injected into agent sessions. They are configuration for the customer's agents, not
switches for our app, and they must not become the flag store.
- `docs/user-guide/configuration.md:47-48` (and its portal copy) says "feature flag → Config
  Items" and "(project or company)". The model only allows `Project`.
- The follow-up should reword that row to "a value your agents read, e.g. a URL or a flag in
  your code", fix the scope, and link the new flags guide for platform admins. That avoids two
  meanings of "feature flag" in our docs.

---

## 10. Implementation breakdown

Sizes: S ≈ 1 day, M ≈ 2–3 days. Tasks 1→2→3 are sequential. Tasks 4 and 5 can start after 1.

| # | Task | Size | Depends on |
|---|---|---|---|
| 1 | **Registry, resolver, facade.** `config/feature_flags.yml` with an empty registry and schema validation; `FeatureFlags::Registry`, `EnvSource` (the settings block, value parsing, boot failure on bad values, warning on undeclared keys), `Resolver` (precedence, scope/`company:` rules, `UnknownFlag`), `Feature.enabled?` / `explain`; the test helper and in-memory test store; unit tests for every row of §3.3–3.4; configuration reference rows | M | — |
| 2 | **Storage and snapshot.** Migration and models with validations; `Company` association and deletion paths; `Snapshot`, `Store` with the `VersionToken` (Redis, plus an in-memory fake for tests), refresh and max-staleness, last-good fallback; `Current.feature_snapshot` pinning; Temporal activity executor check (§5.2); tests against real rows | M | 1 |
| 3 | **Admin pages and writes.** `FeatureFlags::Admin` (set/clear global, add/remove override, turn off everywhere) with `Audit` in the same transaction; the index and show pages from §7.1; the overrides panel on the company show page; controller tests for super admin only and for ENV-locked controls being disabled | M | 2 |
| 4 | **Frontend payload.** The `features` shared prop with `client: true` only; the `feature_flags:typescript` generator wired into the existing type generation; `useFeatureFlag` + Vitest; the `SharedProps` type | S | 1 |
| 5 | **Lifecycle tooling and docs.** The registry CI test (structure, declared ↔ referenced), `feature_flags:audit` and `feature_flags:prune` (called from the release task), the "Feature flags" developer guide (add, roll out, remove), indexed in `docs/index.md` | S | 1 |
| 6 | **Pilot ops flag.** The `env_setting` support in `EnvSource`; move `coder_reap` over; update the Coder guide and portal copy to say it can also be paused from `/admin/feature_flags` | S | 2, 3 |
| 7 | **Docs fix.** Reword the Config Items "feature flag" row in `docs/user-guide/configuration.md` and its portal copy (§9.3) | XS | 5 |

**Total:** about 8–10 developer-days.

**Deferred, not sized into the total:**
- percentage-of-companies rollout, about 1 day (§4.4);
- an OpenFeature provider wrapper, about 1 day (§2.1).

---

## 11. Open questions for implementation

- Do Temporal activities run inside `Rails.application.executor`? This decides whether
  `Current.feature_snapshot` resets per activity (§5.2). Check `app/temporal/activities/base.rb`
  and the worker boot.
- Where should `feature_flags:prune` run? The release task, or a post-deploy step in the deploy
  pipeline? It must run after the new code is live, never before. While old pods are still
  serving, they may still check the key.
- Should the frontend payload be included for anonymous pages (`company: nil`)? The proposal
  says yes, with `client: true` flags only. If no anonymous page needs a flag, leave it out until
  one does.

---

## Sources

- [Flipper on GitHub](https://github.com/flippercloud/flipper): gates, the UI, and audit history
  as a Flipper Cloud feature
- [Flipper optimization docs](https://www.flippercloud.io/docs/optimization): per-request
  preload and memoization, and the cache adapters
- [Flipper self-hosted (Cloudless) guide](https://www.flippercloud.io/docs/get-started/self-hosted):
  `flipper-ui` as the open-source UI
- [OpenFeature Ruby SDK](https://openfeature.dev/docs/reference/sdks/server/ruby) and
  [provider concept](https://openfeature.dev/docs/reference/concepts/provider/)
- [Unleash Ruby SDK](https://docs.getunleash.io/sdks/ruby), [Unleash pricing](https://www.getunleash.io/pricing)
- RubyGems API, read on 2026-10-21, for versions and licenses: `flipper` 1.4.2 MIT,
  `openfeature-sdk` 0.6.5 Apache-2.0, `unleash` 6.7.1 Apache-2.0

Third-party content was paraphrased for compliance with licensing restrictions.
