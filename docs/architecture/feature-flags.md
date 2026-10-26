# Feature flags

How to add a platform feature flag, roll it out and remove it. The design and the
alternatives it was chosen over are in the
[research report](../research/technical-feature-flags-system-design-research-2026-10-21.md);
this guide describes what the code does now.

A flag is declared in `config/feature_flags.yml` and read with `Feature.enabled?`. Its value
comes from the first layer that is set:

```
FEATURE_<KEY> or legacy env_setting (ENV) > company override > global admin value > declared default
```

`Feature.explain` returns the value with the layer that decided it and the layers it beat
(`FeatureFlags::Resolution`). The admin page `/admin/feature_flags` shows the same thing for
every declared flag.

## Ownership

Flags are platform-only. Only super admins see `/admin/feature_flags` and the overrides panel
on a company's admin page, and every change goes through `FeatureFlags::Admin` with a required
reason and an `Audit` row. Company admins never manage flags: a flag is how the platform
exposes unfinished or risky work, not a customer setting.

## Adding a flag

In one PR:

1. Declare it in `config/feature_flags.yml`. The header of that file lists every attribute.
   A release flag ships with `default: false`, an `owner` and a `remove_by` about eight weeks
   out. An invalid entry fails boot (`FeatureFlags::Registry`) and
   `test/config/feature_flags_registry_test.rb`.

   ```yaml
   board_ai_summary:
     description: AI summary panel on the board task drawer.
     owner: "@AixleHQ/board"
     kind: release
     scope: company
     default: false
     remove_by: 2027-01-31
   ```

2. Guard the new code with the flag. A company-scoped flag needs `company:` (nil is legal and
   skips the override layer); a global flag refuses it. Both mistakes raise `ArgumentError`.

   ```ruby
   if Feature.enabled?(:board_ai_summary, company: current_company)
   ```

   Keep the call in this shape, with the key as a literal symbol: it is what the registry test
   finds, and the one thing to search for when the flag is removed.
3. Test both branches with the helpers below.

The flag ships off everywhere.

### Adding a flag the frontend reads

`client: true` takes two steps, not one:

1. Add `client: true` to the flag in `config/feature_flags.yml`.
2. Add its camelized name to `FeatureFlagName` in `app/frontend/shared/ui/types.ts`, next to
   `AgentType` and `UserRole` (`board_ai_summary` becomes `'boardAiSummary'`).

`test/config/feature_flag_name_test.rb` fails until both match, and its message names the
literals it expects. Then read it with `useFeatureFlag('boardAiSummary')`
(`app/frontend/shared/lib/hooks/useFeatureFlag.ts`); a misspelled name fails `tsc`.

Only `client: true` flags reach the browser: `FeatureFlags.client_payload` builds the
`features` shared prop from them alone, so the name and value of an ops or internal flag never
ship. The frontend only reads the resolved boolean. The server decides every write whatever it
shows.

### When the first client flag exists, prefer a resource

The hand-written `FeatureFlagName` union is a consequence of the registry being empty, not the
preferred design. Once any `client: true` flag is declared, replace it: an Alba resource that
declares the client flags as `typelize :boolean` attributes makes Typelizer generate a
`Features` interface, and `useFeatureFlag(name: keyof Features)` then needs neither the
hand-written list nor `test/config/feature_flag_name_test.rb`, because one class produces both
the payload and the type. That is how `current_user` already works, through
`CurrentUserResource` inside its `InertiaRails.always` block in
`Web::ApplicationController`.

It was not done yet because it could not be: Typelizer 0.14 drops a resource with no attributes
before writing any file (`Typelizer.interfaces` ends in `.reject(&:empty?)`, and
`Interface#empty?` is `meta_fields.empty? && properties.empty?`), and no option changes that.
With no client flag declared, a `FeaturesResource` would generate nothing and `keyof Features`
would not compile. This is a pending step, chosen deliberately. The `types.ts` comment above
`FeatureFlagName`, the failure message of `test/config/feature_flag_name_test.rb` and the
`client:` line of the registry header all point here.

## Rolling it out

From `/admin/feature_flags`, with no deploy. Each step takes a reason and writes an `Audit`:

1. Override on for our own company (dogfood).
2. Overrides on for pilot companies.
3. Global on.
4. Override off for any company that hits a problem.

"Turn off everywhere" sets global off and removes every override in one write; the removed
overrides are kept in its audit so they can be put back.

## ENV: `FEATURE_<KEY>`

`FEATURE_<KEY>` (the key upper-cased, e.g. `FEATURE_BOARD_AI_SUMMARY`) locks a flag on or off
in every process, over every override and admin value. It takes `on`/`true`/`1` or
`off`/`false`/`0`; any other value fails boot naming the variable. It is read once at boot
(`FeatureFlags::EnvSource`, via `Settings.feature_flags.env`), so changing it needs a restart,
and the admin page shows the flag as locked. It is the kill switch for when the database or the
admin page cannot be trusted.

A variable for a key nobody declares is ignored with one warning at boot, so removing a flag
never needs an infra change first. `FEATURE_FLAGS_*` is reserved for the system's own settings
(`FEATURE_FLAGS_REFRESH_INTERVAL`, `FEATURE_FLAGS_MAX_STALENESS`), which is why no key may start
with `flags`. See [reference/configuration.md](../reference/configuration.md).

### Moving a legacy ENV toggle over: `env_setting`

An existing kill switch with its own variable (for example `CODER_REAP_ENABLED`, read into
`Settings.coder.reap_enabled`) becomes a flag without renaming the variable:

```yaml
coder_reap:
  description: Lets the Coder reaper delete dead workspaces.
  owner: "@AixleHQ/platform"
  kind: ops
  scope: global
  default: true
  env_setting: coder.reap_enabled          # the Settings path
  env_setting_variable: CODER_REAP_ENABLED  # what admin names as the lock
```

- The setting is a second ENV lock, at the same precedence as `FEATURE_<KEY>`.
  `FeatureFlags::EnvSource` reads it once at boot from the settings tree.
- `config/settings.yml` must leave the setting null while its variable is unset, and give it
  `true` or `false` once it is set. Only an explicitly set variable locks the flag; with it
  unset, the flag is controlled from `/admin/feature_flags` and falls back to its default.
  The read stays in `settings.yml`, so `docs/reference/configuration.md` keeps its row:

  ```yaml
  reap_enabled: <%= ENV['CODER_REAP_ENABLED'].nil? ? '~' : ENV['CODER_REAP_ENABLED'] == 'true' %>
  ```

- **Both set: `FEATURE_<KEY>` wins.** It is the flag's own lock, so a deployment that sets it
  has moved to it; the legacy variable is ignored while it is set. `Feature.explain` and the
  admin page name the variable that actually decides (`Resolution#env_var`,
  `EnvSource#variable_for`).
- A value that is not `true`, `false` or null, or an `env_setting` path that names no setting,
  fails boot (`FeatureFlags::InvalidEnv`).
- Replace every read of the setting with `Feature.enabled?(:key)`.

## Test helpers

`test/support/feature_flags_helper.rb`, included in every test case. No database, Redis or real
ENV: the suite's store is a `FeatureFlags::MemoryStore`, reset before each test, so every test
starts from the declared defaults.

```ruby
with_feature(:board_ai_summary, true) { ... }                               # global value
with_feature(:board_ai_summary, false, company: companies(:acme)) { ... }   # one override
stub_feature_env(:board_ai_summary, "off") { ... }                          # the FEATURE_* lock
stub_feature_env_setting(:coder_reap, false) { ... }                        # the legacy env_setting lock
with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY) { ... }         # declare test flags
uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY                  # the same, for a class
```

An undeclared key raises `FeatureFlags::UnknownFlag` in development and test, so a test that
guards on a typo fails. Tests that need a flag declare the two examples of
`test/fixtures/files/feature_flags_registry.yml`, so they do not depend on what the shipped
registry declares. Tests of the database-backed store and of `FeatureFlags::Admin` run against real rows with
`FakeFeatureFlagVersionToken` instead of Redis. On the frontend, set
`inertiaState.pageProps = { features: { boardAiSummary: true } }` in a Vitest test.

## Removing a flag

In one PR, owned by the flag's owner:

1. Delete the losing branch of every `Feature.enabled?(:key` (and `useFeatureFlag`) check.
2. Delete the entry from `config/feature_flags.yml` (and, for a client flag, its name from
   `FeatureFlagName`).
3. Remove any `FEATURE_<KEY>` from the environments when convenient; it is ignored meanwhile.

The flag's database rows are left behind. They are inert: the resolver never consults an
undeclared key. `/admin/feature_flags` lists them under "Orphaned rows", where a super admin
deletes one key's rows with a reason. That is the normal way to clean up.

### Where `prune` runs

`bin/rails feature_flags:prune` deletes the rows of every undeclared key, through
`FeatureFlags::Admin.prune`, with one `feature_flag.pruned` `Audit` per key. It is idempotent: a
second run finds nothing.

It is a **manual** step and nothing runs it automatically, on purpose:

- **Old pods.** Run it only once the rollout has replaced every pod running the previous code.
  An old pod may still check the key, and would lose its value.
- **Rollbacks.** Remove a flag, deploy, prune, then roll back: the old code declares the flag
  again, its global value and company overrides are gone, and it silently falls back to its
  declared `default`. For a release flag that was on for pilot companies, that is an incident
  nobody would trace to the cleanup. Container start (`bin/docker-entrypoint`) has this failure
  mode and also runs while old pods still serve; `.github/workflows/release.yml` runs before
  any deploy and has no database.

Skipping it is safe. The step is also listed in
[operations/releasing.md](../operations/releasing.md#after-a-rollout).

## Finding stale flags

- **CI:** `test/config/feature_flags_registry_test.rb` fails when an entry is invalid, when a
  declared flag is not read anywhere in `app/` or `lib/`, and when `Feature.enabled?(:x`,
  `Feature.explain(:x` or `useFeatureFlag('x')` names an undeclared flag (or, for
  `useFeatureFlag`, one not declared `client: true`). Comments and test files do not count as
  reads. It deliberately never fails on dates.
- **`bin/rails feature_flags:audit`** changes nothing and prints four lists: release flags past
  `remove_by`; flags whose value has been the same for every company for 30 days or more (from
  the row's `updated_at`, or `introduced` for a flag with no row), which are candidates for
  removal; orphaned rows; and `FEATURE_*` variables for undeclared keys. Run it in the ops
  review.
- **The admin index** badges the same first two cases (`FeatureFlags::Overview`).

## Adding a new targeting dimension

The design is extensible by construction: `scope` is declared per flag and decides which
keyword a call site must pass, so a new dimension changes no existing flag and no existing call
site. Using a hypothetical `project` dimension:

1. Add `project` to `FeatureFlags::Registry::SCOPES` and a `project_scoped?` predicate on
   `FeatureFlags::Registry::Definition`, next to `company_scoped?` and `global?`.
2. Add a `feature_flag_project_overrides` table with its own foreign key and
   `on_delete: :cascade`, mirroring `feature_flag_overrides` in
   `db/migrate/20261021120000_create_feature_flags.rb`.
3. Add a slice and a reader to `FeatureFlags::Snapshot` (next to `global` and `override`), and
   the extra `SELECT` to `FeatureFlag.load_snapshot`.
4. Add one `add(layers, :project, ...)` line to `FeatureFlags::Resolver#set_layers` at the
   chosen precedence position. `Feature.explain` reports the new layer with no further change,
   because `FeatureFlags::Resolution` already carries `source` and `shadowed`.
5. Add the keyword to `Feature.enabled?` and `Feature.explain`, and extend
   `FeatureFlags::Resolver#check_company_argument!`, which today raises `ArgumentError` for a
   missing or forbidden `company:`.

Three decisions, and why:

- **No polymorphic overrides table** (`subject_type` / `subject_id`). Postgres cannot put a
  foreign key on a polymorphic reference, and `on_delete: :cascade` is what guarantees a
  company's overrides disappear with the company (the tenant-hygiene rule of the report's
  §4.2; `Users::PermanentDeletionService` relies on the same foreign keys). One table per
  dimension keeps that guarantee in the database, not in code that can be forgotten.
- **Percentage of companies needs no schema change.** `feature_flags.rollout_percent` already
  exists and is reserved for it. It is evaluated after company overrides and before the global
  value (resolution step 3 in the report's §3.1 and §4.4), with
  `Zlib.crc32("#{key}:#{company.id}") % 100 < rollout_percent`, which only ever adds companies
  as the percentage rises. With `company: nil` it falls through to global.
- **Per-user targeting is deliberately not supported.** It needs a user at every call site and
  per-user frontend payloads, and in a B2B product two colleagues seeing different features is
  a support question with no good answer. If a real experiment needs it, compare against
  PostHog experiments before growing this system (report §4.4).
