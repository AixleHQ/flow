# Adversary Review — Federated Identity and SSO Architecture Spine

**Reviewer lens:** BMAD reviewer-gate #2, ADVERSARY (read-only).
**Method:** for each seam, construct two units one level down that each obey every AD to the
letter yet build incompatibly. Every pair found is a hole; each hole gets a proposed AD tightening.
**Target:** `docs/planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md`

**Verdict:** NOT READY — 8 holes found, 3 of them (H3, H5, H6) are ordering/ownership conflicts
that would ship *silently wrong* code even from a careful, spec-literate builder; H1 is a live
account-takeover regression of the exact class AD-3 exists to close.

---

## H1 — `email_verified` is a boolean nobody defines for the absent case (CRITICAL)

**Seam:** AD-3 ("promote an assertion... only when... the provider asserts `email_verified`") vs.
two `Methods::Oidc` instances for Microsoft and a generic per-company connection.

AD-3's promotion gate is written as if `email_verified` is always present and boolean. It isn't:
many generic OIDC IdPs (bespoke Keycloak realms, some Okta custom app integrations, self-hosted
authelia/Zitadel setups a customer might point a "generic OIDC" `AuthProvider` row at) never emit
the `email_verified` claim at all — the field decodes as `nil`, not `false`.

- **Builder A** treats "the provider asserts `email_verified`" as `assertion.email_verified == true`
  strictly. `nil`/`false`/missing all fail promotion. Fully literal reading of AD-3's words.
- **Builder B** notes that AD-3's promotion gate already requires the `AuthProvider` to belong to
  the company *and* the email domain to match that company's verified `email_domain` — and reasons
  that for a **company-scoped generic connection specifically** (as opposed to a public multi-tenant
  provider like Google), the admin who configured the connection already vouches for it, so an
  *absent* claim (not an explicit `false`) is treated as verified. Also textually "compliant": AD-3
  never disambiguates absent-vs-false, and Builder B's reading only relaxes the case the text is
  silent on.

Builder B's reading reopens exactly the takeover vector AD-3 exists to close: a generic OIDC
`AuthProvider` pointed at any IdP with open self-registration and no `email_verified` claim lets
anyone register `attacker@victim-company.com` and get silently promoted into the victim's `User`
account on first login. Both builders pass a code review scoped to AD-3's literal text.

**Fix — tighten AD-3:**
> `Auth::Assertion#email_verified` is a required, normalized boolean produced by the adapter, never
> passed through raw. An adapter that cannot obtain an explicit `true` claim from the provider
> (missing, `false`, or unsupported) MUST set it to `false`. Promotion checks `== true` only. No
> adapter, no matter how narrowly scoped the connection, may treat "claim absent" as "verified."

---

## H2 — AD-3's `oid` aside is not binding on what an adapter actually stores as `subject`

**Seam:** same two `Methods::Oidc` instances, subject storage.

AD-3's normative rule is "the subject is the provider's immutable identifier"; `(sub / Entra oid)`
is a parenthetical example, not a mapping table. `Auth::Assertion.subject` is the field of record
(per the Consistency Conventions table), but nothing pins *which claim* populates it per `kind`.

- **Builder A** writes `Methods::Oidc` to special-case `kind == "microsoft"` and pull the `oid`
  claim explicitly out of the decoded ID token, because that's the one example AD-3 names.
- **Builder B** writes `Methods::Oidc` to stay kind-agnostic (consistent with AD-2's whole point —
  one adapter, no per-provider branching) and plumbs through whatever the underlying gem's
  normalized `uid` already is for every kind, including Microsoft. Whether that `uid` happens to be
  `oid` or a pairwise/app-scoped `sub` is a library-configuration detail the spine never pins.

If Builder B's gem default is not `oid`, `user_identities.subject` silently stores a claim that can
rotate per-app-registration or be pairwise-per-client, defeating the "immutable identifier" property
AD-3 is built on, while never touching a line AD-3 forbids.

**Fix — tighten AD-3:** add an explicit `kind -> claim` table to the Consistency Conventions (e.g.
`microsoft: oid`, `google: sub`, `oidc (generic): sub` unless the connection's discovery document is
configured otherwise), and require every adapter to assert the source claim by name in its test
double, not just assert "subject is present."

---

## H3 — Step-up and the session-proof model can be satisfied by two different session lifecycles

**Seam:** AD-5 (step-up) vs. AD-6 (session proof model).

AD-6 says "A `Session` row per sign-in... Each successful authentication appends a
`session_authentication` row." AD-5 says step-up "redirects to step-up re-authentication; it never
signs the user out." Step-up *is* a successful authentication (a fresh `#complete` on an adapter) —
so does it produce a new `Session` row ("per sign-in," literally) or append to the session already
referenced by the still-valid cookie?

- **Builder A** reads "per sign-in" literally: step-up completion mints a **new** `Session` row
  (new token digest, new cookie), because step-up is, mechanically, a sign-in. To honor "proving a
  second method never invalidates the first," it copies forward the prior session's
  `session_authentication` rows onto the new one.
- **Builder B** reads "it never signs the user out" as governing the `Session` row too: the browser
  cookie/token never rotates on step-up, so step-up **appends** a `session_authentication` to the
  existing `Session` row; "per sign-in" refers only to the original login (`POST /login` /
  OAuth callback with no prior valid cookie).

Both cite different clauses of the same AD. The consequences are not cosmetic: Builder A rotates the
token on every step-up (any other tab/request racing on the old cookie mid-step-up now references an
orphaned `Session` row — is it revoked, or just abandoned?), and a "your active sessions" security
page fragments one continuous browser session into a **chain** of `Session` rows, breaking
straightforward revocation ("revoke this session" now means "revoke this fragment," leaving earlier
fragments in an undefined state). Builder B keeps one row per login until logout — clean revocation,
no orphaned tokens, but requires the spine to have actually said so, which it doesn't.

**Fix — tighten AD-6:**
> Step-up NEVER creates a new `Session` row. It appends a `session_authentication` to the `Session`
> row already identified by the current, unexpired session cookie. A new `Session` row (and cookie)
> is minted only when no valid session cookie is presented — i.e. only by an actual `POST /login` /
> OAuth callback with no prior session. Token rotation on privilege change is explicitly out of
> scope for step-up.

---

## H4 — "Voids its proofs immediately" doesn't pin resolver-on-read vs. cache vs. sweep

**Seam:** AD-6 revocation semantics.

AD-6's mechanism (session proofs ∩ *currently enabled* rows) is immediate **only if** the
intersection is always computed against a live read of `auth_providers.enabled`. Nothing in AD-6 (or
AD-4, which owns `PolicyResolver`) forbids caching the effective set, and the codebase already has a
precedent for exactly this shape of optimization: `AuthConcern#current_membership` memoizes
per-request with `@current_membership ||=`.

- **Builder A** extends that exact idiom: `@effective_set ||= Auth::PolicyResolver...` memoized
  per-request only. "Immediately" holds to within one request.
- **Builder B**, worried about `PolicyResolver#allowed_for` running on every request for every user
  of a large company, caches the company's effective set in `Rails.cache` with a short TTL (a
  completely ordinary Rails pattern, invalidated by an `after_commit` on `AuthProvider`). Nothing in
  AD-4/AD-6 says "no cache wider than one request." If the invalidation callback misses a code path
  (e.g. a bulk toggle, an admin API that updates via `update_all`), "immediately" quietly becomes
  "within the TTL," i.e. an attacker window after a provider is disabled specifically *because* it
  was compromised.

A third variant answers the review prompt's explicit question directly: a builder could instead
implement voiding as a **background sweep** that tombstones `session_authentication` rows when a
provider is disabled (denormalizing "still valid" onto the proof row itself, since the ERD draws no
`revoked_at`/validity column there today) rather than joining live against `auth_providers.enabled`
at read time. That has its own commit-to-sweep-execution window. AD-6 doesn't rule any of these out.

**Fix — tighten AD-6:**
> The enabled-intersection is computed against a live read of `auth_providers.enabled` at the moment
> of the request; it is never served from a cache or memo that outlives the request, and
> `session_authentication` rows carry no denormalized validity flag. Voiding a provider's proofs is
> a property of the *read path*, not a write the disable action performs elsewhere.

---

## H5 — AD-7's guard covers "enable/disable," not "delete," and isn't proven atomic across rows

**Seam:** AD-4 effective set vs. AD-7 prove-before-enforce, exactly as the brief asks: does a policy
edit and a connection deletion race to an empty effective set anyway?

AD-7's rule text: "A policy change that would leave a company's effective set without any method...
is refused." AD-4's mechanism is "Admins **toggle** `enabled`." Neither AD ever mentions deleting an
`auth_providers` row outright (removing a misconfigured SAML/OIDC connection is a distinct, very
plausible admin action — "remove this connection," not "disable this connection").

- **Builder A** wires the AD-7 guard as a `before_save` callback on `AuthProvider`, triggered when
  `enabled` flips. Deleting a row is a separate action in a separate service/controller
  ("disconnect SSO connection") that never touches that callback — AD-7's text says "a policy
  change," and deleting the row isn't editing a policy flag, it's removing the resource the flag
  lives on. Fully defensible reading.
- **Builder B** treats deletion as just another way to shrink the effective set and wires the same
  guard into `before_destroy`.

Builder A's system lets an admin delete the company's only enabled SSO connection outright with **no
guard at all**, instantly emptying the effective set — including, per AD-6, voiding the very proof
the deleting admin is currently relying on to be in the admin surface, since that `session_authentication`
now points at a row that no longer exists. That is a same-transaction, self-inflicted, unrecoverable
company lockout (no company admin can now satisfy any company's effective set to fix it — only a
platform `super_admin` override, per AD-7, can, and Open Question 3 admits that override's scope is
still undecided).

Even with **both** actions guarded (Builder A patched to add the same check to destroy), the brief's
race is still open: AD-7 never specifies the locking granularity. A guard implemented as a per-row
check-then-act (`auth_provider.with_lock { ... }`) does not prevent two concurrent admin actions on
**different rows of the same company** — Admin 1 disables Provider X (passes, because Provider Y is
still enabled+proven in the pre-image it read) concurrently with Admin 2 deleting Provider Y (passes,
because Provider X is still enabled in *its* pre-image) — both commit, and the company lands on an
empty effective set despite every individual guard passing. Nothing in AD-7 mandates a company-level
lock spanning the check-and-act; per-row locking is the "obvious," cheaper implementation and AD-7
doesn't forbid it.

**Fix — tighten AD-7:**
> The guard applies to every mutation of a company's `auth_providers` rows that can shrink the
> effective set — `enabled: false`, and destroy — not only an `enabled` toggle. The check-and-act is
> performed under a lock scoped to the **company**, not the row (e.g. `company.with_lock` or a
> Postgres advisory lock keyed by `company_id`), held for the duration of the mutating transaction,
> so two concurrent admin actions on different rows of the same company cannot both pass a
> stale-pre-image check.

---

## H6 — SCIM provisioning needs to write `user_identities`, and nothing says how

**Seam:** AD-10 (SCIM writes are AASM events) vs. AD-3 (`Auth::IdentityResolver` is the only writer
of `user_identities`).

SCIM provisioning creates `User`/`CompanyMembership` rows for people who have never logged in
interactively. To be useful at all, it must also record *some* binding of "this SCIM-provisioned user
corresponds to subject X at connection Y" — i.e. a `user_identities` row — so that when that person
later actually signs in via SSO, `Auth::IdentityResolver` finds the pre-provisioned user instead of
creating a duplicate. AD-10 legitimizes SCIM as calling AASM events directly for membership state;
it says nothing about `user_identities`, and AD-3's "only writer" rule says nothing about SCIM.

- **Builder A** keeps AD-3's invariant intact: the SCIM service constructs a synthetic
  `Auth::Assertion` (`subject:` the SCIM `externalId`, `email_verified: true` only because the
  connection itself is company-trusted, not because a live claim was asserted) and hands it to
  `Auth::IdentityResolver`, reusing the exact same writer AD-3 mandates.
- **Builder B** notes AD-10 already sets the precedent that SCIM gets a direct, non-standard write
  path into auth-adjacent tables (bypassing whatever service the interactive UI uses for membership
  state), and extends that precedent to `user_identities`: the SCIM provisioning service calls
  `user.user_identities.create!(auth_provider: scim_connection, subject: scim_external_id)` inline,
  next to its AASM `accept!` call, entirely bypassing `Auth::IdentityResolver`.

Builder B's code violates AD-3's literal text the moment it ships, but a reviewer checking only
against AD-10 (which explicitly blesses SCIM's habit of writing directly into state-machine-governed
tables) sees nothing wrong — AD-10 and AD-3 point in opposite directions on the one write SCIM
actually needs to make, and the spine never says which AD wins.

**Fix — tighten AD-10 (or AD-3):**
> SCIM's AASM-event carve-out applies only to `CompanyMembership` state. Any `user_identities` row
> SCIM needs — provisioning, deprovisioning, or externalId rotation — is created by constructing an
> `Auth::Assertion` and calling `Auth::IdentityResolver`, exactly as an interactive adapter would.
> `Auth::IdentityResolver` remains the only writer of `user_identities`, with no exception for SCIM.

---

## H7 — AD-11's gate can't be evaluated at the point the current code accepts an invitation

**Seam:** AD-11 vs. the actual invitation code (read directly, three call sites — the spine's own
"sources" sweep names only one of them).

`app/controllers/concerns/auth_concern.rb:87-106` (`accept_pending_invitation`) is called from
`Web::SessionsController#create` (line 44) and `#omniauth` (line 70) — in **both** call sites, it
runs *before* `sign_in(user)` (lines 52 and 85 respectively). `accept_pending_invitation` itself sets
`session[:current_company_id]` and calls `membership.accept!` (the AASM event) — i.e., under the
current code, **entering the company happens before there is any session to attach a proof to**.

AD-11's rule — "Accepting an invitation passes through the same AD-5 gate... sent to step-up, not
admitted" — requires evaluating "session proofs ∩ effective set," which per AD-6 requires a `Session`
row with an already-appended `session_authentication`. That doesn't exist yet at the point
`accept_pending_invitation` currently runs, because `sign_in` (which must now be the point that
creates the `Session` and appends the proof) hasn't executed.

- **Builder A** reorders the call sites: `sign_in`/session-creation moves *first*, so by the time
  `accept_pending_invitation` runs, the session already carries the just-completed method's proof;
  `accept_pending_invitation` then calls `Auth::PolicyResolver#allowed_for(membership.company)`
  against that session and only calls `membership.accept!` if it's satisfied, otherwise redirects to
  step-up leaving the membership `invited`.
- **Builder B** keeps the existing order (smaller diff, doesn't touch working login sequencing) and
  instead has `accept_pending_invitation` check "is the method **currently being completed** (not
  yet recorded as a session proof) a member of the invited company's effective set" — a parallel,
  simplified kind-membership pre-check that never touches `session_authentication`/`PolicyResolver`
  at all, because at this point in the request neither exists.

Both claim AD-11 compliance ("it passes through a gate that checks the effective set"), but they
enforce different things. The gap shows up concretely for a multi-company user already signed in
elsewhere in the same browser (an existing `Session` with prior proofs) who then opens an invitation
link: Builder A's ordering lets the *existing* session's accumulated proofs satisfy the new company's
gate with no re-authentication at all (correct — this is exactly what AD-6's "proofs append, never
invalidate" is for). Builder B's ordering can only ever evaluate "the method currently mid-completion,"
so it can never benefit from a prior proof and forces a needless step-up even when the real AD-5 gate
is already satisfied.

This gap is wider than the spine's own sources list suggests: **`app/controllers/web/invitations_controller.rb`
is not in the spine's "code sweep" sources list at all**, yet it has *two more* independent
accept-paths with their own ordering, neither guarded by anything resembling AD-5 today:

- `#accept` (already-signed-in invitee, line 44-58): calls `safely_accept(membership)` (the AASM
  `accept!`) immediately, with zero policy check before or after.
- `#signup` (first-time invitee with no password, no OAuth, line 72-94): sets the user's password,
  saves, calls `safely_accept`, *then* `sign_in` — a **third**, different ordering (accept before
  sign_in again, but this time the "authentication" being proved is the password just set in this
  same request, which doesn't exist as a `session_authentication` until `sign_in` runs after).

Three call sites, three different accept/sign_in orderings, and the spine names only one of them.
Three separate builders patching three separate controllers each pick their own fix.

**Fix — tighten AD-11:**
> AD-11's gate is enforced in exactly one place: a shared `Auth::InvitationGate` (or equivalent)
> called from all three existing accept paths (`AuthConcern#accept_pending_invitation`,
> `InvitationsController#accept`, `InvitationsController#signup`), and in each, session/proof
> creation (`sign_in`) is sequenced *before* the gate check and the `accept!` AASM call — never
> after. Enumerate all three call sites explicitly in the stage's implementation notes; the spine's
> code sweep must add `app/controllers/web/invitations_controller.rb` to its sources.

---

## H8 — `password` `enabled: false` conflates a company-entry policy with a global credential

**Seam:** AD-4 (`auth_providers` row per company, including `password`) vs. AD-7's admin-only guard
vs. AD-5/AD-6 step-up, for a user whose *only* identity anywhere is a password.

AD-7's guard checks only that "an existing **active admin** has already proved" an alternative method
before a company may disable `password`. It says nothing about ordinary members. So it is entirely
AD-7-compliant for a company admin (who has linked, say, Microsoft SSO) to disable `password` for the
company while a regular employee member — whose one and only `user_identity` anywhere is
password-based, who has never linked any SSO identity — is immediately locked out (AD-6: disabling
voids that proof immediately). AD-5 says this "redirects to step-up... never signs the user out," but
step-up is a dead end for this user: there is no alternative identity to complete step-up *with*, and
per AD-3 linking a new identity "requires explicit linking from an already-authenticated session" —
which is precisely the session this user cannot obtain for *this* company.

The prompt's literal question — is this user locked out of the company, of the product, or neither —
is one the spine never answers, and two builders answer differently:

- **Builder A** scopes the effect strictly to company entry: `auth_providers` rows are per-company
  (AD-4), so disabling `password` for company X changes nothing about the user's global
  `password_digest`/credential or their access to any *other* company that still allows `password`.
  The user sees "no method available — contact your admin" for company X only.
- **Builder B**, implementing the same feature from the step-up UI/messaging side, frames the
  blocked state as "your password is disabled" (mirroring the row's name), conflating a per-company
  policy flag with the user's account-wide credential. This isn't just a copy nit: a support agent or
  the user themselves may reasonably act on that framing (reset the global password, contact support
  to "restore" the credential) when nothing about the credential is actually wrong — the row that
  changed lives on `auth_providers` (company-scoped), not `users`/`user_identities` (user-scoped).

Beyond the messaging split, the spine also has **no stated recovery path** for this user in Builder
A's (correct) world: they cannot self-link a new identity (no authenticated session for this
company), an admin cannot "grant" them SSO on their behalf without impersonation-level tooling that
isn't described anywhere in this spine, and re-enabling `password` is unguarded in the other
direction (AD-7 only blocks *disabling*), so the only stated way out is an admin flipping `password`
back on — silently defeating the SSO-only policy the admin turned it off for in the first place, the
moment any one member turns out to be stuck.

**Fix — tighten AD-4/AD-7 together:**
> `auth_providers.enabled` is strictly a company-entry gate; it never touches
> `users.password_digest` or any `user_identities` row, and no user-facing copy may describe a
> disabled company row as "your password/account is disabled." Additionally: AD-7's guard extends to
> require that disabling a method leaves **every currently-active member** — not only admins — with
> at least one already-proved alternative, or provides a stated, in-product recovery path (e.g. an
> admin-initiated identity link on a stuck member's behalf) before the disable is allowed. Absent
> that, AD-7 should say explicitly that members without an alternative are an accepted, admin-visible
> casualty of the policy change — not leave it undefined.

---

## Extra: H9 — a per-company `auth_providers` row for Google can't be resolved before a company is known

**Seam:** AD-4 ("every method available to a company is a row... including password and Google,
seeded on company creation") vs. AD-5 ("signing in is governed by the deployment allowlist alone" —
i.e. no company is known yet at the point of entry) vs. AD-2 (`Auth::Registry.for(auth_provider)`
resolution, which requires already having *an* `AuthProvider` row to resolve against).

Today, `google_omni_auth_service.rb` is a single, deployment-wide OAuth app: any Google user can hit
the callback, and the company is discovered **after** the fact from the verified email domain
(`Company.find_by_email_domain`). AD-4 says every company gets its *own* `auth_providers` row for
Google, seeded on creation. But Google's actual credentials (client id/secret) are one deployment-wide
app registration, not a per-company IdP connection like OIDC/SAML. The spine never reconciles "one
Google app, many companies" with "a row per company, and the registry resolves a specific row."

- **Builder A** adds a nullable/sentinel "global" `auth_providers` row (or a `company_id: nil`
  shape) for `google`, `password`, and `magic_link`, treated specially by `Registry`/`PolicyResolver`
  as the anonymous-entry-point row — preserving today's single "Continue with Google" button with no
  company context. This directly contradicts AD-4's literal words ("seeded on company creation," i.e.
  every row has a company), but is the only way to keep a companyless entry point at all.
- **Builder B** takes AD-4 at face value: every row, Google included, always has a `company_id`.
  Since `Auth::Registry.for(auth_provider)` needs a specific row to resolve an adapter, and AD-5
  evaluates the deployment allowlist "alone" with no company yet — the *only* way to get a concrete
  `AuthProvider` row to authenticate against is to ask the user which company they're entering
  **before** offering a login button, e.g. a company picker or subdomain-based routing. This is a
  fundamentally different, company-first login UX, breaking the existing domain-auto-join signup
  flow (which currently discovers the company from the OAuth-verified email *after* auth completes,
  not before).

Both are literal readings of AD-4 + AD-2 + AD-5 together; they produce flatly incompatible product
shapes (global anonymous entry vs. mandatory company-first entry) and the spine gives no signal which
one STAGE-0/ORG-POLICY is supposed to build. Given `google` is explicitly in scope for STAGE-0/ORG-POLICY
migration (not a future stage), this is not a deferred question — it blocks the first stage's login
page.

**Fix — new AD (or fold into AD-4):**
> A small set of method kinds (`password`, `google`, `magic_link`) are *deployment-wide identity
> providers* Rails always knows how to authenticate against; the *company-scoped* `auth_providers`
> row for these kinds carries an `enabled` policy flag only, never distinct provider credentials —
> `Auth::Registry` resolves the **adapter** for these kinds from deployment config regardless of
> company, and resolves the **row** (for the AD-4 effective-set/enabled check) only *after* the
> assertion returns an email, exactly as `google_omni_auth_service.rb` does today. Per-company-keyed
> kinds (`microsoft`, `oidc`, `saml`) are the only ones where the row itself carries distinct
> credentials and must be known before the flow begins (hence require company-first entry, e.g. a
> company slug in the SSO-initiation URL).

---

## Summary table

| # | Seam | Severity | One-line |
| --- | --- | --- | --- |
| H1 | AD-3 promotion gate | CRITICAL | `email_verified` absent-vs-false is undefined; one compliant reading reopens the exact takeover AD-3 exists to close |
| H9 | AD-4 + AD-2 + AD-5 | CRITICAL | A per-company Google row can't be resolved before a company is known; blocks STAGE-0's own login page, not just a future stage |
| H5 | AD-4 + AD-7 | HIGH | AD-7's guard covers `enabled` toggles, not row deletion, and isn't specified as company-locked, so two individually-safe admin actions can race to an empty effective set |
| H6 | AD-10 vs AD-3 | HIGH | SCIM must write `user_identities` to provision users; AD-10's direct-write precedent and AD-3's sole-writer rule point opposite ways with no tiebreaker |
| H7 | AD-11 vs invitation code | HIGH | Company-entry (accept!) currently runs before session/proof exists in all 3 accept call sites; the spine's own sources list omits 2 of the 3 |
| H3 | AD-5 + AD-6 | MEDIUM | Step-up compliant as either "new Session row" or "append to existing Session" — different revocation/token-rotation security properties |
| H4 | AD-6 revocation | MEDIUM | "Voids immediately" doesn't rule out a wider-than-request cache or a sweep-based tombstone, both of which reopen an attacker window |
| H2 | AD-3 subject claim | MEDIUM | `oid` is an example, not a mapping table; a kind-agnostic adapter can silently store a non-immutable claim |
| H8 | AD-4 `password` row | MEDIUM | No stated answer for a password-only user losing their sole method; messaging and recovery path are unspecified and support-risk-prone |

**Total: 9 holes** (renumber H1-H9; table lists all).
