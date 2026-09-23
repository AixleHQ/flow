# RFC: Federated identity, SSO, and company-level auth policy

**Status:** Draft
**Date:** 2026-09-17
**Scope:** Every way a human proves who they are to this app — multi-identity users, per-company IdP connections, Microsoft Entra and generic OIDC, passkeys/TOTP/magic links, SCIM directory sync, server-side sessions — and every rule a company may set about which of those its members may use.
**Invariants:** [`ARCHITECTURE-SPINE.md`](../planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md) — the `AD-n` blocks cited throughout this document.
**Depends on:** [research report](../research/technical-federated-identity-and-sso-provider-research-2026-09-16.md), [oauth-unification](./oauth-unification.md) (the integrations broker whose state machinery is copied, not reused)

---

## 1. Problem

We authenticate two ways: Google OAuth and email/password. We want Microsoft/Entra, generic OIDC, enterprise SAML, passkeys, MFA and magic links — and we want a company admin to decide which of those apply to their company.

Three answers fix the solution space before any feature comparison:

1. Enterprise SSO must work for **self-hosted** OSS users, not only our managed cloud.
2. There is **no deadline** — this is roadmap work, so total cost of ownership beats time-to-first-SAML-customer.
3. **No paid external dependency** may sit in the login path.

Together these eliminate the entire commercial CIAM market, plus the AGPL and self-hosted-paywalled OSS identity providers. The research report carries that elimination with prices and licences. What remains is: own the identity layer, and buy nothing.

## 2. Current state (audit)

| Concern | Location | Behaviour |
|---|---|---|
| Provider registration | `config/initializers/omniauth.rb:1-9` | One strategy, `google_oauth2`. Credentials are a boot-time global (`Settings.google_oauth`) — one client per deployment. |
| CSRF posture | `config/initializers/omniauth.rb:12-16` | POST-only request phase, pinned against CVE-2015-9284. Correct; keep. |
| OAuth callback | `app/controllers/web/sessions_controller.rb:62-92` | Hardwires `GoogleOmniAuthService`. `params[:provider]` is routed but never read. |
| Identity resolution | `app/services/google_omni_auth_service.rb:27-48` (since deleted) | `User.find_or_initialize_by(email:)` — email is the identity key. `provider`/`uid` are overwritten on every login. `email_verified` is never read. |
| Password sign-in | `app/forms/user_sign_in_form.rb:16-37` | bcrypt, with dummy-hash timing equalisation. |
| Session | `app/controllers/concerns/auth_concern.rb:8-18` | `session[:user_id]` in the encrypted cookie. No server-side record: no "sign out everywhere", no device list, no revocation. |
| Tenant resolution | `app/controllers/concerns/auth_concern.rb:46-57,110-157` | `session[:current_company_id]`, re-validated against live active memberships **on every request**. |
| Invitations | `app/controllers/web/invitations_controller.rb`, `app/controllers/concerns/auth_concern.rb:87-106` | Signed 7-day token parked in the session, redeemed after either login path. All three accept call sites run `membership.accept!` before any session exists. |
| Company creation | `app/controllers/admin/companies_controller.rb:12` | Admin namespace only. There is no self-serve company creation, which is what makes `companies.email_domain` a trustworthy anchor today (§7, AD-17). |
| Schema | `db/schema.rb:326-369,1182-1205` | `users` has one `provider`+`uid` pair, unique composite. `companies.email_domain` is unique and required. No column exists for an Entra tenant, a SAML entityID, or a per-customer connection. |

Five structural blockers follow from that audit, and none of them is archaeological — there is no literal `provider == "google"` comparison anywhere. The coupling is in the schema:

1. One `provider`+`uid` pair caps a user at one external identity; signing in via Entra would silently overwrite a Google `uid`.
2. Providers are initializer constants, so **per-company connections have nowhere to live**. This, not gem availability, is the real blocker.
3. The callback instantiates one service class and rescues one exception class.
4. `password_digest.present? || provider.present?` is the entire "does this person have credentials?" test.
5. Email is the cross-IdP join key with no `email_verified` check — fine with one trusted provider, an account-takeover vector with two.

## 3. Goals

- Many identities per user, many connections per company, one place that resolves either.
- A company admin can enable and disable authentication methods for their company, safely — without locking anyone out, and without the toggle being bypassable from a side entrance.
- Broad method coverage without a SAML parser in the Rails process.
- The self-hosted deployment stays one Rails app and a Postgres. Nothing here adds a second service to run.

**Non-goals.** Becoming an OIDC provider for customers' own tools. Replacing our company model with a vendor's. Per-company login-page branding beyond the existing `Company#branding`.

## 4. Design

Rails is the system of record for identity (AD-1); every authentication method is an adapter behind one port (AD-2). Controllers hold an `IdentityProvider` row and ask the port — they never branch on a kind string, and adding a method adds an adapter and a row type rather than editing a controller.

### 4.1 Providers and policy are two tables

The tempting model — "a row per method per company" — is incoherent for the two methods we already have: Google is **one deployment-wide OAuth client** whose company is discovered from the email domain *after* authentication completes, and a password is one `password_digest` on a globally-unique user. AD-4 has the full argument for why forcing either into a per-company row breaks today's entry page.

So (AD-4):

- **`identity_providers`** — what can authenticate. `scope: deployment` (password, Google, passkey, magic link, a deployment-wide Entra app) or `scope: company` (a customer's own OIDC, SAML, or Entra tenant). Identities point here.
- **`company_auth_policies`** — `(company_id, identity_provider_id, enabled)`. The only thing a company admin toggles.

The effective set for a company is `deployment_allowlist ∩ enabled policies`, computed only by `Auth::PolicyResolver`. The **deployment allowlist is configuration**, not data — a self-hosted operator is never handed a toggle for a provider their instance holds no credentials for.

### 4.2 Where the policy bites

A user signs in before any company is chosen, and may belong to several with disjoint policies. Enforcing at the login screen therefore fails in both directions: a contractor on a foreign email domain would slip past an SSO-only company, and a multi-company user would be held to the strictest policy of any of them.

So the policy is enforced **at company entry** (AD-5), in the same pass that already re-validates membership on every request. A mismatch redirects to step-up re-authentication — never a sign-out, never an unscoped page.

For that to work without bouncing a multi-company user between two step-ups forever, session proofs **append** (AD-6). A session records every method it has satisfied; a company is satisfied when the intersection of those proofs with its *currently enabled* providers is non-empty. Disabling a provider voids its proofs on the very next request, because the intersection is computed on read against live rows — never from a cache, never by a sweep writing tombstones.

Two properties of that model are load-bearing and easy to lose:

- The session identifier **rotates on every successful authentication**, and the proof is appended to the rotated session. Without this, a session fixed before a step-up inherits the victim's new proof.
- The test is deliberately OR-only, so it cannot express "SAML *and* TOTP". Additive MFA is a contained future change — require a subset instead of a non-empty intersection — and is deferred, not designed around.

### 4.3 Not locking anyone out

A company can destroy itself with this feature in three ways, and each needs its own guard (AD-7):

1. **Enable a connection that was never known to work.** Enabling a company-scoped provider requires a completed real sign-in through it, by an admin of that company, first.
2. **Delete instead of disable.** Deleting a policy row or a provider is evaluated exactly as disabling it — the guard that only reads `enabled` is a hole.
3. **Race two safe edits into one unsafe state.** The check and the write happen in one transaction holding a row lock on the company.

And the guard evaluates against **every currently active member**, not merely the acting admin — otherwise one compromised admin can downgrade a company to its weakest seeded method, or strip everyone else's access, without tripping anything. A platform `super_admin` may override, audit-logged with the before and after effective sets.

Members are not left to discover this at sign-in: when an edit would remove the last method a member has ever proved, that member is emailed before it takes effect, and the admin sees the list of about-to-be-stranded members before confirming (AD-16).

### 4.4 Identity binding

Identity is `(provider, subject)` — never email (AD-3). The subject claim is **binding per kind**, not illustrative: OIDC `sub`, Entra `oid` (never `email` or UPN). An adapter that cannot obtain its bound claim fails the sign-in rather than substituting another.

Email may promote an assertion to an existing user only when the provider asserts `email_verified` **present and true** — an absent claim is not a true claim — and only when the asserting provider is company-scoped and the email's domain is that company's. A changed email updates the stored address and never re-links the identity, so mailbox reassignment does not transfer an account.

Every assertion is checked against the row it claims to satisfy (AD-13): `iss` and `aud` for any OIDC connection, `tid` for Entra. Mismatch rejects. There is no email fallback and no "try the other connections" retry — that retry *is* the multi-tenant confused-deputy bug.

Passkeys are the one credential kind the company does not own (AD-18). A passkey lives on the user's own device and works across every company they belong to, so registration, listing and deletion belong to the user alone and no company-admin surface touches them. A company may still decline to *accept* a passkey — disabling it in the policy stops a passkey proof from satisfying that company, which an SSO-only buyer will want — but it never deletes or invalidates the credential, which remains usable everywhere else.

### 4.5 No SAML, and why that costs little

There are two ways to support SAML in a Ruby application and both were rejected.

**In the web process** means `ruby-saml` — the only Ruby service provider, and what every wrapper
sits on. It has had five Critical authentication-bypass advisories in fifteen months, in three
rounds: September 2024 (XML Signature Wrapping, confirmed exploitable against gitlab.com), March 2025
(two parser differentials), December 2025 (two more, one published as an *incomplete fix* of
March's). Each is a new angle on the same hazard — two XML parsers, one document, one trust decision.
Taking it means a standing same-week patch obligation, forever, in the process that serves the app.

**Out of process** means a bridge: a second service to deploy, monitor and upgrade, in a product
whose self-hosted story is "one Rails app and a Postgres". That was built and then removed —
the operational cost was not worth what it bought.

What it buys is small, because **enterprise SSO does not require SAML**. Per-company OIDC is already
implemented and tested (§4.1), and every identity provider our customers actually run speaks it:
Entra ID, Okta, Ping, OneLogin, JumpCloud, Google Workspace. SAML is needed only where a customer's
IT mandates it specifically, or where they run something older — ADFS, Shibboleth.

So the decision is recorded rather than deferred (AD-28), and it is guarded: `ruby-saml` and its
wrappers are barred from `Gemfile.lock` by a test. Adding SAML later has to be a deliberate act taken
with that advisory history in view, not a quiet `bundle add`.

### 4.6 Provisioning

SCIM writes `User` and `CompanyMembership` only, through the same AASM events as the UI, attributed to the connection that made them (AD-10). **SCIM never writes identities.** A SCIM-provisioned user has no identity row until their first successful authentication creates one — which is what makes provisioning-before-first-login coherent instead of a second identity authority contradicting the first.

### 4.7 Invitations

The invitation flow is the obvious side entrance, and today it cannot be gated where the gate belongs: all three accept call sites run `membership.accept!` before a session exists. Acceptance therefore moves **after** the session and its first proof, into `Auth::SessionService` at company entry — one call site instead of three (AD-11).

`#signup`, which mints a user's first credential, is gated on the *kind being minted*: a company with password disabled shows no password form. And the token binds to the invited address — redeeming it requires the authenticating identity to assert that same verified address, single-use, consumed in the same transaction as the acceptance (AD-12). Otherwise whoever holds the link attaches the account's first credential.

### 4.8 Cutover

Expand/contract, three independently deployable phases (AD-14):

| Phase | Does | Does not |
|---|---|---|
| **Expand** | Create the new tables; backfill an identity per existing `provider`+`uid` and per existing `password_digest`; write both shapes on every sign-in | Read from the new tables |
| **Migrate** | Switch all reads over; `GoogleOmniAuthService` is replaced by `Methods::Oidc` behind the registry | Drop anything |
| **Contract** | Drop `users.provider`, `users.uid` | — |

No phase both writes the new shape and drops the old one — the rolling-deploy failure this team already knows from splitting a JS bundle from its API.

Live sessions do not survive the Migrate phase: every existing cookie session is invalidated once and everyone signs in again (AD-14). The alternative — a bounded window in which a legacy cookie mints a `Session` row — would require a half-trusted proof kind that exists only during the migration, which is exactly the sort of shape two builders interpret differently. One forced re-authentication costs every user a single sign-in and buys an invariant that holds in every phase: a proof always names a real provider.

### 4.9 The operator account

A `super_admin` is outside the company model entirely — no memberships, its own namespace — so the company-entry gate would have nothing to evaluate for it. It therefore bypasses every company auth surface: it satisfies any company without a proof, is never counted as a stranded member, and may override the AD-7 guards, with every override audit-logged.

The exchange is that the operator account holds exactly one key: **password only** (AD-19). An assertion from any other provider is refused before a session is minted, whatever the deployment allowlist or a company policy allows. The highest-privilege account in the installation should not depend on an external identity provider, and certainly not on a company-scoped connection that the customer themselves administers.

## 4.9 What it looks like

Captured from a running build. `super_admin` is omitted deliberately: it bypasses
every company surface here and authenticates by password only.

**Signing in.** Google and a passkey identify the person on their own. Company SSO
and an emailed link start from the address, so they stay inactive until one is
typed — and the screen says so rather than leaving a grey control unexplained.

| Nothing typed | Address typed |
|---|---|
| ![Login screen with company SSO and the emailed link inactive](images/federated-identity/01-login.png) | ![The same screen with every method active](images/federated-identity/02-login-with-address.png) |

**Enterprise SSO discovery.** The workspace is resolved from the address's domain.
One enabled connection starts immediately; several offer a choice rather than a
guess; none says so instead of failing obscurely.

| A workspace with two connections | A domain no workspace claims |
|---|---|
| ![Choice between two OpenID Connect connections](images/federated-identity/03-sso-choice.png) | ![The login screen reporting no SSO connection for that domain](images/federated-identity/04-sso-no-connection.png) |

**The emailed link.** The mail carries the address the browser reaches the app at,
port included. Opening it lands on a confirmation rather than consuming the token,
because mail providers pre-fetch links.

| Requested | Delivered | Confirm before it is spent |
|---|---|---|
| ![The login screen after a link is requested](images/federated-identity/05-magic-link-requested.png) | ![The delivered sign-in mail](images/federated-identity/06-magic-link-email.png) | ![The confirmation page the link opens](images/federated-identity/07-magic-link-confirm.png) |

**Company auth policy.** What a workspace accepts, and the connections it owns. A
new connection arrives switched off and carries *Not verified yet* until someone
has signed in through it once, so a misconfigured connection cannot lock a
workspace out.

| A workspace that refuses passwords | A connection awaiting its first sign-in |
|---|---|
| ![Sign-in methods with password off and SCIM on](images/federated-identity/08-policy-sso-only-workspace.png) | ![An OpenID Connect connection marked not verified yet](images/federated-identity/09-policy-unverified-connection.png) |

**The entry gate.** Enforcement is at company entry, not at the login screen: a
session proved one way crosses into a workspace that does not accept it and is
asked to add a proof, not signed out. Every method the workspace accepts gets a
control.

| Crossing into a workspace that refuses the proved method | Proved, and through |
|---|---|
| ![The step-up screen offering a link, a passkey and a code](images/federated-identity/10-step-up.png) | ![The workspace after the step-up is satisfied](images/federated-identity/11-step-up-passed.png) |

**Enrolling codes.** The QR carries the same secret as the text below it; the text
is the fallback for an authenticator with no camera. Both are redacted in this
capture.

![Authentication code enrolment showing a QR and the typed secret](images/federated-identity/12-totp-qr.png)

**Who may change any of it.** The policy surface is admin-only in both places it
is enforced — a member has no navigation entry, and typing the path directly is
refused rather than merely hidden.

| A member's navigation | A member typing the path |
|---|---|
| ![Sidebar without the Sign-in methods entry](images/federated-identity/13-member-nav.png) | ![The request refused](images/federated-identity/14-member-refused.png) |

## 5. Phasing

| Stage | Scope | Estimate |
|---|---|---|
| **0. Foundation** ✅ built | `identity_providers`, `user_identities`, server-side `AuthSession` + appending proofs, the port and registry, expand/contract backfill | 3-4 wk |
| **ORG-POLICY** ✅ built | `company_auth_policies`, deployment ceiling, entry gate, step-up, the no-stranding guard, admin UI | 3-4 wk |
| **1. OIDC** ✅ built | Entra (multi-tenant), generic per-company OIDC with PKCE | 4 wk |
| **2. Passwordless** ✅ built | Passkeys, TOTP (step-up only), magic links | 4-5 wk |
| ~~**3. SAML**~~ | **Dropped.** Enterprise SSO is per-company OIDC — see §4.5 | — |
| **4. SCIM** ✅ built | Inbound provisioning and deprovisioning | 3-4 wk |

Stages 0 and ORG-POLICY are worth doing on their own merits: they fix the missing revocation path and the email-join-key weakness, both of which exist today regardless of whether any SSO ever ships.

`rotp` 6.3.0 is already declared at `Gemfile:185` with zero usages anywhere in `app/` or `lib/` — Stage 2 inherits a vendored, approved TOTP gem rather than adding a dependency.

### 5.1 As built

Stages 0 and ORG-POLICY are implemented on `artempartos/rusalka`. What exists:

| Piece | Where |
|---|---|
| Schema | `db/migrate/20260917000100..000600` — five tables plus the expand-phase backfill |
| Models | `IdentityProvider`, `UserIdentity`, `CompanyAuthPolicy`, `AuthSession`, `AuthSessionProof` |
| Port and adapters | `app/services/auth/method.rb`, `methods/password.rb`, `methods/google.rb`, `registry.rb` |
| Identity and policy | `auth/identity_resolver.rb`, `auth/policy_resolver.rb`, `auth/policy_updater.rb` |
| Sessions | `auth/session_service.rb`, wired through `AuthConcern` |
| Entry gate and step-up | `Web::ApplicationController#enforce_company_auth_policy`, `Web::StepUpsController`, `Auth/StepUpPage.tsx` |
| Company surface | `Web::Company::AuthPoliciesController`, `Web::Company::AuthPoliciesPolicy`, `Company/AuthPolicies/Index.tsx` |

An adversarial review of the diff caught two CRITICAL defects that the green suite did not, both worth carrying forward:

- **The impersonation marker is only a cookie key.** `sign_out` never cleared it (true before this work too), and the new session rotation deliberately carried it across `reset_session` — so an unrelated later sign-in on the same browser inherited the operator identity and passed `authenticate_admin!`. Verified by reverting the fix: the bystander got `200` on `/admin`. Fixed in AD-20, with a regression test confirmed to fail against the pre-fix code.
- **Password credentials never reached `IdentityResolver`.** Password sign-in goes through `UserSignInForm`, and invitation signup mints a password directly, so only the backfill migration ever created password identities. Anyone who set a password afterwards held zero identities — and `stranded_members` reads identities, so `PolicyUpdater` refused *every* policy edit for such a company, including purely additive ones. `Auth::LocalCredential.link!` now routes those through the single writer, and a `User` callback fires it whenever a password is written — so the invariant holds for the admin panel and seeds too, not only for the two controllers. The updater's own tests had been seeding the identity by hand, which is exactly what hid it; that seeding is now deleted, because production does it.

Three further implementation findings:

1. **The OmniAuth strategy name is not our provider kind.** `/auth/:provider/callback` carries
   OmniAuth's vocabulary (`google_oauth2`); ours is `google`. `Auth::Registry.provider_for_omniauth`
   maps it. Treating the URL segment as a kind turned every OAuth error into a generic failure.
2. **A redirect sign-in by an already-signed-in user appends its proof** rather than starting a new
   session. Otherwise proving Google discards the password proof another company still needs, and
   two companies with disjoint policies bounce the user between step-ups forever.
3. **`email_verified` arrives in `extra.raw_info`**, not reliably in `info`. The adapter reads both
   and treats absent as false. The test fake was corrected to carry the claim Google actually sends
   — a fake that omitted it never exercised the promotion path.

**Five of the six capabilities are implemented, and the sixth was deliberately dropped**, and the port held: every method after the first was an
adapter plus a row kind, with no change to the entry gate.

| Capability | Where |
|---|---|
| CAP-3 Microsoft | `auth/methods/microsoft.rb` — `oid` as the subject, tenant pinning per AD-13, personal accounts refused promotion |
| CAP-3 generic OIDC | `auth/methods/oidc.rb`, `auth/state.rb`, `Web::OidcSessionsController` — discovery, PKCE, server-side nonce, `iss`/`aud`/`nonce`/`tid` all checked |
| CAP-4 passkeys | `auth/methods/passkey.rb`, `Web::PasskeysController`, `Web::PasskeySessionsController`, `shared/lib/webauthn.ts` |
| CAP-4 magic links | `auth/methods/magic_link.rb`, `MagicLinkToken`, `Web::MagicLinksController` |
| CAP-4 TOTP | `auth/methods/totp.rb`, `Web::TotpController` — step-up only |
| CAP-6 SCIM | `Scim::UsersController`, `ScimConfiguration`, the Scimitar mixin on `CompanyMembership` |

**On CAP-5.** A sidecar bridge was built, and a spike ran it: the OSS build did take three
per-company connections with no licence gate, and the adapter's `client_id` shape worked against the
live authorize endpoint. The spike also found that the published compose image name did not resolve
at all, that one `entityID` may serve only one tenant, and that the bridge phones analytics home
unless told not to.

None of that survived the decision that followed it: carrying a second service was not worth what
SAML buys when per-company OIDC already covers the identity providers our customers run. The
adapter, the bridge client, the compose profile and their tests are removed; §4.5 records why, and a
test keeps `ruby-saml` out of the lockfile so the decision cannot erode quietly.

## 6. Alternatives considered

**Keycloak**, proposed by the CTO, is the most feature-complete Apache-2.0 identity product in existence and covers the entire wishlist without custom code. It is the wrong shape for *this* codebase rather than a bad product:

- It replaces a user and company model we already own — memberships with states, domain auto-join, invitations, impersonation, soft delete — and its Organizations feature has no per-org theming.
- It takes the login page. Passkeys and IdP brokering are browser ceremonies that cannot run behind our own React form; the only workaround, Direct Grant/ROPC, is forbidden by RFC 9700 and absent from OAuth 2.1.
- There is no free LTS: each community minor is the patched branch for roughly three months.
- Self-hosters get a JVM identity server on a quarterly upgrade treadmill, with no first-party production compose file.
- Keycloak hashes with SHA-256/512/Argon2, not bcrypt, so importing our digests needs a custom `PasswordHashProvider` SPI or a forced reset for every password user.

It becomes the right answer only if we decide to stop being in the identity business — a strategic choice about what this team maintains, not a component swap. If it is adopted anyway, the least-bad shape is **broker-only**: Keycloak holds no users, Rails stays the system of record, and the bcrypt migration problem disappears.

Because every external provider is consumed as plain OIDC behind one seam, putting Keycloak, Casdoor or Authentik in front of it later — or for a commercial broker, if the constraints ever change — is a connector change, not a re-platforming. Building this does not foreclose Keycloak; adopting Keycloak now forecloses everything else.

## 7. Security requirements that hold regardless

These are requirements, not improvements, and several fix weaknesses that exist **today**:

1. **Email is currently the cross-IdP join key with no `email_verified` check** (`google_omni_auth_service.rb:28`, since deleted). §4.4 replaces it.
2. **Nothing can revoke a session.** §4.2's server-side records are what make deprovisioning, "sign out everywhere", and device lists possible at all.
3. **`companies.email_domain` is an unverified trust anchor** — a company claiming a public mail domain would auto-join every user of that provider. It is safe today only because company creation is admin-only. Before self-serve creation is ever introduced, the domain must become a verified claim (DNS TXT with a `verified_at`) and public mail providers must be blocklisted (AD-17). `RESERVED_DOMAINS` on `Company` is not that blocklist: it holds fourteen implausible `.com` names and no public mail provider at all.
4. **Auto-join answers *which* company; the method answers *whether*.** The domain picks the company, but `Auth::DomainAutoJoin` now declines one that does not accept the provider the person authenticated with. Such a membership could never be entered — the entry gate refuses it on every request — and once active it strands its holder, which makes `Auth::PolicyUpdater` refuse **every** later policy edit by that company's admins. A membership nobody can use is worse than no membership: it reads as access, counts as a member, and freezes the policy screen.
5. **Copy `Oauth::State`, do not reuse it.** Its signed, 10-minute, single-use, user-pinned, server-side-PKCE shape is verified to be exactly what a login flow needs — but `OauthCredential` deliberately refuses to persist `id_token`, which is the artifact login requires.
6. **Rate-limit every credential-accepting endpoint** with explicit `rack-attack` rules.
7. **Magic links are not invitations.** Invitation tokens are 7-day and reusable-until-consumed; a login magic link needs 5-15 minutes, hard single-use, and session-fixation-safe redemption.
8. **The single-writer rules are enforced mechanically** (AD-15) — a custom `Auth/` rubocop cop, database unique indexes, a Pundit policy — because this repo already enforces doctrine with cops rather than documentation.

## 8. Open questions

All five are closed. They are kept rather than deleted because each answer is a
constraint the code now depends on.

| # | Question | Answer |
|---|---|---|
| 1 | Does the sidecar bridge's OSS build support enough tenancy for per-company connections? | **Withdrawn with SAML.** The spike answered yes — three connections, no licence gate — and the sidecar was dropped anyway: a second service is not worth what SAML buys. See §4.5. |
| 2 | Does a passkey belong to the user or to a company's policy? | **To the user.** Registration and deletion are the user's alone; a company may decline to *accept* a passkey but never deletes one (AD-18). |
| 3 | Does `super_admin` bypass the entry gate entirely, or only the activation guard? | **Entirely**, and it authenticates by password only — no federated provider may ever resolve to a `super_admin`. |
| 4 | IdP-initiated SSO inverts the "authenticate, then enter a company" order the entry gate assumes. | **Withdrawn with SAML.** Per-company OIDC is SP-initiated; nothing in the shipped flow starts at the IdP. |
| 5 | Live cookie sessions at the Stage 0 cutover: one forced global re-authentication, or a bounded adoption window? | **One forced re-authentication.** A product call, taken. |

## 9. Key references (code)

- `config/initializers/omniauth.rb` — the single-strategy registration and the CVE-2015-9284 posture to preserve.
- `app/services/auth/identity_resolver.rb` — the identity resolution that replaced `GoogleOmniAuthService` (deleted; its domain auto-join rule lives on in `auth/domain_auto_join.rb`).
- `app/controllers/concerns/auth_concern.rb:46-57,87-106,110-157` — the per-request membership re-validation the policy gate joins, and the invitation redemption that moves.
- `app/services/oauth/state.rb` — the redirect-state shape to copy.
- `app/state_machines/company_membership_state_machine.rb` — the events SCIM must go through.
- `app/models/concerns/encryptable.rb` — how connection secrets are stored.
