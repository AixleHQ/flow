# AWS OIDC: workflow steps assume a customer's IAM role without keys

Proposed 2026-11-25. Not built.

A workflow step that needs the customer's AWS account today gets there with an IAM
user's access key stored as a config item. This design makes Flow an OpenID Connect
identity provider that the customer's AWS account trusts, so a step assumes an IAM
role through `AssumeRoleWithWebIdentity` and holds only one-hour credentials. No
long-lived key exists on either side.

It ships as a separate, project-level integration called **AWS OIDC**, behind a
feature flag, and changes nothing for a project or a step that does not use it.

## 1. The problem

The request that started this: a team builds a workflow triggered from a Slack
thread that reads production CloudWatch logs, queries an Aurora database read-only
through the RDS Data API, and replies with a diagnosis. The production account has
no IAM users, only Identity Center, and the team does not want to create the first
long-lived key just for this.

What Flow offers today, and why none of it is the answer:

| Option | What is wrong with it |
|---|---|
| IAM user key in a config item, used from an MCP server's env (`config_item:NAME`) | A long-lived key. An item an attached MCP server references is attached to the session (`SessionConfigResolver#resolve_config_item_ids`), so the agent can read it with `get_config_item`; the stdio server's config is written into the agent's container as well. |
| The same key held by a custom tool (`required_config_items`) | Keeps the key out of the agent's container, since it arrives as env in the tool's own container (`ContainerStrategies::CustomToolStrategy#resolve_config_items`). Still a long-lived key, and every AWS call becomes an async container run. |
| A self-hosted runner in the customer's account with an instance role | No key, but it needs always-on compute in the customer's account (the team above was told "no always-on EC2 in prod"), runners are behind `external_runners`, and session containers can reach the instance metadata endpoint. |
| IAM Roles Anywhere | Needs an X.509 certificate and its private key in the session: a long-lived secret in another shape. |

The workaround recommended until this ships is a key whose only permission is
`sts:AssumeRole` into a read-only role, held by a custom tool. The role is built so
that moving to this design is one change on the AWS side: the role's trust
principal goes from that IAM user to the OIDC provider, and the user is deleted.

## 2. Decisions

1. **Flow is the OIDC identity provider; AWS trusts it.** The model GitHub Actions,
   GitLab CI (`id_tokens`), Terraform Cloud dynamic credentials and EKS (IRSA) use.
   No Flow-owned AWS account takes part, so it works the same on a self-hosted
   instance.
2. **A separate integration, AWS OIDC, at project level.** Provider `aws_oidc` on
   `Integration`, listed under Project Settings → Integrations, gated by the
   `aws_oidc` feature flag. Named for the mechanism, not for AWS as a whole: other
   AWS integrations may follow.
3. **One issuer per integration.** `https://<host>/oidc/<issuer_key>`, a random key
   generated on connect, the way EKS gives each cluster its own issuer. The IAM
   OIDC provider in the customer's account is then bound to this one project's
   integration, not to every tenant on the instance (§5.1).
4. **Workflow steps only.** No ad-hoc sessions (§3).
5. **Rails does the exchange.** Rails signs a short-lived token, calls STS itself
   and hands the session the resulting credentials through the `credential_process`
   path already built for Bedrock. The token never enters the container (§6).
6. **The agent sees the role credentials, and that is intended.** The boundary is
   the role's permissions, the one-hour lifetime and CloudTrail attribution per
   session, not secrecy from the agent (§10).
7. **A role reaches a step only by an explicit pick.** `inherit_all_project_resources`
   does not pull roles in (§7.2).

## 3. Scope: workflow steps, not ad-hoc sessions

An AWS role can be attached to a workflow (as a base resource) or to a step. An
interactive session started by hand cannot have one.

Two reasons:

- **No stable workload identity.** A step has one: `workflow:12:step:34` is the
  same automation on every run, so an AWS administrator can trust exactly that. An
  ad-hoc session has a random id and does whatever the person types. Its `sub`
  could only say "some session in this project" or "this user", which turns the
  trust policy into a per-person grant.
- **Silent widening.** If roles could go on sessions, everyone who can start a
  session in the project would effectively hold the role, and nobody would have
  decided that. A step's attachment is part of a reviewed workflow, recorded in its
  version history (`Versions::Snapshots`).

Testing a role before the workflow exists is covered by the integration's
**Verify** action (§8) and by test runs of the workflow, including drafts (§5.3).

Out of scope for the first version: GCP Workload Identity Federation and Azure
federated credentials (the same issuer can serve them later), a CloudFormation
quick-create link, and attribute-based access control beyond the session tags
in §5.2.

## 4. How it works

```
 Customer's AWS account                         Flow
 ──────────────────────                         ────
 IAM OIDC provider                              AWS OIDC integration (project)
   url: https://<host>/oidc/<issuer_key>          issuer_key, roles[]
   audience: sts.amazonaws.com
 IAM role prod-diag                             Step "Diagnose" ── attached role: prod-diag
   trust: provider, aud, sub = workflow:12:*

 Run:
 agent container                Rails                              AWS STS
   aws logs ... ─┐
   SDK resolves credentials
   credential_process ──POST──▶ check session key, step, role
                                sign JWT (iss, aud, sub, tags, 5 min)
                                AssumeRoleWithWebIdentity ─────────▶ fetches
                                                                     <issuer>/.well-known/openid-configuration
                                                                     and JWKS, checks
                                                                     signature + trust policy
                                ◀──────────────── 1h credentials ───
                                arm log redaction, record issuance
   ◀── credential-process JSON ─
```

Setup, once per role:

1. A project admin connects AWS OIDC. Flow generates `issuer_key` and shows the
   issuer URL and the audience.
2. The customer creates an IAM OIDC provider for that URL with audience
   `sts.amazonaws.com`, and a role. The integration page generates the role's trust
   policy, with the `sub` condition already filled in for the chosen workflows.
3. The admin adds the role to the integration (name, ARN, region, session
   duration) and presses **Verify**.
4. A workflow editor attaches the role to the workflow or to a step.

At run time the SDK in the container asks for credentials when it first needs them
and again before they expire. Nothing on Flow's side runs ahead of that.

## 5. The issuer and the token

### 5.1 Issuer

- **URL:** `https://<host>/oidc/<issuer_key>`. `issuer_key` is 32 random URL-safe
  characters stored on the integration. It is not a secret (it sits in the
  customer's IAM configuration), but it is not guessable either.
- **Discovery:** `GET /oidc/<issuer_key>/.well-known/openid-configuration` returns
  `issuer`, `jwks_uri` (`/oidc/<issuer_key>/jwks`), `response_types_supported`
  (`["id_token"]`), `subject_types_supported` (`["public"]`),
  `id_token_signing_alg_values_supported` (`["RS256"]`) and `claims_supported`.
- **Visibility:** both endpoints answer 404 unless the integration is active and
  the `aws_oidc` flag is on for its company. Disconnecting the integration
  therefore makes STS refuse every token for it: a kill switch that takes effect on
  the AWS side, not only in Flow.
- **Why one issuer per integration.** With one instance-wide issuer, a trust policy
  that checks only `aud` (a common mistake with GitHub's issuer) accepts a token from
  any tenant of the instance. With an issuer per integration, the same sloppy policy
  accepts only this project's integration. The `sub` condition then narrows to
  workflows, rather than being the only thing between tenants.
- **Reachability.** STS fetches discovery and JWKS from the public internet over
  HTTPS. The hosted platform qualifies. Staging is behind HTTP Basic auth and needs
  the same exemption the MCP OAuth endpoints got (aixle-infra #129). A self-hosted
  instance that is not reachable from AWS cannot use this integration, and Verify
  says so.

### 5.2 Token

Signed RS256 with the instance's current signing key (§5.4), `kid` in the header.

| Claim | Value |
|---|---|
| `iss` | the integration's issuer URL |
| `aud` | `sts.amazonaws.com` |
| `sub` | see §5.3 |
| `iat`, `nbf` | now |
| `exp` | now + 5 minutes. Rails exchanges it immediately, so it only has to outlive one STS call. |
| `jti` | random, recorded with the issuance |
| `https://aws.amazon.com/tags` | `principal_tags`: `flow_project`, `flow_workflow`, `flow_step`, `flow_run`, `flow_session`, `flow_user` (ids); `transitive_tag_keys`: none |

The session tags make each set of credentials attributable in CloudTrail and usable
in `aws:PrincipalTag` conditions. Passing tags requires `sts:TagSession` in the
role's trust policy; the generated policy includes it, and Verify names it when it
is missing.

`RoleSessionName` is `flow-session-<session id>`, so CloudTrail's role session ARN
names the Flow session.

### 5.3 Subject

| Run | `sub` |
|---|---|
| Workflow step | `workflow:<workflow id>:step:<step id>` |
| Test run of a draft | `draft:workflow:<source workflow id>:step:<source step id>` |

- **Ids, never slugs.** Slugs can be renamed (company slugs moved into URLs in #864).
  A renamed project would either break its trust or, worse, start matching a
  pattern written for something else.
- **Derived from the session, never from the request.** The vending endpoint takes a
  role name and nothing else; `sub` comes from the session's step run.
- **Drafts.** A draft is a hidden copy of the workflow with its own id
  (`Workflow#draft_of`, docs/design/workflow-drafts.md). Using the copy's id would
  make every draft test run fail the trust policy. Using the source id without a
  marker would let `workflow:12:*` hand production credentials to unsaved changes.
  The `draft:` prefix makes that the AWS administrator's explicit choice: one more
  line in the policy. The source step is the draft step's `Step#origin_step`. A step
  added in the draft has none and uses `draft:workflow:<source id>:step:new-<draft step id>`.
- **The project is not in `sub`.** The issuer already identifies it.

A trust policy for one workflow, as the integration page would generate it:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/flow.example.com/oidc/9fK2..." },
    "Action": ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"],
    "Condition": {
      "StringEquals": { "flow.example.com/oidc/9fK2...:aud": "sts.amazonaws.com" },
      "StringLike":   { "flow.example.com/oidc/9fK2...:sub": "workflow:12:step:*" }
    }
  }]
}
```

### 5.4 Signing keys

- One key set per instance, shared by every issuer; only the `iss` string differs.
  Per-integration keys would add key management without adding isolation: the key
  is held in the same database either way.
- Table `oidc_signing_keys`: `kid`, `private_key` (encrypted with `Encryptable`),
  `public_jwk`, `state` (`next`, `current`, `retired`), `activated_at`,
  `retired_at`.
- JWKS publishes `next` and `current` (and `retired` keys until the last token
  signed with them has expired, which with a 5-minute token is minutes).
- Rotation: a scheduled job promotes `next` to `current`, creates a new `next` and
  retires the old key. `next` is published at least a day before it signs anything,
  so a JWKS cached by AWS already contains it.
- The first key is created on first use; there is no operator setting to fill in.

## 6. Delivering credentials into the container

### 6.1 What exists

Bedrock through Identity Center already works this way
(docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md):

- `docker/base/cloud/aixle-aws-creds`, a `credential_process` helper that POSTs to
  the platform and prints the credential-process JSON;
- `CloudCredentialsController`, which authenticates the call with a per-session key
  derived from the app's key base (`CloudAuth::SessionKey`, header `X-Cloud-Key`) and
  vends only to a live session;
- `AIXLE_CLOUD_CREDENTIALS_URL` and `AIXLE_CLOUD_KEY` in the container's env;
- `CloudAuth::AwsCredentialVendor#to_credential_process_json`, the exact output
  shape the SDKs require.

### 6.2 What changes

- **The helper moves into the base image.** Today only `docker/claude-code/Dockerfile`
  copies it; every runtime's image needs it. It gains `--role <name>`. In that mode it
  makes one attempt and fails fast: the 100-second wait loop exists for Claude Code's
  Bedrock wizard, which no role call involves.
- **A vending action for roles**, next to the Bedrock one and behind the same session
  key: `POST /cloud/aws_oidc/credentials` with the role name. It refuses unless the
  session is active, is a workflow step's session, and the role is in the step's
  resolved set (§7.2). It then signs the token, calls STS, arms log redaction and
  records the issuance (§7.3) before returning anything.
- **The vending env is set for a session that has a role or a Bedrock connection.**
  Today `ClaudeCodeAdapter#cloud_credential_env` sets it only for Bedrock.
- **Cache.** Credentials are cached per (session, role) until five minutes before they
  expire, so several SDK clients resolving at once cost one STS call. The cache is
  dropped when the session leaves the active state.

### 6.3 `~/.aws/config`

Each role becomes a named profile:

```ini
[profile prod-diag]
credential_process = aixle-aws-creds --role prod-diag
region = eu-west-1
```

- **One writer.** `ClaudeCodeAdapter#aws_config_file` already writes the whole file
  for Bedrock. Two writers would overwrite each other, so the file is composed in one
  place from both sources: the Bedrock profile, if any, and one profile per attached
  role.
- **`[default]` only when it cannot be shadowed.** When the step has exactly one role
  and the session has no Bedrock connection, the role is also written as `[default]`,
  and plain `aws …` or `boto3.client(...)` works. With Bedrock on, Claude Code's
  settings env carries `AWS_PROFILE`, `AWS_REGION` and possibly static keys, and the
  agent's shell inherits them; a default profile would be silently bypassed, so the
  agent is told to name the profile instead.
- **Stdio MCP servers.** An MCP client passes a stdio server only part of its own
  environment, so a server should get `AWS_PROFILE=<name>` in its own env setting.
  It is not a secret and needs no config item.
- **Context.** The session's context file lists each profile with its role ARN,
  account and region, and says to pass `--profile` / `AWS_PROFILE`.

## 7. Data model

### 7.1 Integration and roles

- `Integration` provider `aws_oidc`, one per project. `settings`: `issuer_key`,
  `verified_at`.
- New table `aws_oidc_roles`:

  | Column | Notes |
  |---|---|
  | `integration_id` | FK, cascade |
  | `name` | profile name, `[a-z0-9-]`, unique within the integration |
  | `role_arn` | validated as `arn:aws[-a-z]*:iam::<12 digits>:role/...` |
  | `region` | default region written into the profile |
  | `session_duration_seconds` | 900–3600, default 3600; must not exceed the role's own maximum |
  | `created_by_id` | |

### 7.2 Attachment

- A new `aws_oidc_role_id` column on `step_resource_links` and
  `workflow_resource_links`, added to `ResourceLink::COLUMNS` and read and written
  through `ResourceLists`, like every other resource list.
- `SessionConfigResolver#resolve_aws_oidc_role_ids`: the workflow's base roles plus
  the step's, additive like tools and config items. Unlike them,
  `inherit_all_project_resources` does **not** add the project's roles: production
  access is always a named pick.
- The duplicator, the version snapshots (`Versions::Snapshots`) and the template
  exporter learn the column. A template carries a role by name only, never its ARN;
  installing it asks for a role of that name in the target project.

### 7.3 Audit

Table `aws_oidc_credential_issuances`: `aws_oidc_role_id`, `terminal_session_id`,
`step_run_id`, `user_id` (the session's user), `sub`, `jti`, `expires_at`,
`created_at`. One row per STS call, not per SDK resolve. It is what the
integration's Activity list reads, and what answers "which run held this role on
Tuesday" from the Flow side; CloudTrail answers it from the AWS side.

## 8. The integration page

Under Project Settings → Integrations, only with the `aws_oidc` flag on:

1. **Trust.** Issuer URL and audience, with copy buttons; Terraform and
   CloudFormation snippets for the OIDC provider.
2. **Roles.** Name, ARN, region, session duration. For each role, the generated trust
   policy, with a workflow picker that fills in the `sub` patterns and a checkbox
   for the draft pattern.
3. **Verify** (per role). Signs a token with `sub` = `verify:integration:<id>`, calls
   `AssumeRoleWithWebIdentity` and then `sts:GetCallerIdentity`, and shows the
   assumed-role ARN. The credentials are dropped after that call and never shown.
   Generated trust policies include the `verify:` subject; a customer who removes it
   loses only the button. Failures are translated (§9).
4. **Activity.** Recent issuances: when, role, workflow and step, run, user.

In the workflow builder, a step's resources get an **AWS roles** picker, shown only
when the project has an active AWS OIDC integration. Mockups to follow.

## 9. Failures

| STS says | Usual cause | Shown as |
|---|---|---|
| `InvalidIdentityToken`, "Couldn't retrieve verification key" | provider created for another URL, issuer unreachable (staging Basic auth, self-hosted behind a VPN) | "AWS could not fetch Flow's signing keys from <issuer>" |
| `InvalidIdentityToken`, other | no OIDC provider for this issuer in that account; audience missing on the provider | "No OIDC provider for <issuer> with audience sts.amazonaws.com in account <id>" |
| `AccessDenied` | `sub` does not match the trust policy; `sts:TagSession` missing | "The role's trust policy rejected subject <sub>" plus the TagSession hint |
| `ValidationError` on duration | `session_duration_seconds` above the role's maximum | "The role allows at most N seconds" |
| `ExpiredTokenException` | clock skew | logged; the token is re-signed once |

In the container, the helper exits non-zero and the SDK reports a generic
credential error. The reason is in the platform log and on the step run, the same
way Bedrock failures are surfaced today.

## 10. Security

- **What the agent holds.** One-hour credentials for the roles its step was given,
  readable in its container like anything else there. That is the intended boundary:
  whatever the agent may do through a tool, it may do with the credentials, so hiding
  them buys nothing. A credential that outlives the session and works from anywhere
  is what this design removes.
- **The token never leaves Rails.** It is signed and spent in the same request.
- **Confused deputy inside Flow.** `sub` and the tags come from the session's own step
  run. The endpoint takes only a role name, checked against the step's resolved set.
- **Replay.** A 5-minute `exp`, a `jti` per token, and the token is never exposed.
- **Signing key compromise.** Whoever holds the private key can mint a token for any
  issuer on the instance. The keys are encrypted at rest, rotated on a schedule, and a
  compromised key is retired by removing it from the JWKS.
- **Logs.** Vended secret keys and session tokens are added to the session's
  redaction list (`Sessions::SecretRegistry`) before they are returned, as
  `get_config_item` does.
- **Data exposure belongs to the workflow, not the credential.** A Slack-triggered
  step that replies in a thread gives everyone in that channel what the role can
  read. The user-facing page should say so, and recommend roles and database users
  scoped to non-sensitive data.

## 11. Rollout

1. **Spike** against a real AWS account, settling the points in §12.
2. **Build** behind `aws_oidc` (`config/feature_flags.yml`: `kind: release`,
   `scope: company`, `default: false`, `client: true`).
3. **Early access** for the team in §1, which asked to try it. Their role then only
   needs its trust principal changed.
4. **Document and release**: a portal page under integrations and its
   `docs/user-guide/` copy, a changelog entry, and this document marked built.

## 12. Open questions for the spike

1. Which claims IAM accepts as condition keys for a generic OIDC provider. The design
   assumes `aud` and `sub` only and puts everything that matters into `sub`.
2. Whether `CreateOpenIDConnectProvider` still needs a thumbprint for an issuer whose
   certificate chains to a public CA, and what the console asks for.
3. An issuer URL with a path (`/oidc/<issuer_key>`): EKS uses one, so it should
   work. Confirm with ours, including the trailing-slash form STS requests.
4. How long STS caches the JWKS, which sets how early `next` must be published.
5. Sessions on a self-hosted runner: does the credential callback reach Rails through
   the runner's callback proxy as the Bedrock one would?
6. Claude Code settings env with Bedrock on: confirm which `AWS_*` variables the
   agent's shell inherits, and whether `[default]` can be written safely in any
   Bedrock mode.
