# Security review — Federated identity and SSO architecture spine

**Lens:** SECURITY (ad-hoc, added because this spine governs authentication)
**Target:** `docs/planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md`
**Method:** Read-only. Design-level attack walkthrough against the ADs as written, cross-checked
against the current code (`app/models/company.rb`, `app/services/google_omni_auth_service.rb`,
`app/controllers/concerns/auth_concern.rb`, `app/controllers/web/sessions_controller.rb`,
`app/controllers/web/invitations_controller.rb`, `app/state_machines/company_membership_state_machine.rb`,
`db/schema.rb`) and against §10 of
`docs/research/technical-federated-identity-and-sso-provider-research-2026-09-16.md`.

## Verdict

**CONDITIONAL — do not build STAGE-3/ORG-POLICY on this spine as written.** The paradigm (ports and
adapters, Rails as system of record, no `ruby-saml` in-process) is sound, but four of the twelve ADs
have exploitable gaps at the exact seams a reviewer should distrust in a multi-tenant auth system:
the domain-based identity-promotion trust anchor, the append-only session-proof model, the
single-admin policy-change guard, and the sidecar trust boundary. None of these are nitpicks — each
is a path to cross-tenant or cross-account takeover if implemented literally from the current text.

## Findings

### F1 — CRITICAL — AD-3's promotion trust anchor (`email_domain`) is self-asserted, not verified, and public/free-mail domains are not excluded

**Attack.** AD-3 promotes an assertion to an existing user when "the asserting `AuthProvider`
belongs to a company, and the email's domain is that company's verified `email_domain`." But
`Company#email_domain` (`app/models/company.rb:39-40`) has no domain-ownership verification (no DNS
TXT challenge, no admin-mailbox round-trip) — it is a free-text field with a format regex, a
case-insensitive **uniqueness** index, and a small reserved-word blocklist (`RESERVED_DOMAINS`,
`app/models/company.rb:33-37`) that covers vanity strings like `admin.com`/`mail.com` but **not a
single public mail provider** (`gmail.com`, `outlook.com`, `yahoo.com`, `icloud.com`, …). Company
creation is platform-admin-only today (`app/controllers/admin/companies_controller.rb`), so the
uniqueness index does stop two companies literally claiming the identical string — but it does
nothing about a company being onboarded (by platform staff, or by a self-hosted operator who is
their own platform admin) with `email_domain = "gmail.com"`.

Once that row exists, STAGE-1's per-company generic OIDC connection is company-admin self-service
(Consistency Conventions: "Org-policy administration is a Pundit policy on `AuthProvider`, scoped to
company `admin` role"). A company admin — who fully controls what their own IdP asserts, since it is
their own connection — configures it to assert `email: victim@gmail.com`, `email_verified: true`
for a victim who never had anything to do with this company. AD-3's three conditions are satisfied
to the letter: `email_verified` is true, the `AuthProvider` belongs to a company, and the email's
domain (`gmail.com`) is that company's verified `email_domain`. `Auth::IdentityResolver` — "the only
writer of `user_identities`" — attaches the attacker-controlled `subject` to the victim's *existing*
Rails `User` row (created whenever the victim first signed up with their real Gmail account,
unrelated to this company). Under AD-6, that new `user_identities` row is a durable, replayable
credential: the attacker's own IdP can now sign in **as the victim**, indefinitely, from a company
the victim never joined.

The uniqueness index is doing real work for the case the prompt asks about (two companies cannot
both claim the literal string `"gmail.com"`) — the actual overlap that matters here is one company
claiming a domain it does not administratively own, which uniqueness cannot detect because it has no
concept of ownership at all.

**Which AD fails:** AD-3 (trust anchor unverified), AD-4 (no constraint on what a company may set as
its own `email_domain` before rows/connections are built on top of it).

**Tightened text.**
> AD-3 addendum: `email_domain` is not usable as an identity-promotion trust anchor until it has
> passed a domain-ownership challenge (DNS TXT record or a confirmation round-trip to an address at
> that domain), recorded as `companies.email_domain_verified_at`. Promotion additionally refuses any
> domain that appears on a maintained public-mail-provider list, verified or not — a company's own
> corporate domain is never `gmail.com`. Until a domain is verified, the company's connections may
> still be used to *sign in*, but never to *auto-promote* an assertion onto a pre-existing user
> outside an explicit, already-authenticated linking flow.

### F2 — HIGH — AD-3 promotion does not distinguish "new user" from "re-attach to an existing account whose real owner may have changed"

**Attack.** AD-3's promotion rule fires whenever a verified, domain-matching assertion arrives for
an email that already has a Rails `User` row, regardless of *why* no `user_identities` row matched
first. The common real case: an employee (`paul@corp.com`) leaves, IT disables their old IdP object
and reassigns the mailbox to a new hire (a routine mailbox-recycling practice, not an edge case). The
new hire's first SSO login is a *new* `(connection, subject)` pair with a verified `email_verified`
claim for `paul@corp.com`. AD-3, read literally, silently attaches the new hire's subject to the
**departed employee's existing account** — inheriting whatever that account carries: other company
memberships if `paul` was multi-company, agent/OAuth credentials, chat/session history, admin roles.
This is identity confusion dressed as convenience, and it needs no attacker at all — ordinary
offboarding triggers it.

**Which AD fails:** AD-3 (no distinction between first-ever assertion for an email with zero
existing identities — safe to treat as JIT provisioning — and an assertion for an email that
already resolves to an account with *other* identities or memberships, which should never be
silently re-homed).

**Tightened text.**
> AD-3 addendum: domain-scoped promotion applies only when the target user has no other
> `user_identities` rows and no company memberships outside the asserting connection's company (i.e.
> genuine first-contact JIT provisioning). An assertion that matches an existing email on an account
> that already has independent identities or memberships is never auto-attached; it is routed to the
> explicit-linking flow (which requires proving the *existing* account first) or, for SCIM-managed
> deprovisioning, requires the admin to explicitly resolve the identity collision.

### F3 — CRITICAL — Step-up does not state that the session identifier rotates, so it is fixable

**Attack.** AD-5 requires step-up to "never sign the user out" and AD-6 models a session as one
`Session` row that accumulates `session_authentication` proofs over its lifetime. Nothing in AD-6
says the session's bearer token (the thing whose digest is stored, and whose plaintext lives in the
cookie) is **rotated** when a proof is appended — only that a new `session_authentication` row is
written. Read literally, the token minted at initial sign-in remains the live credential for the
entire session, including through every subsequent step-up.

That is a textbook session-fixation setup applied to privilege escalation: an attacker who gets a
victim's browser to hold an attacker-known session token *before* step-up (a fixation vector into
the pre-elevated session — a shared/kiosk machine, a subdomain-scoped cookie plant, a token
observed in a referrer or log at the low-privilege stage) does not need to defeat SSO at all. They
wait. When the victim later performs the company's required step-up (e.g. completes SAML/Entra to
satisfy an SSO-only policy), the *same* session row gains the proof, the token is unchanged, and the
attacker — still holding that token — now has a fully step-up-satisfied session for the company,
without ever proving the strong method themselves.

**Which AD fails:** AD-6 (silent on token rotation; "append" is described only at the proof-row
level, not the bearer-credential level).

**Tightened text.**
> AD-6 addendum: the session's bearer token is rotated on **every** successful authentication event
> that appends a `session_authentication` — not only at initial sign-in. `SessionService#append_proof`
> issues a new token for the existing `Session` row (same id, same audit history, same
> `session_authentications`), invalidates the previous token's digest immediately, and resets the
> cookie. This preserves AD-5's "no ping-pong, no forced sign-out" property while closing fixation
> across step-up. Initial sign-in also calls the framework's session-reset primitive so a
> pre-authentication token is never carried into an authenticated session either.

### F4 — HIGH — The append-only proof model has no way to invalidate a proof without disabling the method for everyone, so a real "prove harder" tightening event has no effect on standing sessions

**Attack.** AD-6's intersection check is `session's appended proofs ∩ company's currently-enabled
rows`. This correctly handles the one tightening event AD-6 names explicitly — disabling a row voids
its proofs immediately. But the *unit* of revocation is the `AuthProvider` row's `enabled` flag, and
that is too coarse for the tightening events that actually happen in practice without anyone wanting
to kill the method outright:

- A generic-OIDC or SAML connection's client secret is rotated after a suspected leak. The
  `auth_provider` row's id and `enabled` flag are unchanged, so every `session_authentication` ever
  recorded against that row — including ones proved under the *leaked* secret, by whoever had it —
  continues to satisfy AD-6's intersection forever. Rotating the secret was supposed to be the
  remediation; it revokes nothing already granted.
- An admin decides "everyone re-proves now" (post-incident hygiene) without wanting to permanently
  retire the method. There is no lever for this that doesn't also block all new logins via that
  method for the duration.

This is exactly the "proof obtained under a policy that has since tightened still satisfies the
company" bug the design should be checked for: AD-6 closes it only for the single case where
tightening happens to coincide with `enabled → false`.

**Which AD fails:** AD-6 (proof validity is keyed only to the row's `enabled` flag, not to any
notion of *when* the row's trust configuration last materially changed).

**Tightened text.**
> AD-6 addendum: each `auth_providers` row carries a `proofs_valid_since` timestamp, bumped whenever
> its trust configuration changes materially (secret/cert rotation, issuer/tenant change, or an
> explicit admin "force re-proof" action) as well as on `enabled` toggles. The intersection test in
> AD-6 additionally requires `session_authentication.created_at >= auth_provider.proofs_valid_since`
> for that row's proof to count. This lets an admin invalidate standing proofs from a compromised
> configuration without disabling the method for future logins.

### F5 — CRITICAL — AD-7's "an existing active admin" is singular: one compromised admin can downgrade the whole company to its weakest already-proved method, unilaterally, without tripping the guard or needing a super_admin override

**Attack.** AD-7 refuses a policy change that would leave the company's effective set "without any
method an existing active admin has already proved." It says *an* admin — not "every currently
active admin," not "a quorum." Combine that with AD-4: password is a **seeded row on every
company**, almost always proved by whichever admin first stood the company up, long before SSO was
configured. An attacker who compromises any single admin account (credential stuffing against that
admin's password — which is virtually guaranteed to be an enabled, proved method somewhere in the
company, per AD-4's seeding) can:

1. **Downgrade, not just avoid lockout.** Disable every strong method (SAML, Entra, passkey),
   leaving only `password` enabled. AD-7's guard is satisfied trivially — the attacker's own
   compromised admin account is itself "an existing active admin [who] has already proved" password.
   No super_admin override is needed; the guard was never designed to stop the actor who already
   holds a valid proof for the fallback method. An SSO-only policy the company relied on is now
   silently gone, and every other member (and every future invitee, per AD-11) is funneled onto the
   weakest configured method — the one the attacker just used.
2. **Strip other admins without stripping themselves.** Because AD-7 checks the company's aggregate
   effective set, not each admin's individual standing, the attacker can disable whichever method
   the *other* admins actually use (say, Google, if they never set a password) while keeping
   password enabled — since they themselves proved password, AD-7 does not object. The other admins
   are now locked out (no password identity to fall back to) while the attacker retains sole access,
   with no real-time signal to anyone else: AD-7's audit trail ("Audit: policy changes... are
   recorded through the existing `Audited::Audit` trail") is forensic, not preventive, and nothing
   requires out-of-band notification before the change takes effect.

The spine's own Open Question #3 ("Does `super_admin` bypass AD-5 entirely, or only the AD-7
activation guard?") is adjacent but not this bug — this attack doesn't touch the super_admin
override at all; it walks straight through AD-7 as written.

**Which AD fails:** AD-7 ("an existing active admin," singular, with no per-admin retention
requirement and no dual-control on narrowing changes).

**Tightened text.**
> AD-7, replace the guard: a policy change that narrows the effective set is refused unless (a)
> every currently active admin — not just one — retains at least one already-proved method in the
> resulting set, or the change is accompanied by (b) confirmation from a second admin (or the
> platform `super_admin` override, which remains audit-logged) and (c) an out-of-band notification
> to every other active admin sent *before* the change takes effect, with a short cooldown before it
> applies. A single admin, alone, can never remove another admin's only proved method.

### F6 — CRITICAL — Neither AD-8/AD-9 (the sidecar) nor AD-3/STAGE-1 (Entra) state that Rails cross-checks the tenant/connection identity embedded in an incoming assertion against the `auth_provider` row the login flow was for — the classic multi-tenant confused deputy

**Attack, sidecar variant.** AD-8/AD-9 establish *that* SAML is bridged to OIDC by a shared Polis
sidecar and *that* its admin API is cluster-internal — but neither states the one property that
actually closes cross-tenant impersonation: that the OIDC token Polis hands back to Rails carries a
tenant/connection claim, and that `Methods::Oidc#complete` verifies that claim against the specific
`auth_provider` row the flow was initiated for, not merely that the token is validly signed by
"our" sidecar. If the adapter's check is "signature verifies, issuer is Polis" and nothing more, then
any company with its own legitimate SAML connection on the same shared sidecar — who fully controls
what their own IdP asserts — is one misrouted or replayed callback away from completing a login that
Rails accepts as if it came from a *different* company's connection. Signed-state alone (`Auth::State`
— signed, short-TTL, single-use, user-pinned) proves "this callback matches a request we issued," not
"the assertion inside it actually originated from the tenant that request named" — those are
different checks, and only the second one closes the deputy problem. AD-3's domain-scoped promotion
check is not a backstop here either: it only applies once identity resolution has already decided
*which company's connection* an assertion belongs to, which is precisely the fact in question.

**Attack, Entra variant (same bug, different door).** Research §10 item 2 names this exactly:
"Validate issuer per connection... pin `iss` and the `tid` claim to the company's connection row."
No AD carries this. Microsoft's signing keys are shared across the multi-tenant `common` endpoint,
and STAGE-1 explicitly wants "multi-tenant + admin consent" Entra connections. If the adapter
verifies only that a token is validly signed by Microsoft and reads `oid`/`email` off it, then any
external Entra tenant — including one an attacker stands up for free — can mint a token that is
technically valid and route it at a company's login/callback; without an explicit `tid`-pinning
check against the specific `auth_provider` row's registered tenant, the company's SSO connection
would accept assertions from a tenant it never consented to.

Both variants are the same root cause: an AD that says "we trust assertions from this shared bridge"
without an AD that says "and we verify which tenant inside that shared bridge this specific assertion
came from, against the specific row it claims to satisfy."

**Which AD fails:** AD-8/AD-9 (sidecar trust boundary silent on tenant-claim verification); no AD
covers Entra `iss`/`tid` pinning at all (a gap, not just an implicit omission — see also F9 below).

**Tightened text.**
> New AD (or AD-8 addendum): every assertion bridged through the sidecar or accepted directly as OIDC
> carries an explicit tenant/connection identifier in its signed claims. `Methods::Oidc#complete`
> verifies that identifier against the specific `auth_provider` row resolved from the inbound
> `Auth::State`, in addition to verifying the token's signature and issuer, before invoking
> `Auth::IdentityResolver`. A mismatch is treated as a failed authentication, not routed to any
> fallback. For Entra specifically: `iss` and `tid` are pinned to the value captured at
> admin-consent time for that connection; a token from any other tenant is rejected regardless of
> signature validity.

### F7 — MEDIUM — AD-6's OR-only intersection model cannot express additive MFA

**Attack (functional gap, amplifies F4/F5).** AD-6 satisfies a company when the intersection of
proofs with enabled rows is *non-empty* — any one proved, enabled method suffices. There is no way
to express "SSO **and** TOTP," only "SSO **or** TOTP" (both as independent, enabled rows). A company
that wants a genuine second factor on top of SSO or password cannot express that requirement in this
model: enabling `passkey`/`totp` alongside `password` does not force its use if `password` alone
already satisfies the intersection; the only way to make TOTP mandatory is to disable everything
else, at which point a 6-digit shared-secret code — designed as a *second* factor, not a standalone
identity proof — becomes the company's sole login credential. Combined with F4/F5, an organization
that believes it has "required MFA" may not actually have it, and a downgrade attack (F5) is even
easier to execute unnoticed because there is no drop from "two factors" to "one" to alert on — the
model has no such distinction.

**Which AD fails:** AD-6 (models only membership-in-a-set, not composition of proofs).

**Tightened text.**
> AD-6 addendum: a company's policy may name a required *set* of proofs (e.g. `{sso, totp}`), not
> only a required *union*. The intersection test becomes: the company is satisfied when, for at
> least one policy-defined "satisfying combination," every method in that combination has a proof in
> the session. The single-method union remains the default combination for policies that don't opt
> into composition.

### F8 — HIGH — AD-11/AD-12 govern policy at invitation entry but leave the invitation token itself exactly as fragile as today: first redeemer attaches the credential

**Attack.** AD-12 replaces `password_digest.present? || provider.present?` with
`user.user_identities.any?` — a correct mechanical fix for the AD-12 "Prevents" clause it names. But
neither AD-11 nor AD-12 touches the token itself. Per the current code this spine cites directly
(`invitations_controller.rb:27,114`) and per the research report's own framing (§10 item 6, contrasting
invitations with magic links): invitation tokens are long-lived and reusable-until-consumed. The
`show` action parks the token in session on a bare GET and branches to a "signup" variant whenever
the invited `User` row has no identities yet — at that point, *whoever holds the link* can be the one
who sets the account's first credential (a password, via `Web::InvitationsController#signup`, which
takes only `name`+`password`, no proof of mailbox control at redemption time). If the link leaks
before the real invitee opens it — forwarded mail, a corporate mail-relay log, a link-preview/unfurl
bot, a shared inbox — the first redeemer becomes the account, is signed in as the invitee, and the
membership is accepted under their control. The real invitee, arriving later, either finds themselves
looking at "wrong_account" (if the attacker is still signed in on that browser) or simply cannot use
the invite anymore. AD-11's "same AD-5 gate" protects the *company's SSO policy* from being
bypassed via invitations; it does nothing about the *identity* being attached being the wrong one.
This is the sharper, invitation-specific form of the account-attachment risk the review brief asks
about in item 5, and it is unchanged by this spine despite the spine explicitly touching this file.

**Which AD fails:** AD-11 (governs policy satisfaction, not token/credential-attachment integrity);
AD-12 (fixes the credential-existence *test* but not the credential-attachment *race*).

**Tightened text.**
> AD-11 addendum: the first credential ever attached to an invited user's row (password set, or an
> OAuth/OIDC identity linked) is provisional until confirmed by a second factor sent to the invited
> address itself — e.g. the signup/link action re-sends a short-TTL, single-use confirmation code or
> link to the invited email, and the membership is not accepted (and the credential is not treated as
> a durable proof for AD-6 purposes) until that confirmation completes. This holds even though the
> original invitation token proved mailbox control *at send time* — it does not prove it *at
> redemption time*, arbitrarily later, which is the actual gap.

### F9 — MEDIUM (completeness gap) — Research §10 item 2 (`iss`/`tid` pinning) is not carried by any AD

Called out on its own because it is a documentation defect independent of F6's exploit path: the
research document explicitly lists issuer/tenant pinning as a requirement that "applies no matter
what we choose." No AD in the spine states it, and the Capability→Architecture Map binds STAGE-1 only
to AD-2/AD-3 — neither of which mentions `iss`/`tid`. Fold into F6's fix, but flag that the
Capability→Architecture Map should list the new AD against STAGE-1 explicitly, not only STAGE-3.

### F10 — MEDIUM (completeness gap) — Research §10 item 6 (magic-link hygiene) is roadmap prose, not an invariant

The research doc states magic links need "5-15 minute expiry, hard single-use enforcement, and
session-fixation-safe redemption" as a requirement that holds regardless of vendor choice. The spine
mentions magic links only in the Capability → Architecture Map ("STAGE-2 passwordless... magic
links," governed by AD-2/AD-6) and in the Stack/Structural Seed as an adapter kind — no AD actually
commits to single-use, TTL, or fixation-safe redemption for magic-link tokens. Once STAGE-2 is built
by someone who has not read the research doc's prose (the normal way an AD-driven build proceeds),
nothing enforces this. This should become an explicit AD-6 (or new AD) clause, not left to be
inherited by implication from STAGE-0's session-fixation fix in F3.

## Summary table

| # | Severity | One-line |
|---|---|---|
| F1 | CRITICAL | `email_domain` is an unverified, un-blocklisted trust anchor for AD-3 promotion — a company can claim a public mail domain (or any domain it doesn't own) and its own admin-controlled OIDC connection can then mint identity-attaching assertions for arbitrary victims |
| F2 | HIGH | AD-3 promotion re-attaches a new IdP subject to a pre-existing account on ordinary mailbox reassignment (offboarding), with no distinction from genuine first-contact JIT provisioning |
| F3 | CRITICAL | AD-6 never states that the session token rotates on step-up, leaving step-up fixable: an attacker who fixates a pre-elevated session inherits the victim's step-up proof for free |
| F4 | HIGH | AD-6's proof validity is keyed only to `enabled`, so secret rotation / "reprove everyone" after an incident invalidates nothing already granted — proofs outlive the policy that would tighten them |
| F5 | CRITICAL | AD-7's guard checks for *one* admin's proof, not every admin's — a single compromised admin can unilaterally downgrade the company to its weakest already-proved (often seeded, password) method, or strip other admins' access, without tripping the guard or needing super_admin |
| F6 | CRITICAL | Neither the sidecar (AD-8/AD-9) nor Entra/OIDC (no AD) require verifying the tenant/connection claim inside a bridged or federated assertion against the specific `auth_provider` row it claims to satisfy — the classic multi-tenant SSO confused deputy, open on two fronts |
| F7 | MEDIUM | AD-6 can only express OR-composition of proofs, not AND — "require SSO and TOTP" is not representable, amplifying F4/F5 |
| F8 | HIGH | AD-11/AD-12 fix the credential-existence test but not the invitation token's first-redeemer-wins race; whoever holds the (long-lived, reusable) invite link attaches the account's first credential |
| F9 | MEDIUM | Research §10's `iss`/`tid`-pinning requirement is not carried by any AD (same root cause as F6) |
| F10 | MEDIUM | Research §10's magic-link single-use/TTL/fixation-safe-redemption requirement is not carried by any AD |

## Note on scope

This review is confined to the ADs as text — it does not evaluate Ory Polis's own implementation
(its OSS multi-tenancy is already an Open Question in the spine, #1) or the `webauthn`/`rotp`/
`openid_connect` gems' correctness; those are supply-chain and implementation concerns for later
gates, not design-level findings against this spine.
