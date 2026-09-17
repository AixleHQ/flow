# Rubric Walker review — Federated identity and SSO architecture spine

**Target:** `docs/planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md`
**Memlog:** same folder, `.memlog.md`
**Driving research:** `docs/research/technical-federated-identity-and-sso-provider-research-2026-09-16.md`
**Reviewer:** Rubric Walker lens (read-only)

## Verdict

CONDITIONAL — the spine is well-grounded (every code citation I re-checked is accurate) and faithfully
tracks the research roadmap, but it has one load-bearing structural gap (F1) and an underspecified
cutover (F2) that together mean two builders implementing STAGE-0 could diverge on the exact thing the
task asked me to scrutinize: how `user_identities` gets backfilled and how live sessions survive the
switch. I'd send it back for one more pass on AD-3/AD-4's interaction before epics are cut, everything
else is fixable in-flight.

## Findings

### F1 — HIGH: "one row per company" (AD-4) and "identity keyed by connection" (AD-3) never reconcile for the two methods that aren't actually per-company

AD-4's rule is explicit: *"Every method available to a company is a row in `auth_providers` —
**including password and Google**, seeded on company creation."* AD-3's rule is equally explicit:
`user_identities` is unique on `(auth_provider_id, subject)`.

But password and Google are not, today, per-company connections:

- Google OAuth is one deployment-wide client (`Settings.google_oauth`, `config/initializers/omniauth.rb:2`)
  — there is no per-company client id/secret to seed a distinct row with.
- `password_digest` is one column on `users` (`db/schema.rb:1192`), shared across every company a user
  belongs to (verified: no route or model scopes it per company).

If every company still gets its own seeded "password" and "google" `AuthProvider` row (as AD-4 literally
says), then a user in 3 companies needs 3 `user_identities` rows for the *same* password/Google
credential — same `subject`, three different `auth_provider_id`s. Nothing says whether that's the
intended shape, or whether password/Google are actually meant to be one deployment-wide row referenced
by every company (which would contradict "seeded on company creation" and complicate AD-7's
per-company "an admin has already proved this method" check, since the proof would live against a
row shared by companies that have never coordinated).

This isn't academic — it's the exact question a STAGE-0 builder must answer to write the backfill
migration AD-12 depends on ("credential existence is `user.user_identities.any?`"), and to handle the
initial-admin-creation path (`Company#initial_admin_email`/`initial_admin_password`,
`app/models/company.rb:34`) where a password is set before the company (and therefore its seeded
`AuthProvider` row) fully exists. Two reasonable builders would model this differently: one creates N
redundant rows per company, another makes password/Google exempt from AD-4's per-company seeding and
special-cases them, a third makes `auth_provider_id` nullable for "global" kinds. Each has different
consequences for AD-3's uniqueness constraint and for AD-7's prove-before-enforce scope. This is a real
divergence point for the level below and it is currently unaddressed — not decided, not deferred, not
an open question.

### F2 — HIGH: the migration/cutover for both the session model and the column drop is underspecified

Directly the dimension the task asked me to scrutinize. Two independent things change shape in
STAGE-0, and neither has a stated cutover sequence:

1. **Sessions.** Today `sign_in` is `session[:user_id] = user.id` and nothing else
   (`app/controllers/concerns/auth_concern.rb:8-18`, cited accurately by AD-6). AD-6 replaces this with
   a `Session` row plus append-only `session_authentication` proofs, and AD-5/ORG-POLICY's entry gate
   is defined *in terms of* those proofs ("session proofs ∩ effective set"). The spine never says what
   happens to a cookie that is already live at deploy time — one with a `user_id` but no corresponding
   `Session`/`session_authentication` row. Options are materially different (force a global logout on
   deploy; lazily materialize a `Session` row on next request with *no* recorded proof, which makes
   AD-5's policy check vacuously fail-open or fail-closed depending on how "empty intersection" is
   coded; or run a real backfill of one `Session`+`session_authentication` per currently-valid cookie
   before flipping the read path) — and the choice changes user-visible behavior on deploy day. Nothing
   in the AD text, the Capability→Architecture Map, or the memlog picks one.
2. **`users.provider`/`uid` → `user_identities`.** AD-12 says the columns "are dropped after backfill,"
   but there's no stated order relative to cutting `sessions_controller#omniauth` and
   `GoogleOmniAuthService` over to the new registry/adapter path (both still hardwired today, confirmed
   at `app/controllers/web/sessions_controller.rb:62-92` and `app/services/google_omni_auth_service.rb:27-48`).
   Is this expand/contract (write both old and new shapes for a window, backfill, then cut reads, then
   drop columns), or a single stop-the-world migration+deploy? This team already has an
   expand/contract discipline for exactly this class of problem elsewhere (rolling deploys splitting
   bundle from API require it), but the spine doesn't invoke it here, despite dropping two live,
   currently-read columns.

Given AD-12 is the one AD explicitly under a "HARD RULE" callout in the review brief, I'd treat this as
blocking: STAGE-0 stories cannot be written unambiguously off the spine as it stands.

### F3 — MEDIUM: several "only X may do Y" Rules are conventions, not enforced constraints

Criterion 2 asks whether a Rule is "actually enforceable" or "a wish." Three Rules make an exclusivity
claim with no stated enforcement mechanism:

- AD-3: "`Auth::IdentityResolver` is the only writer of `user_identities`."
- AD-4: the effective set is "computed **only** by `Auth::PolicyResolver#allowed_for(company)`."
- AD-10: "No direct `update_column`, no bypassing the state machine" for SCIM writes.

Nothing pins these to a mechanism (a Rubocop cop, a private/friend-class pattern, a DB trigger, a
`freeze`d writer). Compare to AD-12 in the same spine, which *is* mechanically enforced — once the
columns are dropped, nothing can read them, full stop — or AD-9's reachability split, enforced by actual
network topology. This codebase already has the pattern for making an invariant like AD-10's
mechanically true: `docs/testing.md`'s custom `Testing/*` Rubocop cops are exactly this move, applied
to test-writing discipline. The spine doesn't commit any of these three to an equivalent mechanism, so
as literally written they are aspirational conventions a code reviewer must catch by eye, not
constraints the architecture itself prevents someone from violating.

### F4 — MEDIUM: the research's IdP-initiated-SSO open question is dropped, not carried forward

Research §11, row 4: *"Does keeping our own login page survive contact with enterprise buyers who
expect IdP-initiated SSO? ... confirm during the Stage 3 spike."* The spine's Open Questions table has
three entries (Polis tenancy, passkey scoping, `super_admin` bypass scope) and this one isn't among
them, nor is it in Deferred. AD-8/AD-9 commit to "SAML never enters the Rails process" and "Rails
completes it through `Methods::Oidc` against the Polis sidecar," which is a stance on the *SP-initiated*
flow only — nothing states which party fields an IdP-initiated assertion (a customer's IdP portal
linking straight to Polis, bypassing the Rails login page AD-9's diagram assumes is the entry point).
This is a capability the research flagged as decision-critical for STAGE-3 and it should either be
resolved, deferred explicitly, or listed as an open question — right now it's simply absent.

### F5 — MEDIUM: AD-11's "same AD-5 gate" claim doesn't fit the one invitation path that creates a credential from scratch

AD-11: "Accepting an invitation passes through the same AD-5 gate as any other entry." AD-5's gate is
defined as session proofs ∩ effective set — it presumes an existing authenticated session or a
completed sign-in. But `Web::InvitationsController#signup`
(`app/controllers/web/invitations_controller.rb:72-94`, `signup_allowed?` at `:112-115`) is a different
shape: a brand-new invitee with **no** existing credential sets a password for the first time and is
signed in directly, with no prior proof to intersect against. The spine doesn't say whether an
SSO-only company should even offer this password-signup form (letting a first-time invitee mint a
password credential silently defeats "SSO-only"), nor whether "just set a password" counts as
satisfying AD-7's prove-before-enforce bar. This is a real fork in the invitation flow that AD-11 as
written doesn't actually cover.

### F6 — LOW: `omniauth-google-oauth2` is absent from the Stack table with no stated retirement

`config/initializers/omniauth.rb`'s `google_oauth2` strategy is provided by `omniauth-google-oauth2`
(confirmed in `Gemfile.lock`, `omniauth-google-oauth2 (1.2.3)`), but the Stack table doesn't list it,
and no AD states it's being retired in favor of routing Google through the generic
`openid_connect`-backed `Methods::Oidc` (only implied by the architecture diagram's
`A2 --> Methods::Oidc (google, microsoft, generic, saml-via-polis)`). Worth an explicit line — either
"kept" or "replaced by `openid_connect`" — so a builder doesn't leave two Google strategies live by
accident. (The version-reality lens flagged this independently, same severity.)

### F7 — NIT: companion doc doesn't exist yet; one file:line citation is an inverse match

- Front-matter `companions: docs/design/federated-identity.md` — that file doesn't exist yet (only
  `docs/design/oauth-unification.md` is in `docs/design/`). Presumably the not-yet-written deliverable
  the memlog calls out ("the spine PLUS a full solution-design document in docs/design/"); worth
  confirming it lands before the spine leaves `draft`.
- AD-12 cites `invitations_controller.rb:27,114` for the `password_digest.present? || provider.present?`
  test. Line 27 matches literally; line 114 is the logical inverse of the same predicate
  (`password_digest.blank? && provider.blank?`, in `signup_allowed?`) — same test class, not a literal
  string match. Not a misreading, just worth knowing if someone greps for the exact string.

## Code verification log (criterion 5)

All file:line claims in the spine's ADs were re-read against the actual files and check out:

| Claim | Location | Verified |
|---|---|---|
| Callback hardwires one service class | `app/controllers/web/sessions_controller.rb:63` | Accurate — `auth_service = GoogleOmniAuthService.new(...)` |
| Joins on email alone, never reads `email_verified` | `app/services/google_omni_auth_service.rb:28` | Accurate — `User.find_or_initialize_by(email: email)`; `email_verified` never referenced in the file |
| Session is only `session[:user_id]` in a cookie | `app/controllers/concerns/auth_concern.rb:8-18` | Accurate — `sign_in`/`sign_out`/`signed_in?` touch only `session[:user_id]` and related session keys, no DB-backed session record anywhere in the concern |
| Invitation acceptance runs with no policy involved | `app/controllers/concerns/auth_concern.rb:87-106` | Accurate — `accept_pending_invitation` only checks token validity and AASM `may_accept?`, no auth-policy check |
| `password_digest.present? \|\| provider.present?` credential test | `app/controllers/web/invitations_controller.rb:27,114` | :27 literal match; :114 is the inverse predicate in `signup_allowed?` (see F7) |
| `users.provider`/`uid` single unique pair | `db/schema.rb:1182-1205` | Accurate — one `provider`/`uid` string pair, unique composite index `index_users_on_provider_and_uid` |
| `companies.email_domain` unique+required, domain→company 1:1 | `db/schema.rb:326-344`, `app/models/company.rb:74-77` | Accurate |
| Membership states invited/active/suspended/revoked | `app/state_machines/company_membership_state_machine.rb:9-37` | Accurate |
| `Encryptable` concern already used elsewhere | `app/models/oauth_credential.rb:7`, `app/models/agent_credential.rb:5` | Accurate |
| `Audited::Audit` trail used for impersonation | `app/controllers/admin/users_controller.rb:29-48` | Accurate |
| `rack-attack` already in the Gemfile | `Gemfile.lock:513` (`rack-attack (6.8.0)`) | Accurate |
| Ruby/Rails/omniauth/rotp versions in Stack table | `Gemfile.lock`, `.ruby-version` | Ruby 4.0.6, Rails 8.1.3.1, omniauth 2.1.4, rotp 6.3.0 all confirmed exact |
| `rotp` in Gemfile, zero usages | `Gemfile:185`, `grep -r rotp app/ lib/` | Confirmed zero hits outside Gemfile |
| No `ruby-saml`/`omniauth-saml` in this codebase today | `Gemfile.lock` | Confirmed absent |
| No public self-serve signup route (only invitation-gated) | `config/routes.rb` | Confirmed — only `login`, `auth/:provider/callback`, and `invitations/:token/*` |
| `Auth::`, `AuthProvider`, `UserIdentity`, `SessionAuthentication` don't exist yet | `app/services/`, `app/models/` | Confirmed — pure greenfield, consistent with "Structural Seed" being proposed |

## Rubric coverage notes (criteria not otherwise called out above)

- **Criterion 1 (divergence points for the level below):** covered well except F1/F2/F5 above.
- **Criterion 3 (Deferred hiding a divergence):** the four Deferred items (SCIM implementation choice,
  being an OIDC provider, per-company branding, step-up for sensitive actions) are each genuinely
  non-blocking for the stages that precede them — no finding here.
- **Criterion 4 (tech verified-current):** cross-checked the Stack table against both the research
  report's dated citations and `Gemfile.lock`/`.ruby-version` directly — all entries check out (see
  table above). No staleness found beyond F6.
- **Criterion 6 (research capability coverage):** all five research stages (0-4) and ORG-POLICY are
  represented in the Capability→Architecture Map; the one dropped item is F4 (IdP-initiated SSO).
  "GitHub if wanted" from the research is implicitly out-of-scope (research itself marked it optional)
  and its absence from the closed `kind` enum is not a finding on its own.
- **Criterion 7 (every dimension decided/deferred/open):** the operational/deployment envelope for
  the Polis sidecar itself (own DB, public ACS route, internal admin API, optional compose profile) is
  genuinely decided (AD-9) and the compose `profiles:` mechanism it relies on already exists in this
  repo (`docker-compose.yml:200,212`, pattern `profiles: [infra]`) — ratified correctly. The one
  dimension left silent is the migration/backfill/cutover sequencing itself — see F2.
