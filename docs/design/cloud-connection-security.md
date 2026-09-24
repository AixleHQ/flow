# Cloud Connection Security — notes for a reviewing security team

**Audience:** the security or cloud team of an organisation whose developers want Aixle
to run Claude Code against the organisation's **own** Amazon Bedrock account.
**Companion:** `docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md`
(the engineering design). This page is the part worth handing to a reviewer, and it
describes what the platform does today.

---

## 1. What a connection can do

A connection carries **one developer's own access**, nothing more. On the Identity Center
path (§3a) every AWS credential Aixle uses is a role credential for the permission set you
assigned to that developer, so the permission set *is* the grant: whatever it allows,
sessions using the connection can do. Scope it to Bedrock.

The platform uses a connection for three things:

- the developer's agent sessions invoke Bedrock models (Claude Code runs in the session's
  container);
- when the developer opens a page with a model picker, the platform lists the account's
  inference profiles (`bedrock:ListInferenceProfiles`, cached for a day) so the picker
  offers only what the account has; a permission set without that action leaves the
  picker on a static list;
- when the developer runs the connection health check, the platform makes one
  `bedrock:InvokeModel` call capped at a single output token and shows AWS's own error
  message if it fails.

A permission set that lets Claude Code work on Bedrock needs:

- `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`
- `bedrock:ListInferenceProfiles`, `bedrock:GetInferenceProfile` (model discovery; without
  the latter every new model costs an extra round-trip while the CLI retries with the
  other request shape)
- `aws-marketplace:ViewSubscriptions`, `aws-marketplace:Subscribe`, conditioned on
  `aws:CalledViaLast = bedrock.amazonaws.com` — this is what lets Bedrock accept a first
  call for an Anthropic model, and it cannot subscribe you to anything else

You can narrow the `Resource` list to specific inference-profile ARNs to restrict which
models are reachable.

## 2. Where prompts go

**Prompts and completions travel from the developer's session container directly to
Bedrock.** They do not pass through Aixle's application servers. What crosses our
infrastructure is the credential exchange described below, plus the usual platform
metadata (token counts, session identifiers).

Bedrock's own invocation logging is off by default and, if you enable it, writes to
**your** account. We never enable it.

Data retention is entirely yours: Bedrock retention modes are configured on your account
or per Bedrock project. Note that Claude Fable/Mythos-class models require the
`provider_data_share` retention mode and show as unavailable without it — that is an AWS
and Anthropic arrangement, not ours.

## 3. The two connect paths, and the trust each creates

Both start in the same place: the developer signs in to Claude Code from their Aixle
profile, in a terminal embedded in the page, and chooses Amazon Bedrock in Claude Code's
own setup.

### 3a. IAM Identity Center sign-in — the managed path

When the developer picks this, the page opens a connect step. The developer enters your
Identity Center start URL and region, signs in to **your** Identity Center through the
OAuth 2.0 device authorization grant, and approves in their own browser. They then choose
one of the account and role pairs their permission sets grant; only pairs this
authorization actually listed are accepted, and nothing is stored before that choice.
Nothing is created in your account; the developer gets exactly the permission set you
already assigned them.

**Read this part before approving it.** The device-code grant is a published
credential-phishing technique, and PKCE-by-default in AWS CLI 2.22.0 was AWS's mitigation.
We are aware that this flow resembles the attack, and we do not pretend otherwise:

- What makes the attack work is a stranger getting a victim to approve a code the stranger
  initiated. Here the developer initiates the flow themselves, in your product, for your
  Identity Center.
- A connection is refused unless the person who approved it is the person who started
  it: before anything is stored, the platform asks AWS STS who the chosen role's
  credentials act as, and the Identity Center user name in that answer has to be the
  platform user's email (compared without regard to case). A link forwarded to someone
  else therefore connects nothing. If your Identity Center user names are not email
  addresses, this path refuses every connection.
- PKCE is not usable in our case: its callback must open on the machine running the client,
  and the client runs in a headless container. That is why the device grant is used at all.
- You will see `CreateToken` events in CloudTrail with
  `grantType=urn:ietf:params:oauth:grant-type:device_code`. If you alert on those, expect
  them from developers who connect this way. If your policy blocks the device endpoint,
  this path is unavailable.

What we store, encrypted: the OIDC client registration, the refresh token, and the current
access token. Identity Center caps client registrations at **90 days**, after which
refresh is impossible and the developer must sign in again — we cannot extend that.
Access tokens are one hour and refreshed server-side.

The session container never logs in to Identity Center and never receives this material.
Its AWS profile names a `credential_process` helper that asks our vending endpoint for
role credentials, authenticated by a key derived from the session; the endpoint refuses a
session that is no longer active.

Revocation: the developer can disconnect in Aixle, which deletes the stored registration
and tokens. On your side, revoke the developer's Identity Center session or unassign the
permission set.

### 3b. Keys entered in Claude Code's own setup

Claude Code's Bedrock setup also accepts a Bedrock API key, or a long-term IAM access key
pair. Aixle keeps what Claude Code wrote, encrypted, and restores it into the settings of
the developer's later sessions — so these keys are present inside every session container
of that developer. Temporary credentials (a key pair that comes with a session token) are
not kept. Nothing is created in your account and no role is assumed. The platform itself
never calls AWS with these keys: model listing and the health check work only on the
Identity Center path.

We flag this as the least preferred path for a reason: a long-term Bedrock API key can be
created with **no expiry at all**, and short-term keys are computed client-side so their
creation is invisible in CloudTrail (their *use* is logged, and both can be constrained
with `bedrock:CallWithBearerToken` / `bedrock:BearerTokenType` — deny both the `bedrock:`
and `bedrock-mantle:` namespaces to close it fully). Long-term access keys stay valid
until you rotate them.

Revocation: delete or rotate the key.

## 4. Attribution — what you will see in your own logs

- On the Identity Center path, sessions call AWS with the developer's own Identity Center
  role credentials, so CloudTrail records each call under that developer's assumed-role
  session. Its session name is their Identity Center user name — the same name the
  connect step checked against their Aixle email.
- Bedrock invocations are ordinary `bedrock:InvokeModel` events in your account, in the
  region the connection names.
- Keys from §3b are attributed to the principal or API key they belong to.

## 5. What lives where

| | Stored by us | Stored in your account | In the developer's container |
|---|---|---|---|
| Identity Center registration + tokens (3a) | yes, encrypted | nothing | no |
| Bedrock API key or long-term access keys (3b) | yes, encrypted | nothing | yes, in Claude Code's settings for the session |
| Short-lived AWS role credentials (3a) | no | n/a | yes, ≤1 hour, never written to disk by us |
| Prompts and completions | no | only if you enable Bedrock invocation logging | in the session, as the agent's own working state |

A connection also belongs to the one company it was made in. A developer who works for
several companies on our platform connects each separately, and a session can only vend the
connection of the company that session is billed to — so your grant is never reachable from
work done for someone else.

## 6. Questions we expect, answered

**Can a developer use this to reach non-Bedrock services in our account?** Only what the
permission set you assigned allows: on the Identity Center path, sessions get exactly that
permission set's role credentials. Scope the permission set to the actions in §1.

**Can Aixle use the grant when the developer is not working?** Role credentials are vended
only to that developer's active sessions; a finished session cannot vend. Outside
sessions, the platform uses the connection only for the two calls in §1, and only when the
developer is using the product: listing inference profiles for their model picker, and the
health check they run.

**What happens if we rotate or revoke?** Unassigning the permission set makes the next
credential request fail. Revoking the developer's Identity Center session stops new
credentials once the access token we hold expires (it is at most an hour old). Credentials
already handed to a session expire within the hour. A connection whose registration has
expired, or that holds no usable token, is refused before the next session starts, with a
prompt to reconnect; any other failure surfaces when the session asks for credentials, and
the health check shows AWS's own error.

**Can we see what it would cost before committing?** Yes — Bedrock spend is ordinary AWS
billing in your account, draws down your EDP/PPA commitments at full value, and can be
paid with AWS credits. Nothing routes through our billing.
