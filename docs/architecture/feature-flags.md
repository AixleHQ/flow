# Feature flags

A flag is declared in `config/feature_flags.yml` and read with `Feature.enabled?`. Its value
comes from the first layer that is set:

```
ENV (FEATURE_<KEY>, or the flag's own env: variable) > company override > global value > declared default
```

`Feature.explain` returns the value with the layer that decided it and the ENV variable that
locks it (`FeatureFlags::Resolution`).

Flags are platform-only. Super admins change them on `/admin/feature_flags`, and every change
goes through `FeatureFlags::Admin` with a required reason and one `Audit` row. Company admins
never see them.

## Declaring a flag

Add an entry to `config/feature_flags.yml`; the header of that file lists every attribute. A
release flag ships with `default: false`, an `owner` and a `remove_by`. An invalid entry fails
boot (`FeatureFlags::Registry`) and `test/config/feature_flags_registry_test.rb`.

```yaml
board_ai_summary:
  description: AI summary panel on the board task drawer.
  owner: "@AixleHQ/board"
  kind: release            # release | ops
  scope: company           # company | global
  default: false
  client: true             # optional: the frontend reads it
  remove_by: 2027-01-31    # required for kind: release
```

A release flag whose `remove_by` has passed gets a "past remove-by" badge on
`/admin/feature_flags`. Nothing fails on a date.

## Reading it

### Ruby

```ruby
if Feature.enabled?(:board_ai_summary, company: current_company)
```

Keep the key a literal symbol: it is the one thing to search for when the flag is removed. An
undeclared key raises `FeatureFlags::UnknownFlag` in development and test; elsewhere it reads as
off and is reported to Sentry once per process.

### Controllers

A controller, or some of its actions, that exists only while a flag is on declares it with
`requires_feature` (`FeatureGated`, included in `ApplicationController`). With the flag off the
action answers `404`.

```ruby
class Web::Company::RunnersController < Web::Company::ApplicationController
  requires_feature :external_runners                  # every action
  requires_feature :runner_tokens, only: %i[rotate]   # some actions; except:, if:, unless: too
end
```

The check is prepended, so it runs ahead of authentication and authorization and a company
without the flag gets the same `404` whatever the user's role. A company-scoped flag is read for
`current_company`; an anonymous request skips it and goes on to the sign-in redirect. A global
flag is read for every request. Use `Feature.enabled?` inside an action only when the flag
changes what the action does rather than whether it exists.

### Frontend

Declare the flag `client: true`; that is the only step. `FeaturesResource` sends every client
flag, as the current company resolves it, in the `features` shared prop, and Typelizer turns its
attributes into the generated `Features` type (`app/frontend/types/generated/Features.ts`).
Commit the regenerated file with the registry change. Read the flag by its camelized key:

```ts
const enabled = useFeatureFlag('boardAiSummary')
```

`useFeatureFlag(name: keyof Features)` does not compile for an undeclared name. Only `client:
true` flags reach the browser, and the server still decides every write.

## Scopes

- **`company`**: the call passes `company:`. `nil` is legal (no company context) and skips the
  override layer. A super admin can set an override per company.
- **`global`**: the call passes no `company:`. There are no overrides.

Either mistake raises `ArgumentError`. `FeatureFlags::UNSET` is what tells a forgotten
`company:` apart from `company: nil`.

## Runtime values

One `feature_flags` row per flag holds the global value (`NULL` is "use the default"), and
`feature_flag_overrides` holds the per-company exceptions. A row is created the first time an
admin changes the flag.

`FeatureFlags.snapshot` reads all of them through `Rails.cache` (the shared Redis) with a
10-second TTL, and memoises the result in `Current` for the rest of the request or job, so one
unit of work gets one answer per flag. Outside an executor run (Temporal activities) nothing is
memoised. An admin write deletes the cache key once its transaction commits
(`FeatureFlags.changed!`), so every process sees the change on its next request; the TTL only
covers a delete that never reached Redis. With Redis down, the cache store reads the database.

Rollout, from `/admin/feature_flags` with no deploy: an override on for our own company, then
for pilot companies, then global on. "Turn off everywhere" sets global off and removes every
override in one write; the removed overrides are kept in its audit.

## Setting a flag through ENV

Both ways lock the flag in every process, over every override and admin value. They are read
once at boot (`FeatureFlags::EnvSource`, from `Settings.feature_flags.env`), so a change needs a
restart, and the admin pages show the flag as locked by that variable and refuse writes to it
(`FeatureFlags::EnvLocked`).

- **`FEATURE_<KEY>`**, the key upper-cased (`FEATURE_BOARD_AI_SUMMARY`), works for every flag.
- **The flag's own variable**, declared as `env:` (`coder_reap` has `env: CODER_REAP_ENABLED`).
  No two flags may claim the same one, and it may not be a `FEATURE_*` name. When both are set,
  `FEATURE_<KEY>` wins.

Both take `on`/`true`/`1` or `off`/`false`/`0`, case-insensitive; empty is unset. Any other
value fails boot naming the variable. A `FEATURE_*` variable no flag declares is reported once
at boot and otherwise ignored, so removing a flag never needs an infra change first.

`config/settings.yml` collects the `FEATURE_*` variables and the variables flags declare as
`env:` (it reads their names from `config/feature_flags.yml`), so app code never reads `ENV`.
See [reference/configuration.md](../reference/configuration.md).

## Testing

`test/support/feature_flags_helper.rb` is included in every test case.

```ruby
with_feature(:external_runners, true) { ... }                                # global value
with_feature(:external_runners, false, company: company) { ... }             # one override
stub_feature_env(:coder_reap, "off") { ... }                                 # FEATURE_CODER_REAP
stub_feature_env(:coder_reap, "off", variable: "CODER_REAP_ENABLED") { ... } # the flag's env:
```

- **Values are rows.** `with_feature` writes the row inside the test's transaction, which rolls
  back on its own, and clears the `Current` memo. The test cache is a null store, so every read
  goes to the database.
- **Facade-level and web tests use the real flags.** Both scopes are among them:
  `external_runners` is company-scoped, `coder_reap` is global and has its own `env:` variable.
- **ENV locks are simulated with `stub_feature_env`.** It goes through `FeatureFlags.with(env:)`,
  the one test seam: fiber-local, undone when the block ends. `config/settings/test.yml` keeps
  the real environment's variables out of the suite.
- **Tests of the flag machinery itself** (`Registry`, `EnvSource`, `Resolver`, `Overview`) build
  their own objects with an in-memory registry passed to the constructor. Composition is tested
  through `FeatureFlags.compose`, which validates and returns the parts without installing them.

On the frontend, set `inertiaState.pageProps = { features: { externalRunners: true } }` in a
Vitest test.

## Removing a flag

In one PR, owned by the flag's owner:

1. Delete the losing branch of every `Feature.enabled?(:key` and `useFeatureFlag` check, and
   every `requires_feature :key`.
2. Delete the entry from `config/feature_flags.yml`. For a client flag, regenerate the Typelizer
   types; `tsc` then points at any `useFeatureFlag` check left behind, and a leftover Ruby check
   raises `UnknownFlag` in the tests.
3. Remove its `FEATURE_<KEY>` (or `env:` variable) from the environments when convenient.

The flag's rows can stay: nothing reads a key that is no longer declared. Delete them with a
migration in the same PR if you prefer.
