# Cloud-Provider Auth for Agent CLIs (AWS Bedrock first)

**Date:** 2026-07-25
**Status:** shipped on `feature/bedrock-cloud-provider-auth` and exercised end to end against
a live Identity Center instance (device flow → vended credentials → a Bedrock session that
answered). **Identity Center is the only connect path.** The cross-account role and the
LLM-gateway paths were built, reviewed and then deliberately removed — see §3.
**Research pair:** `docs/planning-artifacts/research/technical-aws-bedrock-agentic-cli-integration-research-2026-07-24.md`
**Supersedes:** the "Bedrock / Vertex — deferred (not modeled)" section of `docs/design/oauth-implementation.md` (§9)

---

## 1. What this document settles

The platform runs Claude Code inside an ephemeral agent container. A user who wants their
token spend billed to their **own** cloud account picks `3rd-party platform → Amazon Bedrock`
inside Claude Code's **native** login wizard — a UI we do not control and deliberately do not
replace (the same doctrine already applies to subscription vs API-key login, see
`oauth-implementation.md` §9).

This document answers: **how does a working cloud credential come to exist inside that
container, how does the user authorise it from a browser, and where do we persist the result
so it survives the container?**

It does not re-litigate the business question of BYO vs token resale — see the research pair.

Non-goals for the first implementation: Vertex, Foundry, token resale, LLM-gateway metering.
Each is a later phase over the same surface (§11).

---

## 2. The invariant

Everything below reduces to one of two end states inside the container:

1. an **AWS profile** in `$HOME/.aws/config` whose credential source works non-interactively, or
2. a **single env var** (`AWS_BEARER_TOKEN_BEDROCK`, or a container-credential-provider URI).

The native wizard consumes either. Our entire job is to reach one of those two states through a
browser flow, and to remember the result so the next container starts already in that state.

Two hard container facts shape everything (see `docs/architecture/container-runtime.md` and the
strategies):

- **Agent containers are fully ephemeral.** `base_strategy.rb:173-175` sets only `NetworkMode`
  and `AutoRemove` — no binds, no mounts, no tmpfs; K8s pods use `restartPolicy: Never`; the
  container is removed at session end (`base_strategy.rb:89-108`). Nothing on disk survives.
  **Persisting credentials server-side is mandatory, not an optimisation.**
- **Env vars are frozen at container creation** (`agent_base_strategy.rb:88-114` →
  `create_container`), and there is no restart/respawn path anywhere in the repo. We therefore
  cannot flip a provider mid-session ourselves. We do not need to: the wizard writes
  `CLAUDE_CODE_USE_BEDROCK` into `~/.claude/settings.json` and restarts Claude Code itself.
  Our contract is only "the credential source already works".

### Do not put cloud credentials in a Coder workspace

Coder workspaces are a separate, **external** pool reached only over `coder ssh`. This codebase
never stops or deletes them (`workspace_service.rb:41` `stop` has no caller; there is no delete
endpoint), one Coder identity is shared per `Integration`, and claiming is a 60-minute lock per
terminal session. A credential written into a workspace `$HOME` is therefore readable by the
next session that wins the lock — **possibly a different user**. All cloud credential material
stays in the ephemeral agent container.

---

## 3. Connect paths, ranked

| User's starting point | Path | Admin needed | Persisted server-side |
|---|---|---|---|
| IdC Start URL, no admin rights | **SSO device flow, run server-side** | no | OIDC client registration + refresh token (secret) |
| Was handed a Bedrock API key or long-term access keys | Entered in Claude Code's own wizard; we harvest it from its settings file | already did | the key (secret) |

**Removed after being built.** The sections below still describe the reasoning, because it
remains the right reasoning if these ever return — but the code is gone:

- **Cross-account role** (`AwsRoleFlow`, `AwsStsClient`, the Terraform module, the ExternalId
  ritual, `role_setup`/`connect_role`, `AIXLE_AWS_ACCOUNT_ID`). Removed because the platform is
  not going to be operated that way: it only makes sense when our AWS account differs from the
  customer's, and it degenerates for a single-account deployment. §8's security argument for
  preferring it over a device flow still stands and is the thing to re-read before reinstating.
- **LLM gateway** (`connect_static`'s gateway half). Removed as out of scope. Note the CLI wizard
  has no gateway prompt, so nothing else can create such a connection; the adapter's rendering
  was removed with it.
- **The Bedrock API key form.** The credential is still supported, but it is entered in the CLI
  wizard rather than in our UI, and captured from `~/.claude/settings.json` afterwards.

Not built: IRSA for customer-hosted workspaces, and Vertex/Foundry.

**`aws login --remote` is not viable and is excluded.** It prints a URL with no code and no
autofill link, then blocks waiting for the user to paste a code **from the browser back into the
terminal** — a paste inward, which our UI cannot supply. It also refuses IdC users, and its cache
at `~/.aws/login/cache` contains a DPoP EC private key, making it device-bound and non-portable.

Repo doctrine (`oauth-implementation.md` §9) is explicit that if this is built it should be
"project env config + interactive SSO step, **NOT** a static-key form". Path 4 therefore exists
but is presented as a clearly secondary option, never as the default form.

---

## 4. Recommended architecture: server-side broker, non-interactive container

**Do the interactive part in Rails and the browser. Keep the container non-interactive.**

```
browser ──────────────┐
                      ▼
              Rails cloud broker
        (device flow / role assumption)
                      │  short-lived creds on demand
                      ▼
   agent container ── non-interactive credential source ──► Bedrock
```

The container mechanism is deliberately one thing regardless of how the connection was made —
which is what let the role path be removed without touching anything below the broker:

| | Identity Center (built) | Cross-account role (removed) |
|---|---|---|
| Browser step | device authorisation, once per user | IaC apply, once per org |
| Server holds | OIDC registration + refresh token | role ARN + ExternalId |
| Server mints | `sso:GetRoleCredentials` → 1h creds | `sts:AssumeRole` → 1h creds |
| Container sees | identical short-lived creds | identical short-lived creds |

`aws-sdk-core` already ships `Aws::STS`, `Aws::SSO` and `Aws::SSOOIDC` on disk (pulled in by
`aws-sdk-s3`, `Gemfile:154`), so **no new gems are needed** for either path. Only the Bedrock
health check (§9) needs `aws-sdk-bedrockruntime`, or a hand-rolled SigV4 call via `aws-sigv4`.

### Why not run the device flow inside the container

It is possible (the SSO cache filenames are deterministic: the client registration is
`sha1` of a canonical JSON blob, the token file is `sha1(session_name)`), and the fallback design
is sketched in §4.3. But running it server-side removes, at once: the auth container, the watcher
key contract, file scraping, SSO-cache format reproduction, the refresh-token portability
question, and the need for `aws` CLI in the image for anything but diagnostics.

### 4.1 Transport into the container — decide in the spike

Two candidates, in preference order:

1. **Container credential provider** — `AWS_CONTAINER_CREDENTIALS_FULL_URI` plus an
   authorization token, pointing at our vending endpoint. The SDK fetches and refreshes over
   HTTP with no subprocess at all. Both vars are in the bundled SDK's env allowlist. **Must
   verify** the SDK's host restriction (loopback/link-local unless a token is supplied).
2. **`credential_process`** in the seeded profile, pointing at a small helper shipped in the
   image. Well understood, but spawns a process per resolve and has the orphan problem below.

Both are strictly non-interactive. Contract details in §10.

`AWS_ROLE_ARN` + `AWS_WEB_IDENTITY_TOKEN_FILE` is a third candidate worth keeping in view: it is
`AssumeRoleWithWebIdentity`, which carries **no role-chaining 1-hour cap**, so it is the answer
if long uninterrupted sessions become a requirement. It costs an IAM OIDC provider in the
customer account and a JWKS endpoint on our side.

### 4.2 Path 1 onboarding without paste-back

1. Generate a per-customer `ExternalId` (ours, never customer-chosen, 2–1224 chars of
   `[\w+=,.@:/-]`; not a secret but must not be guessable).
2. Render a **per-customer CloudFormation template** to S3 with our account ID and the
   ExternalId **baked into the body**. They must not be stack parameters: prefilled quick-create
   params are always user-editable and `NoEcho` is ignored on them. This is AWS's own
   recommendation for onboarding flows.
3. Quick-create link — exactly three query params are supported:
   `https://{region}.console.aws.amazon.com/cloudformation/home?region={region}#/stacks/create/review?templateURL={s3-url}&stackName={name}`.
   `templateURL` must be S3-hosted. **The IAM-capability checkbox cannot be pre-acknowledged**
   by URL; one manual tick is unavoidable. Omit `RoleName` from the template so only
   `CAPABILITY_IAM` is required rather than `CAPABILITY_NAMED_IAM`.
4. **No callback.** The admin copies one string into our UI once per organisation — the role ARN
   from the Terraform output, or the account ID when using CloudFormation with a named role. An
   SNS-backed custom resource would remove exactly that one paste, at the cost of: a topic per
   region (`ServiceToken` must be same-region as the stack) plus region-pinned links, a topic
   policy with just-in-time allowlisting of each customer account and removal on stack delete, a
   response `PUT` with `content-type` set to the empty string and a body under 4096 bytes, a
   `ServiceTimeout` that defaults to 3600s and strands the customer for an hour if our responder
   breaks, and an **unverified** assumption that the publishing principal really is the customer
   account (blog-attested only; CloudFormation is absent from SNS's `aws:SourceAccount` support
   list). Not worth it. Lambda-backed custom resources are also rejected: they require the
   customer to deploy a function with outbound internet access, which fails outright in a locked
   -down account and raises more security questions than it answers.
5. Provisioning tool, in preference order — all three reach the same end state:
   - **Terraform module** (primary). Organisations of this shape already keep an infra repo and
     take our artefacts through it, so a module reviewed in a PR is the culturally native path.
     `output "aixle_role_arn"` is what the admin pastes.
   - **CloudFormation quick-create with a *named* role.** Keeps the click-through UX; the admin
     supplies only the 12-digit account ID and we derive the ARN. Naming the role raises the
     acknowledgement from `CAPABILITY_IAM` to `CAPABILITY_NAMED_IAM` — still exactly one
     checkbox, just different wording — and without a fixed name the ARN is unguessable, so
     naming is the right trade once the callback is gone.
   - **A short shell script** (`aws iam create-role` + `put-role-policy`) the admin can read
     before running, which posts the ARN back with a one-time enrolment token.
6. **ExternalId validation ritual**, verbatim from AWS: attempt `AssumeRole` both with and
   without the ExternalId. If it succeeds *without*, **do not store the role ARN at all** — wait
   until the customer fixes the trust policy.
7. Preflight before declaring the connection healthy: `sts:GetCallerIdentity`,
   `bedrock:ListInferenceProfiles`, `GetUseCaseForModelAccess` (submit via
   `PutUseCaseForModelAccess` if absent — one call covers an AWS Organization), and a TPM/RPM
   quota check. Fresh AWS accounts have drastically reduced quotas; generate a prefilled Service
   Quotas increase request rather than letting the user discover throttling later.

Per-session credentials are minted with `RoleSessionName = <platform user id>` (which lands in
CUR 2.0 `line_item_iam_principal`, giving per-user cost attribution with zero managed resources)
and `sts:SourceIdentity` for the customer's own CloudTrail. A session policy pins the inference
profiles the user's plan allows.

**Role chaining caps the session at 1 hour** when our own caller is already using role
credentials. That is fine — the credential source is re-resolved automatically. Whether the cap
also applies when chaining from IdC `GetRoleCredentials` output is undocumented; test it.

### 4.3 Path 2, server-side

1. User supplies the IdC **Start URL** (+ IdC region). There is no `sso_issuer_url` config key —
   an issuer URL, if that is what the org publishes, goes in the same field.
2. `SSOOIDC#register_client` with `scopes: ["sso:account:access"]` (required, or no refresh token
   is returned) → `#start_device_authorization`.
3. Our UI renders **`verificationUriComplete` verbatim** as a one-click link. Never construct or
   parse this URL: the documented `device.sso.<region>.amazonaws.com` host does not resolve, and
   real deployments return per-instance hosts.
4. Poll `#create_token`; store access token, refresh token and the client registration encrypted.
5. `SSO#list_accounts` / `#list_account_roles` against
   **`portal.sso.<region>.amazonaws.com`** (not `sso.<region>`, which 404s), token passed in the
   `x-amz-sso_bearer_token` header. Auto-select when there is exactly one account/role pair;
   otherwise show a picker.
6. Thereafter `SSO#GetRoleCredentials` on demand, feeding the same transport as path 1.

Login works with **only** an `[sso-session]` block — no profile — which is what makes
"discover the account and role after signing in" possible. Minimum config we generate:

```ini
[sso-session <name>]
sso_start_url = https://<...>/start
sso_region = <idc-region>
sso_registration_scopes = sso:account:access
```

**Fallback**, if server-side client registration or device-grant refresh tokens turn out to be
restricted: run the flow in the container as a new `auth_kind`, mirroring `DESIGN_KIND`
(`claude_code_adapter.rb:72-106`). The `auth_kind` is an opaque string on
`terminal_sessions.metadata` and `AgentAuthStrategy` never branches on it — it only calls five
adapter hooks, so this needs no new strategy:

| hook | bedrock kind returns |
|---|---|
| `auth_setup_files_for` | `~/.aws/config` with the `[sso-session]` block |
| `auth_launch_commands_for` | `["aixle-aws-login"]` — a script shipped in the image |
| `auth_required_keys_for` | a key in the marker file that script writes |
| `auth_complete_for?` | marker check |
| `reconcile_captured_credentials` | merge the AWS block without disturbing `claudeAiOauth` |

Ship a **script**, not a command line: `send_tmux_command` interpolates into single quotes with
no escaping (`agent_base_strategy.rb:131`). Inside the container the login must be
`aws sso login --sso-session X --use-device-code --no-browser` — **both** flags. Without
`--no-browser` the CLI hands the autofill URL to a browser launch that fails silently in a
container, and prints only the bare URL and code.

---

## 5. Where credentials live

Two stores, because the two paths have different owners.

**Per-user (path 2, 4)** → a new block inside the existing `claude_code` `AgentCredential`
config blob, exactly as `designOauth` sits alongside `claudeAiOauth`. Merging is what
`reconcile_captured_credentials` is for. No new model.

> Amended after multi-company membership landed: `AgentCredential` is UNIQUE on
> `[user_id, company_id, agent_type]`, so it is one row per user **per company** per agent.
> Bedrock spend is billed to the company that incurred it, so a consultant connects a
> separate AWS account in each company and neither connection can see the other. Every read
> therefore names a company — `CloudAuth::CredentialLookup` for a (user, company) pair, and
> `SessionCompany` for anything reached from a session (containers, vending, preflight),
> which is the only layer that knows who is being billed.

**Org-level (path 1, 3)** → `Integration`. It is already the repo's non-OAuth,
company-or-project-scoped encrypted store (`credentials_data`, `company_id` NOT NULL,
`project_id` nullable) with typed reader helpers per provider — the right shape for
"role ARN + ExternalId" or "gateway URL + virtual key". Add a provider.

`OauthCredential` is **not** a fit: `oauth_client_id` is NOT NULL, the provider registry requires
authorization/token endpoints, and `apply_token_response!` assumes an OAuth token shape.

⚠️ `AgentCredential#sync_expires_at` (`:29 → :132`) derives `expires_at` from
`adapter.token_expires_at`, and `refresh_due` selects on it. Returning an AWS expiry there would
**shadow** the Claude OAuth expiry and break the existing refresh sweep. It must become the
minimum of both, never a replacement.

Connection attributes we need beyond region and model IDs, because the corporate reality uses
them (see §7):

- the **AWS profile name** — it must match the `AWS_PROFILE` a committed repo settings file
  expects
- a map of `opus`/`sonnet`/`haiku` → **application inference profile ARN**
- Bedrock guardrail identifier + version
- `availableModels`

---

## 6. Session provisioning and settings precedence

Claude Code's precedence is `managed > CLI args > project local > project > user`.

**Do not introduce `/etc/claude-code/managed-settings.json`.** It appears nowhere in the repo
today, and it would silently override a customer's **committed** project
`.claude/settings.json` — including their per-product inference-profile ARNs and guardrail
headers, i.e. their cost attribution and their content filtering.

Instead extend what already exists:

| what | where |
|---|---|
| Bedrock env + AWS profile name | `claude_code_adapter.rb:226-247` (`config_files`) — already writes `~/.claude/settings.json` at **user** scope, which project settings correctly outrank |
| platform-wide, non-conflicting values | `claude_code_adapter.rb:331+` (`default_env_vars`) |
| `~/.aws/config`, helper script | the same `config_files` map, or `inject_config_files` (`session_context_service.rb:173-184`) |

Two placement constraints:

- **The profile NAME is part of the connection and editable in the connect UI.** A repo that
  commits its own `.claude/settings.json` pins `AWS_PROFILE`, and project settings outrank the
  user settings we write — so that pin must resolve to the profile we wrote, or Claude Code looks
  for one that does not exist. Nothing else needs collecting: the repo's own model ARNs,
  `availableModels` and guardrail headers keep winning by precedence, which is the point.
- **Write the profile to the literal `$HOME/.aws/config`** (`/home/claude/.aws/config`). The
  wizard's profile picker uses the process home directory and **ignores `AWS_CONFIG_FILE`** — a
  profile placed elsewhere silently will not be offered, even though the runtime SDK would honour
  the env var. This rules out adopting the corporate repo-local `.aws/` convention inside the
  container. *(Binary-derived; confirm in the spike.)*
- **Seed helper keys in user settings only.** `awsAuthRefresh` / `awsCredentialExport` /
  `apiKeyHelper` sourced from *project* or *local* settings are refused until workspace trust is
  confirmed. A side effect worth telling corporate users about: their committed project-level
  `awsAuthRefresh` will not fire in a fresh container until trust is accepted.
  *(Binary-derived; confirm in the spike.)*

Set `AWS_REGION` explicitly rather than relying on profile resolution.

**Pin models explicitly.** An unpinned deployment on current versions resolves the primary model
to `us.anthropic.claude-opus-5` and bills at Opus rates. Pin `ANTHROPIC_DEFAULT_SONNET_MODEL` and
`ANTHROPIC_DEFAULT_HAIKU_MODEL`; when the connection carries application-inference-profile ARNs,
use those (and grant `bedrock:GetInferenceProfile`, or every new model costs an extra round-trip).

**Scrub conflicting auth env when Bedrock is active** — `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN`, other provider toggles. A leftover subscription credential shadows
Bedrock and produces exactly the silent failure the corporate runbook works around.

**The wizard's non-secret choices are captured; its secrets are not.** We regenerate
`~/.claude/settings.json` from the connection every session, so anything the wizard wrote that
is not stored on the connection disappears — and an unpinned Bedrock deployment resolves to
Opus and bills at Opus rates. So `ClaudeCodeAdapter#extract_settings_config` reads the file
back at cleanup and folds `AWS_REGION`, `AWS_PROFILE`, the three
`ANTHROPIC_DEFAULT_*_MODEL` pins and `availableModels` into the connection. That is cost
safety, not polish.

Credentials typed at the wizard's prompt — `AWS_BEARER_TOKEN_BEDROCK`, access keys,
`ANTHROPIC_API_KEY` — are deliberately **not** harvested: scraping a secret out of a terminal
and storing it as a static key is what `oauth-implementation.md` §9 rejects ("NOT a
static-key form"). A user who configures Bedrock that way still loses it when the container is
replaced, and the session-start preflight is what tells them so.

⚠️ The reconciliation that makes this safe also fixes a data-loss bug. The default
`reconcile_captured_credentials` is a **full replace** of `config_data` from the files scraped
out of the container. A cloud connection never appears in the container — the connect flow
stored it server-side — so completing an auth session would have destroyed it, refresh token
included. The adapter now merges the stored `awsBedrock` block forward instead.

---

## 7. Alignment with the existing corporate setup

The internal Claude Code runbook is this design executed by hand: an IdC `[sso-session]` +
`[profile]` pair, per-developer SSO, no static keys, and a **committed** `.claude/settings.json`
carrying `CLAUDE_CODE_USE_BEDROCK`, `AWS_PROFILE`, `AWS_REGION`, three application-inference-
profile ARNs, guardrail headers and `availableModels`. Deltas that matter when the same shape
runs in a container rather than on a laptop:

1. Its `awsAuthRefresh` is `aws sso login --profile <p>` with no `--use-device-code`. On a laptop
   PKCE opens a local browser; in a headless container PKCE **cannot work** — the URL must open
   on the machine running the CLI. Copied verbatim, re-auth is broken 8 hours in.
2. Its settings file is project-scoped and must keep winning — hence §6.
3. Its `sso_region` differs from its Bedrock region. That combination failed on Claude Code
   v2.1.207 with `Session token not found or invalid` and was fixed in 2.1.208; pin the image to
   ≥2.1.208.
4. Its AWS CLI floor is 2.9 (enough for `[sso-session]`). Container flows need **≥2.22** for
   `--use-device-code`. Ship the latest v2.
5. `sso_registration_scopes = sso:account:access` must be present in anything we generate.
6. Its preflight scrubs stray API keys and verifies the resolved account, and it ships a `check`
   command because Claude Code hides Bedrock errors. Both become platform features (§9).

The corporate account is the natural first fixture for dogfooding: one Start URL, one account,
one role, one SSO group.

---

## 8. Security posture

**The SSO device-code grant is a published AWS credential-phishing technique.** PKCE-by-default
in AWS CLI 2.22.0 was the mitigation. Security teams are advised to block the device endpoint at
the network layer and to alert on CloudTrail `CreateToken` with
`grantType=urn:ietf:params:oauth:grant-type:device_code`. A product surface that says "click
this link to grant AWS access" is structurally identical to the attack.

Consequences, all of them deliberate:

- Order the paths so the **customer-deployed cross-account role is primary** and device code is
  the documented fallback (§3) — but calibrate this per audience rather than treating it as
  absolute. The published attack is a *vendor* getting an arbitrary customer to click a link. A
  developer signing in to their **own** organisation's Identity Center, on a flow that
  organisation's security team can allowlist and monitor, is a materially different risk profile.
  For an org already standardised on Identity Center — including our own, for dogfooding —
  device code creates nothing in AWS, requires no admin action, and preserves per-developer
  attribution, which makes it the closest fit to how such teams already work.
- Word the connect UI so it cannot be mistaken for a phishing prompt: name the IdC instance,
  show the account and role that will be granted, state plainly what the platform can and cannot
  do with the grant.
- Ship a page for the customer's security reviewers: the flow, the CloudTrail events it emits,
  and the `ExternalId` / `SourceIdentity` / `RoleSessionName` attribution they will see.
- Expect some enterprises to block it outright. Path 1 and path 3 are the answers there.

Other standing rules:

- ExternalId is **not** a secret (anyone who can view the role sees it) but must be generated by
  us and be unguessable. The with/without validation ritual is mandatory (§4.2).
- Prefer STS temporary credentials over short-term Bedrock API keys over long-term keys.
  Long-term keys may be created with **no expiry at all**; short-term keys are computed
  client-side, so their creation is invisible to CloudTrail and cannot be prevented by IAM —
  only their *use* is deniable, via `bedrock:CallWithBearerToken` and
  `bedrock:BearerTokenType` (values `SHORT_TERM`/`LONG_TERM` are case-sensitive), and both the
  `bedrock:` and `bedrock-mantle:` namespaces must be denied to close the door.
- Log every credential vend on our side. Short-term key generation is not CloudTrail-logged.
- Direct-from-container Bedrock calls keep prompts inside the customer's trust boundary. Say so
  in customer security docs, and say the opposite plainly if a gateway tier is ever added.
- The agent user has passwordless sudo in the container, so we cannot treat file permissions on
  `~/.aws/config` as a boundary against the agent itself. It is a boundary against nothing but
  accident.

---

## 9. Defects to fix before building on these seams

1. `AgentAuthStrategy#before_exec` writes auth-setup files with no uid/gid
   (`agent_auth_strategy.rb:31`), so they land owned by `0:0`. A root-owned `~/.aws/config` makes
   `aws sso login` fail for the uid-1001 agent user, which must create the cache directory.
2. `SessionContextService#write_file` discards the runtime return value (`:521-525`), so a failed
   config write is silent and resurfaces as "the wizard shows no profile".
3. `extract_auth_files` (`agent_base_strategy.rb:210-223`) is not kind-aware — it always scrapes
   `adapter.auth_file_paths`, so a bedrock auth kind cannot harvest AWS files. Needs an
   `auth_file_paths_for(kind)` hook mirroring the other five `*_for` hooks. Moot if the
   server-side flow lands.

Both product features lifted from the corporate runbook are now built:

- **Connection health check** — `CloudAuth::AwsHealthCheck` + `AwsBedrockProbe`, exposed as
  `POST /api/v1/cloud/aws_connection/health` and a "Test AWS" button on the profile. It vends
  credentials exactly as a session would, then invokes a model with `max_tokens: 1` and reports
  the provider's message **verbatim** — paraphrasing "on-demand throughput isn't supported" or
  "AccessDeniedException" loses the part that says what to fix. The result carries a `stage`
  (`credentials` vs `invoke`) so the UI says "reconnect" rather than "check your model access".
  It probes the connection's pinned Sonnet, falling back to the default Sonnet and never Haiku:
  Haiku is frequently not enabled in an account, so a Haiku failure would be a false alarm. A
  failed probe answers 200 — a failed probe is a successful diagnosis.
- **Session-start preflight** — `CloudAuth::Preflight` + `SessionService#preflight_cloud!`,
  raising `CloudAuth::PreflightError`. A rotten connection blocks the launch with the same
  `422 { reauth_required: … }` shape the OAuth preflight already uses, so `SessionNewForm`
  renders the CTA through one code path. This is what solves the chicken-and-egg problem: the
  user is stopped **before** the session starts, so nothing has to display a URL from inside a
  credential resolver.

### How the user reaches the connect step

There is deliberately **no separate "Connect AWS" button**. The user declares the intent
where it naturally arises — by picking `3rd-party platform → Amazon Bedrock` inside Claude
Code's own login wizard, in the throwaway auth container the profile's **Authenticate**
button already launches.

The signal is the credential helper itself. `auth_setup_files_for` seeds the platform's AWS
profile into the auth container, the wizard lists it, and the wizard **executes its
`credential_process` during verification** (measured, §10). The helper reports that this
user has no connection; `CloudCredentialsController` records that on the session with
`update!` — so the model's existing `broadcasts_to` wakes the browser — and the auth modal,
already on screen and already polling, swaps in the connect form. Meanwhile the helper
**keeps retrying** for ~100s (under the 120s chain-resolve timeout), so when the user
finishes connecting, the wizard's verification passes on its first attempt rather than
reporting a credential error the user has to click past.

Two consequences worth stating:

- The auth container gets the vending env **even with no connection**. Reporting "nothing to
  vend" is the helper's entire job there.
- Bedrock writes no auth file, so the watcher's `authenticated` flag stays false forever on
  this path. Completion is driven by the connection being stored, not by
  `auth_complete_for?` — and the auth session ending without saving a credential is correct,
  since the connection was saved by the connect flow.
- Coverage limit: only the wizard's **profile** branch executes `credential_process`. A user
  who instead pastes a Bedrock API key at the wizard's prompt produces no signal. That branch
  writes `~/.claude/settings.json` at the end, so it could be caught by extending the
  watcher with a second env-configured watch — the browser must never be handed a
  general-purpose file read, since `/file` is confined to `/workspace` on purpose.

The `Reconnect AWS` CTA from session-start preflight goes through the same door
(`/profile?authenticate=claude_code` opens the auth modal), rather than reintroducing a
second cloud-specific entry point.

Also built: **conflicting-env scrubbing.** `BaseAdapter#conflicting_env_keys` lets a provider
declare the env that would shadow it, and `AgentSessionStrategy` filters those keys after every
other env source has been merged (including `ConfigItem` references). For Bedrock that is
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_USE_VERTEX` and
`CLAUDE_CODE_USE_FOUNDRY`. `ANTHROPIC_BEDROCK_BASE_URL` is deliberately excluded — that is how a
customer points Claude Code at their own gateway in front of Bedrock.

---

## 10. Constraint reference

Sources: official Claude Code and AWS documentation, except where marked *(binary-derived)* —
those come from inspecting the installed v2.1.220 bundle and must be re-confirmed in the spike.

### Claude Code

- Native path: `3rd-party platform → Amazon Bedrock → interactive setup`; re-openable later with
  `/setup-bedrock`. The wizard offers: an AWS profile detected from `~/.aws`, a Bedrock API key,
  an access key + secret, or credentials already in the environment. **It never performs a
  browser login itself.** It writes region and model pins into the user settings `env` block.
- The wizard lists profiles by scanning section headers only — no credential-key filtering — so a
  `credential_process`-only profile is offered. It excludes `[sso-session …]` sections. The field
  also accepts a typed name. *(binary-derived)*
- Wizard verification calls `sts:GetCallerIdentity` then `bedrock:ListInferenceProfiles`, and the
  model-pin step probes `InvokeModel` per model. Failure is soft — "Go back and fix" or "Save
  anyway". So a pre-seeded credential source **is exercised** during setup. *(binary-derived)*
- `awsCredentialExport`: output captured **silently**, never shown to the user. Accepts nested
  `{"Credentials":{…}}` or the flat `aws configure export-credentials --format process` shape.
  Reads `AccessKeyId`, `SecretAccessKey`, `SessionToken`, `Expiration`; `Version` is ignored;
  `Expiration` optional but **absent means cached for a full hour**; `SessionToken` is
  **required and non-empty**, so long-term IAM keys are rejected. Runs at session start and on
  every reload. Failure is non-fatal and falls through to the default chain.
- `awsAuthRefresh`: output **is** displayed. It is the only user-visible channel, rendered as the
  last few lines of an `Authentication` panel — and only while the command is still running, so
  to show a link the helper must print it and then block. Hard SIGTERM at **3 minutes**. Runs
  only when credentials are absent or invalid (gated on a `GetCallerIdentity` probe),
  single-flight, with a cooldown. Configuring it also adds a `/login` entry to refresh
  credentials. *(panel mechanics and timings binary-derived; the "output is displayed" contract
  is documented)*
- Known failure mode: `awsAuthRefresh` can loop indefinitely when a corporate proxy interrupts
  the browser flow. Our connect script must exit non-zero rather than retry.
- Credential chain resolution times out after **60 s**; raise with
  `CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS`. The timeout does **not** kill the child process, so
  a blocking helper orphans one process per retry (default 11 attempts). *(binary-derived)*
- Resolved credentials are cached until 5 minutes before expiry. Auth-shaped errors invalidate the
  cache and re-run the source; ordinary retries do not. The source must be idempotent and fast
  on the warm path.
- Bedrock uses the Invoke API, not Converse. WebSearch is unavailable. `/logout` is unavailable.
- Relevant env vars beyond the obvious: `AWS_BEARER_TOKEN_BEDROCK`, `AWS_ROLE_ARN`,
  `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_CONTAINER_CREDENTIALS_FULL_URI`,
  `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`, `CLAUDE_CODE_SKIP_AWS_CRED_CACHE`,
  `ANTHROPIC_BEDROCK_BASE_URL`, `ANTHROPIC_BEDROCK_MANTLE_BASE_URL`, `CLAUDE_CODE_USE_MANTLE`,
  `CLAUDE_CODE_SKIP_MANTLE_AUTH`, `ANTHROPIC_BEDROCK_SERVICE_TIER`.

### AWS

- `aws sso login --sso-session <name>` needs CLI ≥ 2.9; `--use-device-code` needs ≥ 2.22;
  PKCE is the default from 2.22 and cannot work cross-device.
- Use `verificationUriComplete` from the API verbatim. The documented
  `device.sso.<region>.amazonaws.com` host does not resolve; real instances return per-instance
  hosts. Treat the user code as opaque.
- SSO cache: two files, mode 0600, under `~/.aws/sso/cache/`. Registration is `sha1` of a
  canonical JSON blob and carries `expiresAt`; the token file is `sha1(session_name)` and carries
  `registrationExpiresAt`. **Client registration lives 90 days** and refresh hard-stops there.
- Access tokens are **1 hour**, auto-refreshed. Session lengths stack: permission-set session 1h
  default / 12h max; IdC interactive portal session 8h default / 90 days max. AWS Managed AD caps
  at 10h; an external IdP's `SessionNotOnOrAfter` caps at the shorter.
- Refresh-token portability between machines is **undocumented**. There is no device binding in
  the `CreateToken` schema and the OIDC client is registered unsigned, so it should work — but do
  not depend on it. (Moot in the server-side design, where we are always the same client.)
- Portal API is `portal.sso.<region>.amazonaws.com`, signing name `awsssoportal`, bearer token in
  the `x-amz-sso_bearer_token` header. Ops: `ListAccounts`, `ListAccountRoles`,
  `GetRoleCredentials`.
- `credential_process` JSON: `Version` must be the **unquoted integer 1**; `AccessKeyId`,
  `SecretAccessKey` required; `SessionToken`, `Expiration` (strict RFC 3339, `Z`), `AccountId`
  optional. stderr is piped and surfaced only on non-zero exit (Go SDKs inherit it instead).
  botocore has no timeout of its own. It refreshes at T-15/T-10 minutes, so credentials must be
  issued with well over 15 minutes of life. Without `Expiration` the process is treated as
  long-term and **never re-invoked**.
- Role chaining caps `DurationSeconds` at 1 hour regardless of the role's `MaxSessionDuration`.
  `AssumeRoleWithWebIdentity` is not chaining and is not capped.
- Pricing levers worth wiring in from day one: prompt caching is on by default and is the single
  largest cost factor for agentic loops (watch cache-hit token ratios for regressions); global
  inference profiles are ~10% cheaper than regional; `max_tokens` must be a platform-governed
  parameter because Bedrock reserves quota by it at request start.
- Claude Fable/Mythos-class models require the `provider_data_share` retention mode and show as
  unavailable without it. Handle "model unavailable under this tenant's retention mode"
  gracefully rather than failing opaquely.

---

## 11. Phases

**Phase 0 — spike.** Bedrock env in `claude_code_adapter` behind a flag, a pre-seeded profile in
the literal `$HOME/.aws/config`, credentials from a test account. This is also where every
binary-derived claim in §10 gets confirmed for real inside the container, and where the transport
choice in §4.1 is settled.

**Phase 1 — cross-account role. BUILT, THEN REMOVED (see §3).** Recorded for whoever reinstates it:
`CloudAuth::AwsRoleFlow#prepare` issues a per-user ExternalId and renders the Terraform module
with the ExternalId and our account id **baked into the body**; `#finish` runs the AWS-prescribed
confused-deputy ritual (assume without the ExternalId must fail) and refuses to store the ARN at
all when it succeeds. Vending goes through `CloudAuth::AwsStsClient#assume_role` with
`RoleSessionName` = platform user id, capped at the role-chaining hour. Reductions:

- **Per-user, not org-scoped.** The role connection lives in the same `awsBedrock` block on the
  user's `AgentCredential` rather than on a company/project `Integration`. That makes the path
  usable today (a developer pastes the ARN their admin created) and defers the scoping surgery —
  and the resolution layer a session would need to choose between a per-user and an org
  connection. `Integration` remains the right home for a genuinely org-wide connection.
- **Terraform only, no CloudFormation quick-create.** A quick-create link requires the template
  to be S3-hosted, which needs infrastructure this deployment does not have yet. The module
  needs none, and is the better fit for organisations that already take our artefacts through an
  infra repo.

Requires `AIXLE_AWS_ACCOUNT_ID` to be set, or `#prepare` refuses with `NotConfiguredError` — an
operator problem, surfaced as such rather than as "connect your account".

**Phase 2 — SSO device flow (fallback, and the answer for non-admins). BUILT.** As-built
map:

| piece | where |
|---|---|
| Identity Center seam (OIDC + portal), vendor errors translated | `app/services/cloud_auth/aws_sso_client.rb`, `cloud_auth/*_error.rb` |
| device flow: start → poll → finish, state in `Rails.cache` | `app/services/cloud_auth/aws_device_flow.rb` |
| credential vending, single-flight refresh | `app/services/cloud_auth/aws_credential_vendor.rb` |
| derived per-session bearer for the container | `app/services/cloud_auth/session_key.rb` |
| vending endpoint (`POST /cloud/aws/credentials`) | `app/controllers/cloud_credentials_controller.rb` |
| connect API + policy | `app/controllers/api/v1/cloud/aws_connections_controller.rb`, `app/policies/api/v1/cloud/aws_connections_policy.rb` |
| session-start gate | `app/services/cloud_auth/preflight.rb`, `SessionService#preflight_cloud!` |
| container rendering (settings env, `~/.aws/config`, vending env) | `Agents::ClaudeCodeAdapter` |
| in-container helper + AWS CLI v2 | `docker/base/cloud/aixle-aws-creds`, `docker/claude-code/Dockerfile` |
| connect UI | `app/frontend/shared/resources/cloud-connections/AwsConnectionModal.tsx` |
| canonical fake + contract test | `test/support/fakes/fake_aws_sso_client.rb`, `test/services/cloud_auth/aws_sso_client_contract_test.rb` |

Storage: an `awsBedrock` block merged into the user's existing `claude_code`
`AgentCredential`, with the Identity Center registration and tokens under
`identity_center` — deliberately **not** `sso_session`, which is what makes the adapter
render an `[sso-session]` block for the in-container fallback.

Not built here: the proactive refresh sweep, which was rejected on purpose — see §14.

**Phase 3 — secondary paths. REMOVED except the API key (see §3).** Historical note: `POST connect_static` stores either a Bedrock API
key (`AWS_BEARER_TOKEN_BEDROCK`) or a gateway base URL (`ANTHROPIC_BEDROCK_BASE_URL`); both need
no server-side vending, so `Preflight` treats them as having nothing that can rot, and the
adapter renders them straight into the settings env. Not built: IRSA for customer-hosted
workspaces (needs a customer-hosted runtime to exist first), and Vertex/Foundry.

**Phase 4 — other clouds.** Vertex (`CLAUDE_CODE_USE_VERTEX`, `gcpAuthRefresh`, ADC) and Foundry
(`CLAUDE_CODE_USE_FOUNDRY`, Entra chain, no refresh hook needed) over the same connection surface.

Cross-cutting, do not defer: model pinning, env scrubbing, the health check, and the security
documentation in §8.

---

## 12. Verification

Per `docs/testing.md` §4, a new external service must be wrapped in an app-owned adapter, given
one canonical fake in `test/support/fakes/`, and contract-tested. That means app-owned wrappers
over `Aws::SSOOIDC` (device flow), `Aws::SSO` (`GetRoleCredentials`), `Aws::STS` (`AssumeRole`
with ExternalId) and the Bedrock health-check call — never vendor-side stubs, never scattered
`stub_request`.

- Contract-test the generated artefacts: the `~/.aws/config` body, the settings `env` block, and
  the transport payload, per path and per connection shape.
- Assert the settings-precedence rule directly: a session whose repo carries its own
  `.claude/settings.json` must keep that file's ARNs and guardrail headers intact.
- Assert that Bedrock mode scrubs conflicting auth env.
- If the in-container fallback is built, `test/services/container_strategies/agent_auth_strategy_test.rb:380-484`
  is the template — it is the full matrix for the existing `design` auth kind.
- Full suite in Docker before pushing: `docker compose exec -T web make check_all`.

---

## 13. The model catalogue, and why it is filtered

`CloudAuth::AwsModelCatalog` asks `bedrock:ListInferenceProfiles` with the credentials the
connection vends. That call is the only truthful catalogue: an enterprise account exposes its
models as **application inference profiles** whose ARNs are account-specific, and no static
list can name them. It also feeds `available_models`, which narrows Claude Code's own `/model`
picker — refreshed on every reconnect, so a newly enabled model appears after reconnecting.

One correction to "only truthful": `ListInferenceProfiles` answers *what exists in this
account*, not *what this connection may invoke*, and there is no API that answers the second
question. An account that curates its models does it by creating application profiles and
scoping `bedrock:InvokeModel` to exactly those ARNs — every system-defined profile then stays
**visible but denied**. Measured against the real `541894707537` account, whose permission set
allows four Opus/Sonnet/Haiku ids: a system-defined *Fable* profile was listed, sorted to the
top as the newest generation, and was denied on the first invocation.

Measured against one real account: 25 profiles in, 12 offered. Four filters, each with a
reason worth keeping:

- **Application profiles win outright.** If the account has any of its own, only those are
  offered and the system-defined ones are dropped — their existence is the signal that the
  account curates its model set, and it also keeps invocations on the profiles the account
  tags for cost attribution (calling the shared profile directly bypasses that). An account
  with no application profiles falls through to the system-defined list unchanged.
- **Claude 3.x dropped.** A 2x "extended access" surcharge on Bedrock, retiring on a calendar
  that differs from Anthropic's own. The discriminator is where the version sits in the name —
  legacy puts it before the family (`claude-3-sonnet`), current after (`claude-sonnet-4-6`).
- **Newest generation first**, so the obvious pick is also the right one. Anything unparseable
  sorts last rather than at random.
- **One geography per model**, preferring `global`. A global profile costs roughly 10% less
  than the regional one for the same model and draws on a much larger capacity pool, so
  offering both invites paying more by accident. A model offered only regionally keeps its
  regional profile.

⚠️ The geography preference is the one filter that can bite. An organisation with
data-residency rules can SCP-block `global`, and then every model we offer is denied. The
failure is visible rather than silent — "Test AWS" reports the provider's own message — and
reconnecting re-reads the catalogue. If this turns out to be common, the fix is a residency
setting on the connection rather than dropping the preference: paying 10% more by default is
worse than a recoverable, diagnosable denial.

Application profiles are never collapsed into each other: they are the account's own objects,
not geographic variants of a shared model. Failure to list is never fatal — a permission set
without `bedrock:ListInferenceProfiles` is common, and an unrestricted picker beats a broken
page or a failed connect.

## 14. Confirmed in-container (Phase 0, 2026-07-25)

Measured inside `aixle/claude-code` with AWS CLI 2.33.29 added, using fabricated
`ASIAFAKE…` credentials and no real AWS account:

- The agent runs as uid 1001 with `HOME=/home/claude`, and Node's `os.homedir()` resolves
  to the same path — so the wizard's profile scan and our write target agree.
- Claude Code in Bedrock mode **does** invoke a `credential_process` from the seeded
  profile and signs Bedrock requests with what it returns (AWS replied
  `403 … security token … is invalid`, which only the fake credentials can produce). Two
  invocations per session with retries disabled, not one per request — credentials are cached.
- **`credential_process` stderr is invisible.** A marker string printed to stderr by the
  helper appeared in neither Claude Code's stdout nor its stderr. This is the claim the
  design most depends on, and it now rests on measurement rather than bundle reading.
- `aws sso login` accepts `--sso-session`, `--use-device-code` and `--no-browser`
  together (it failed on the session name, not on unknown options). `aws login` accepts
  `--remote`.
- `~/.aws` exists and is owned by the agent user.

## 15. Open items

- Still unverified from §10, because each needs either a real Identity Center instance or a
  driven TUI: that the wizard lists a `credential_process`-only profile (measured on a host with
  the same CLI version, not yet in-container), that its picker ignores `AWS_CONFIG_FILE`, the
  `Authentication` panel rendering and its 3-minute budget, the workspace-trust gate on
  project-scoped helper keys (likely already moot — `generate_projects_config` writes
  `hasTrustDialogAccepted: true` for `/workspace`), and the exact output shape of
  `--use-device-code --no-browser`.
- Transport decision: container credential provider vs `credential_process` (§4.1), including the
  SDK's non-loopback host restriction.
- Whether role chaining from IdC `GetRoleCredentials` credentials is also capped at 1 hour.
- Whether the SNS publishing principal for a cross-account custom resource is really the customer
  account — that is blog-attested only, and CloudFormation is absent from SNS's
  `aws:SourceAccount` support list.
- Whether IdC permits `register_client` from a non-CLI client, and whether the device grant
  returns refresh tokens in that case. If not, Phase 2 falls back to the in-container flow.
- Re-confirm every *(binary-derived)* item in §10 empirically in Phase 0.
