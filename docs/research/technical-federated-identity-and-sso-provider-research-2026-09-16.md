# Federated identity and SSO: market research and recommendation

**Date:** 2026-09-16
**Status:** Research — no decision taken yet
**Question:** We authenticate with Google OAuth and email/password. We want broad login coverage
(Microsoft/Entra, generic OIDC, enterprise SAML, passkeys, MFA, magic links, SCIM). The CTO proposed
Keycloak. What is actually on the market in 2026, and what fits this product?

---

## 1. The three constraints that decide this

Answered by the product owner before the analysis was written. They eliminate most of the market
before any feature comparison happens, so they are stated first.

| Constraint | Answer | Consequence |
|---|---|---|
| Does enterprise SSO have to work for **self-hosted** OSS users, or is it a managed-cloud feature? | **Everywhere** | Every SaaS-only vendor is out as *the* answer. Anything we adopt must be runnable by someone typing `docker compose up`. |
| What is the urgency? | **Roadmap, not a signed customer** | We can optimise for architecture and total cost of ownership rather than for time-to-first-SAML-customer. A vendor's "ship SAML this week" pitch buys us nothing we need right now. |
| Tolerance for a paid external dependency in the login path? | **None — free / self-hosted only** | Per-MAU and per-connection pricing models are out. So is any product whose self-hosted edition paywalls the exact features we need. |

A fourth constraint comes from the repository itself: the project is **Apache-2.0 and publicly
distributed** (AixleHQ/flow). Anything we bundle as a default must be license-compatible with
redistribution, and anything we run in the managed cloud must not create copyleft-as-a-service
obligations.

---

## 2. Where we are today

Verified by reading the code, not from memory.

| Concern | Location | Behaviour |
|---|---|---|
| Provider registration | `config/initializers/omniauth.rb:1-9` | One strategy: `google_oauth2`. Credentials are a **boot-time global** (`Settings.google_oauth`) — one client per deployment. |
| CSRF posture | `config/initializers/omniauth.rb:12-16` | POST-only request phase pinned against CVE-2015-9284. Correct. |
| OAuth callback | `app/controllers/web/sessions_controller.rb:62-92` | Hardwires `GoogleOmniAuthService`; `params[:provider]` is routed but never read. |
| Identity resolution | `app/services/google_omni_auth_service.rb:27-48` | `User.find_or_initialize_by(email:)` — **email is the identity key**. `provider`/`uid` are overwritten on every login. |
| Password sign-in | `app/forms/user_sign_in_form.rb:16-37` | bcrypt via `has_secure_password`, with dummy-hash timing equalisation. |
| Session mechanism | `app/controllers/concerns/auth_concern.rb:8-18` | `session[:user_id]` in the encrypted cookie. **No server-side session record** — no "sign out everywhere", no device list, no admin revocation. |
| Tenant resolution | `app/controllers/concerns/auth_concern.rb:46-57,110-157` | `session[:current_company_id]`, re-validated against live active memberships on every request. |
| Sign-in gates | `app/controllers/web/sessions_controller.rb:17-21,50,78-83` | Run *before* `sign_in`: no active membership, `pending`, `deleted` each get their own refusal. |
| Invitations | `app/controllers/web/invitations_controller.rb:14-40`, `app/models/company_membership.rb:61-65` | Signed 7-day token, parked in session, redeemed after either login path. |
| Schema | `db/schema.rb:326-369,1182-1205` | `users` has **one** `provider`+`uid` pair (unique composite index). `companies` has `email_domain` and nothing else — **no column exists for an Entra tenant id, a SAML entityID, or a per-customer IdP connection.** |

**Five structural blockers**, all mechanical rather than archaeological (there is no literal
`provider == "google"` comparison anywhere in the codebase — the coupling is in the schema):

1. `users.provider` + `users.uid` caps a user at one external identity. A user who signs in via
   Entra after having used Google silently loses their Google `uid` — last write wins.
2. Providers are initializer constants. **Per-company IdP connections have nowhere to live.** This,
   not gem availability, is the real blocker for enterprise OIDC/SAML.
3. `sessions_controller#omniauth` instantiates one service class and rescues one exception class.
4. `invitations_controller.rb:27,114` uses `password_digest.present? || provider.present?` as the
   entire "does this person have credentials?" test — it has to become "has any identity".
5. Email is the cross-IdP join key and `email_verified` is never checked. With one provider that is
   fine. With N providers it is an **account-takeover vector** — see §10.

**Reusable, but do not overload it:** `app/models/oauth_credential.rb`, `app/models/oauth_client.rb`
and `app/services/oauth/` (see `docs/design/oauth-unification.md`) are a hardened OAuth broker — but
for *third-party integrations*, not login. `Oauth::State` (signed state, 10-minute TTL, single-use
nonce, double user-pinning, server-side PKCE verifier) is exactly the machinery a login flow needs
and should be **copied**, not extended: `OauthCredential` deliberately refuses to persist `id_token`,
which is the one artifact login requires.

---

## 3. What "maximum coverage" actually means

Worth splitting, because the two halves have completely different cost curves.

**Self-serve coverage** — what an individual signing up cares about: Google (have it), Microsoft
personal/work accounts, GitHub, passkeys, magic link, TOTP MFA. All of these are OIDC or WebAuthn.
Cheap, low-risk, well-supported in Ruby.

**Enterprise coverage** — what a buyer's IT department demands: SAML 2.0 as a Service Provider
against *their* IdP, SCIM 2.0 provisioning/deprovisioning, per-domain SSO enforcement, audit trails.
Expensive, higher-risk, and the entire reason IdP vendors exist.

One clarification that matters for planning: **"login with Microsoft Teams" is not a thing.** Teams
is a client surface that federates to **Entra ID**. Signing in "with Teams" is an ordinary OIDC
authorization-code flow against `login.microsoftonline.com/{tenant}/v2.0`. What it *does* require
that Google does not:

- A **multi-tenant** app registration (`tenant_id` = `common`/`organizations`), not single-tenant.
- **Admin consent**: a customer's Global Administrator must grant tenant-wide consent via
  `/adminconsent` before their users can sign in. This is an onboarding flow we have to build, not a
  checkbox.
- The `tid` claim is the customer's tenant GUID — map it to a per-company IdP connection row. Use the
  immutable `oid` claim as the per-user key, never email.

---

## 4. The four candidate shapes

| Shape | What it means | Verdict against our three constraints |
|---|---|---|
| **A. Keycloak as the IdP** (CTO's proposal) | Keycloak owns users, credentials and login pages. Rails becomes an OIDC client. | Feature-complete and Apache-2.0, but replaces a user/org model we already own, kills our own login page, and is heavy for self-hosters. §7. |
| **B. A different all-in-one OSS IdP** | Zitadel / Logto / Authentik / Casdoor / FusionAuth in the same role as A. | Every one either has a worse license, a self-hosted paywall on the features we need, or a weaker org model. §6. |
| **C. Commercial CIAM** | WorkOS / Auth0 / Stytch / Clerk / Descope as a federation broker. | Technically the best-fitting option for the managed cloud and dead on arrival for the other two constraints. §5, kept as evidence. |
| **D. Rails-native + a protocol sidecar** | We keep the user/org model and the login page, build OIDC/passkeys/MFA in Rails, and offload **SAML + SCIM** to a self-hostable Apache-2.0 bridge. | **Recommended.** §9. |

---

## 5. Commercial CIAM — the market, and why it is out

Kept because the CTO will reasonably ask "why not just buy this". Prices are 2026 list.

| Vendor | Federation-broker fit | Self-host | 2026 pricing |
|---|---|---|---|
| **WorkOS** | Best in class — explicitly designed to sit next to your own users table; official Ruby gem | No (US-only residency) | AuthKit free to 1M MAU; **SSO and SCIM $125→$50/mo per connection each** ([pricing](https://workos.com/pricing)) |
| **Auth0 / Okta CIC** | Good, but Universal Login wants ownership; Classic Login deprecated | No | Free 25k MAU; B2B Essentials $150→$3,800/mo; +$100/mo per connection ([pricing](https://auth0.com/pricing)) |
| **Stytch** | Equivalent to WorkOS; headless SDK; official Ruby gem | No | Free 10k MAU + 5 connections; then $125/connection ([pricing](https://stytch.com/pricing)) |
| **Clerk** | Partial — architecture assumes Clerk owns the session | No | Free 50k MRU; Pro $25/mo; +$75→$15/mo per connection ([pricing](https://clerk.com/pricing)) |
| **Descope** | Good (BYO session, forkable login shell) | Login UI only | Free 7.5k MAU; Pro $249/mo; SCIM only at Growth $799/mo ([pricing](https://www.descope.com/pricing)) |
| **Frontegg** | Good (`customLoginBox`) | Claimed VPC, unverified | Free 7.5k MAU + 5 connections ([pricing](https://frontegg.com/pricing)) |
| **Kinde / PropelAuth / Scalekit / SSOJet** | Good; Kinde and PropelAuth flat-rate SSO instead of per-connection | PropelAuth BYO is genuinely self-hosted (not OSS, unpublished price) | Kinde $75/mo Plus for unlimited SSO; PropelAuth $150→$500/mo, SCIM $100/connection |
| **Corbado / Hanko** | Passkey specialists — **no SAML+SCIM combination**, wrong category | Hanko yes, but **AGPL-3.0** and no SCIM at all | Hanko free 10k MAU, SAML add-on $49/mo/connection |
| **Entra External ID / AWS Cognito** | Hyperscaler CIAM; Cognito has **no native SCIM** and no organization primitive | No | Cognito Essentials $0.015/MAU flat, no free tier ([pricing](https://aws.amazon.com/cognito/pricing/)) |

**Why they are out:** all of them, without exception, are SaaS-only for the component that matters.
Adopting one as *the* SSO path means self-hosted installations either lose enterprise SSO entirely or
have to sign up for our vendor — both of which contradict constraint #1, and the pricing contradicts
constraint #3.

**Worth carrying forward anyway:** the market's 2025-2026 track record is an argument against
vendor dependence in the login path generally. Auth0 has a documented post-acquisition pricing
backlash (a publicised 15.5x bill increase and a $200k/yr migration away). Stytch was **acquired by
Twilio** (announced Oct 2025) and is pivoting to AI-agent identity. Clerk had a free-tier metric
change backlash in Feb 2026 plus two outages with a public postmortem. WorkOS had a ~19-hour outage
in Oct 2025 during the AWS us-east-1 cascade. BoxyHQ was acquired by Ory. Passage (1Password's
passkey product) was **shut down outright** on 2026-01-16. Auth is a bad place to hold a dependency
you cannot run yourself.

---

## 6. Self-hostable OSS identity providers

| Product | License | OIDC | SAML SP | SAML IdP | Passkeys | SCIM | Native orgs | Headless | Footprint |
|---|---|---|---|---|---|---|---|---|---|
| **Keycloak** | Apache-2.0 | Yes | Yes | Yes | Yes (GA 26.4) | Experimental (26.6) | Yes (Organizations) | No | JVM, 1-2Gi/pod |
| **Zitadel** | **AGPL-3.0** (relicensed from Apache-2.0 at v3) | Yes | Yes | Yes | Mature | Inbound only | Yes, strong | Yes | Go, ~512MB |
| **Ory Kratos + Hydra** | Apache-2.0 core; **orgs/SAML/SCIM behind the proprietary Ory Enterprise License** | Yes | OEL only | OEL only | Yes | OEL only | No, in OSS | Yes, true API-first | Go, light |
| **Logto** | MPL-2.0 core; **SAML / IdP-init SSO / console MFA are paid even self-hosted ($199/mo)** | Yes | Yes | Yes | Mature | Not found | Yes, incl. domain routing | No (roadmap) | Node, own Postgres |
| **Authentik** | MIT core + proprietary EE | Yes | Yes | Yes | Mature | **Both directions** | No (Brands ≠ tenancy) | Partial — headless executor does not cover WebAuthn/OAuth | Django+Go, ≥2vCPU/2GB |
| **Casdoor** | **Apache-2.0, no gating** | Yes | Yes | Yes | Yes | Inbound | Native, org-centric | Yes (full REST API) | Go, 7+ DB engines |
| **SuperTokens** | Apache-2.0 core; **MFA/SAML/multi-tenancy metered even self-hosted** | Paid | SP only, paid | No | Yes | No | Paid | Yes | Java core |
| **FusionAuth** | **Proprietary source-available — redistribution prohibited** | Yes | Yes | Yes | Yes | Enterprise only | Tenants free | Yes | JVM |
| **Authelia** | Apache-2.0, no paid tier | **Beta** | No | No (planning) | Mature | None | None | No | Go, single binary |
| **Dex (CNCF)** | Apache-2.0 | Yes | Inbound connector only | No | No | None | None | No | Go, single binary |
| **Ory Polis** (ex-BoxyHQ SAML Jackson) | **Apache-2.0**; OEL only for advanced scaling/SLA | Yes (it *emits* OIDC) | **Yes** | Yes | n/a | **Yes, Directory Sync** | Tenant/product keyed | n/a — it has no login UI | Node, one container |
| **Janssen** (ex-Gluu) | Apache-2.0 (Linux Foundation) | Yes | via Shibboleth (unverified) | same | Component exists | Component exists | None | Hosted-login-first | Java+Python+Rust, heavy |

**Eliminated by constraint #3 or the Apache-2.0 distribution requirement:**

- **Zitadel** — the strongest product in the table, but AGPL-3.0 since v3, and Zitadel's own licensing
  FAQ states that running it *as a service* creates an obligation to share modifications. That is a
  live risk for the managed cloud, and the Apache-2.0→AGPL relicensing itself is a rug-pull precedent.
- **Logto** — a genuine self-hosted paywall on exactly the features we came for.
- **SuperTokens** — MFA, SAML and multi-tenancy are metered per-MAU even when you run it yourself.
- **FusionAuth** — source-available, not OSI-open; redistribution/embedding without a written
  agreement is explicitly prohibited, so we cannot ship it in our compose file.
- **Authelia, Dex** — clean licenses, wrong shape (reverse-proxy companion; broker with no user store,
  no SCIM, no MFA).

**Survivors for a bundled default: Keycloak, Casdoor, Authentik (MIT core), Ory Polis.**

One structural finding that cuts across all twelve: **none of them model B2B organisations the way we
already do** — companies, memberships with states, email-domain auto-join, invitation tokens,
impersonation, soft delete, super-admin bypass. Only Zitadel and Logto come close, and both are
disqualified above. Whatever we pick, **we keep owning the org layer.** That observation is what
makes shape D the natural one: the IdP is only needed for protocol plumbing *underneath* an org model
we are not going to give up.

---

## 7. Keycloak, evaluated on its merits

The CTO's proposal is not a bad one. Keycloak is the most feature-complete Apache-2.0 identity
product in existence and it covers our entire wishlist without custom code. The case against it here
is about *fit with an existing product*, not quality.

**What it gives us, verified:**

- Latest release **26.7.0** (2026-07-09), four minors a year, CNCF Incubating since 2023, Red Hat-backed.
- Identity brokering for Entra/Microsoft, Google and arbitrary OIDC/SAML — mature, native.
- **Passkeys went officially supported in 26.4.0** (Sept 2025), including Conditional UI
  ([announcement](https://www.keycloak.org/2025/09/passkeys-support-26-4)).
- Recovery codes as a first-class second factor (26.3), TOTP, WebAuthn, Email OTP.
- **Organizations** (stable since 26): org-scoped IdPs, verified domains with email-domain routing,
  invitations, an `organization` token claim. Conceptually a close match to our companies model.
- Account linking, device flow, token exchange, back-channel logout — all native.
- Apache-2.0, no feature paywall in the community build.

**What makes it the wrong shape for this codebase:**

1. **It replaces a user store we already own and like.** Our sign-in path enforces membership state,
   pending approval, soft delete and domain auto-join *before* creating a session. Keycloak wants to
   be the authority on "who may sign in"; we would either duplicate those gates or keep them in Rails
   and reduce Keycloak to a very expensive OIDC proxy.
2. **It takes the login page.** Passkeys and IdP brokering are redirect/browser-ceremony flows — they
   cannot run behind our own React form. The only way to keep our UI is Direct Grant (ROPC), which
   RFC 9700 says **MUST NOT be used**, which is gone in OAuth 2.1, and which cannot carry WebAuthn or
   brokering anyway. Realistic outcome: our login moves to Keycloak's pages, reskinned with
   [Keycloakify](https://www.keycloakify.dev/). That is a real product regression and a real project.
3. **Organizations do not do per-org theming.** Open feature request
   ([#47382](https://github.com/keycloak/keycloak/issues/47382)); groups are decoupled from orgs
   ([#34369](https://github.com/keycloak/keycloak/issues/34369)). A commercial vendor (Phase Two)
   exists specifically to sell the gaps — and their magic-link SPI is **Elastic License v2**, not
   OSI-open, which we should not bake into an Apache-2.0 product.
4. **SCIM is experimental and API-only** as of 26.6 (April 2026) — no admin UI, no bulk ops, no
   Organizations integration, no committed GA date. The old third-party option
   (`scim-for-keycloak`) is proprietary and its open-source edition is **end-of-life**.
5. **Magic links are still not native** — a custom SPI or the Elastic-licensed Phase Two extension.
6. **The upgrade treadmill.** There is **no community LTS**; each community minor is the patched
   branch for roughly three months ([endoflife.date](https://endoflife.date/keycloak)). LTS exists
   only in the Red Hat build, which is not sold standalone. CVE-2025-3501 (CVSS 8.2) forced a
   same-week patch cycle for self-hosters this year.
7. **Self-hosters get the worst of it.** JVM, 512MB minimum and realistically 1-2Gi, 30-60s cold
   start, no first-party production docker-compose, a documented "overkill for a single app"
   reputation, and a supply-chain scare already delivered (Bitnami moved its free Keycloak images to
   an unpatched `bitnamilegacy` archive in 2025). Our `docker compose up` story degrades from "one
   Rails app and a Postgres" to "…and a JVM identity server you must patch quarterly".
8. **Migration is not a config change.** Keycloak hashes with SHA-256/512/Argon2, **not bcrypt** —
   importing our `has_secure_password` digests needs a custom `PasswordHashProvider` SPI, or a forced
   password reset for every password user. Existing Google users need their `provider`/`uid` mapped
   into Keycloak `federated_identity` rows or they get an unexpected account-linking prompt.

**Where Keycloak would be right:** if we decide we no longer want to be in the identity business at
all — if the org model moves into Organizations, the login page moves to Keycloakify, and a dedicated
person owns the upgrade cadence. That is a strategic decision about what this team maintains, not a
component swap. Nothing in the current constraints forces it, and constraint #2 (no deadline
pressure) means we do not have to buy our way out of work we can stage.

**Also note the Rails side is weak:** there is no dominant maintained "Keycloak for Rails" gem. The
generic path is `omniauth_openid_connect` (stalled since 2024-07, several 2026 forks) or the
lower-level `openid_connect` (actively released, 2.5.0 in June 2026), plus hand-rolled back-channel
logout — because an admin revoking a Keycloak session does **not** invalidate our Rails cookie.

---

## 8. The Rails-native path

**Gem health, verified against RubyGems release dates and GitHub advisories:**

| Gem / package | Version | Last release | Verdict |
|---|---|---|---|
| `omniauth` | 2.1.4 | 2025-10-01 | Mature. Three CVEs ever, none since 2022. |
| `omniauth-entra-id` | 3.1.1 | 2025-09-12 | The maintained successor to `omniauth-azure-activedirectory-v2`. Multi-tenant by default, folds `tid` into the UID. **Use this for Microsoft.** |
| `openid_connect` | 2.5.0 | 2026-06-03 | Actively released; the better foundation for a generic connector. |
| `omniauth_openid_connect` | 0.8.0 | 2024-07-04 | Stale ~2 years. Has PKCE and discovery, no back-channel logout. |
| `ruby-saml` | 1.18.1 | 2025-07-29 | Currently patched — see the advisory table below. |
| `omniauth-saml` | 2.2.5 | 2026-02-21 | Pins `ruby-saml ~> 1.18`. |
| `webauthn` (cedarcode) | 3.4.3 | 2025-10-23 | De facto standard, 40M+ downloads. **Use this for passkeys.** |
| `devise-passkeys` | 0.3.0 | 2023-08-19 | Stale and Devise-coupled. We have no Devise. **Skip.** |
| `@simplewebauthn/browser` | 14.x | 2026-09 | Actively maintained, framework-agnostic, no React wrapper needed. |
| `rotp` / `rqrcode` | 6.3.0 / 3.2.0 | 2023 / 2026-01 | TOTP is a frozen algorithm; release-staleness is not risk here. |
| `scimitar` | 2.15.0 | 2026-03-05 | The only maintained Rails-idiomatic SCIM Service Provider. Single-maintainer bus factor. |

**The SAML problem.** This is the single most important technical finding in the document.

| Advisory | Date | Severity | Affected | Mechanism |
|---|---|---|---|---|
| [GHSA-jw9c-mfg7-9rx2](https://github.com/SAML-Toolkits/ruby-saml/security/advisories/GHSA-jw9c-mfg7-9rx2) / CVE-2024-45409 | 2024-09-10 | Critical 9.9 | ≤1.12.2, 1.13.0-1.16.0 | XML Signature Wrapping — signature verified via an XPath selector not bound to the signed node. Confirmed exploitable against gitlab.com SSO. |
| [GHSA-4vc4-m8qh-g8jm](https://github.com/SAML-Toolkits/ruby-saml/security/advisories/GHSA-4vc4-m8qh-g8jm) / CVE-2025-25291 | 2025-03-12 | Critical | <1.18.0 | Parser differential: ReXML and Nokogiri disagree on DOCTYPE, so the signature-checking parser and the assertion-reading parser see different documents. |
| [GHSA-754f-8gm6-c4r2](https://github.com/SAML-Toolkits/ruby-saml/security/advisories/GHSA-754f-8gm6-c4r2) / CVE-2025-25292 | 2025-03-12 | Critical | <1.18.0 | Same class, via namespace handling. GitHub published [a writeup](https://github.blog/security/sign-in-as-anyone-bypassing-saml-sso-authentication-with-parser-differentials/) showing the bug class across multiple languages. |
| GHSA-92rq-c8cf-prrq / CVE-2025-25293 | 2025-03-12 | Moderate | <1.18.0 | DoS via compressed response. |
| GHSA-rrqh-93c8-j966 | 2025-07-29 | Moderate | <1.18.1 | DoS via large response. |
| [GHSA-9v8j-x534-2fx3](https://github.com/SAML-Toolkits/ruby-saml/security/advisories/GHSA-9v8j-x534-2fx3) / CVE-2025-66567 | 2025-12-08 | Critical 9.3 | <1.18.0 | Explicitly **"an incomplete fix for CVE-2025-25292"**. |
| [GHSA-x4h9-gwv3-r4m4](https://github.com/SAML-Toolkits/ruby-saml/security/advisories/GHSA-x4h9-gwv3-r4m4) / CVE-2025-66568 | 2025-12-08 | Critical 9.3 | <1.18.0 | libxml2 canonicalisation returns an empty string on malformed XML instead of failing; ruby-saml then accepts a digest computed over that empty string. Digest bypass and signature replay. |

Read that as: **five Critical full-authentication-bypass disclosures in fifteen months**, in three
separate rounds, each a new angle on the same structural hazard — two XML parsers, one document, one
trust decision. `ruby-saml` 1.18.1 is not vulnerable to any disclosed advisory *today*, and there is
no credible alternative Ruby SAML SP. "Safe in 2026" therefore means safe only under a standing
same-week patch SLA. This is the strongest argument in the whole document for **not putting a SAML
parser inside our Rails process.**

Note honestly: this is not a Ruby problem. GitHub's writeup found the same parser-differential class
in SAML libraries across several languages. Moving SAML elsewhere does not make it safe — it makes it
**someone else's dependency to patch, in a separate process, with a blast radius that is not our web
app**.

**Effort, if we build everything in Rails:**

| Workstream | Build | Ongoing/yr |
|---|---|---|
| Multi-identity table + Entra + generic OIDC per-company connections | 5-7 weeks | 0.5-1 |
| Passkeys (ceremonies, credential model, conditional UI, recovery) | 3-4 weeks | 0.5 |
| **SAML SP, per-company** | **4-6 weeks** | **1-2** |
| SCIM inbound (`scimitar`) | 3-4 weeks | 0.5-1 |
| MFA/TOTP + magic links + recovery codes | 1.5-3 weeks | 0.25 |
| Server-side `Session` model + revocation + auth audit log | 1-2 weeks | 0.25 |
| **Total** | **~18-26 eng-weeks** | **~3-5 weeks/yr** |

SAML is roughly 25% of the build and **40% of the perpetual cost**.

---

## 9. Recommendation

**Shape D: keep the org layer and the login page in Rails; build the OIDC/passkey/MFA layer in Rails;
put SAML and SCIM behind a self-hostable Apache-2.0 sidecar.**

Concretely:

1. **Rails stays the system of record.** Users, companies, memberships, invitations, domain auto-join,
   impersonation, gates. We already have this and no IdP on the market models it better.
2. **Rails keeps the login page.** Which means passkeys work the way we want, and branding is ours.
3. **OIDC-family providers go in Rails**: `omniauth-entra-id` for Microsoft, `openid_connect` for
   generic per-company OIDC connections. Both are ordinary, low-risk work on maintained gems.
4. **SAML (and SCIM directory sync) goes to [Ory Polis](https://github.com/ory/polis)** — the former
   BoxyHQ SAML Jackson, acquired by Ory in 2025. Verified directly: **Apache-2.0**, SAML/OIDC
   enterprise SSO *and* SCIM 2.0 Directory Sync in the open-source edition; the Ory Enterprise License
   covers only advanced scaling, strict-SLA patching and support. It has no user store and no login
   UI — it is a **SAML→OIDC bridge**, which is exactly the thin thing we want. Rails speaks one
   protocol (OIDC) to it and never parses XML.
5. **Self-hosters get the same thing we run.** One extra container in an optional compose profile,
   only needed by installations that actually want SAML. Constraint #1 satisfied at zero licence cost.

**Why this beats Keycloak given our constraints:** it costs us nothing we already own, keeps our
login UI, keeps our org model, adds one small container instead of a JVM identity server on a
quarterly upgrade treadmill, and removes the highest-risk component (`ruby-saml`) from our process.
Keycloak's advantages — Organizations, a hosted account console, brokering out of the box — are
advantages over *having nothing*, and we do not have nothing.

**Why this beats building SAML ourselves:** §8's advisory table.

**Staged roadmap** (nothing here blocks on anything external, which fits constraint #2):

| Stage | Scope | Estimate | Unblocks |
|---|---|---|---|
| **0. Foundation** | `user_identities` table (many per user), server-side `sessions` table with revocation, auth audit log. Refactor `sessions#omniauth` to dispatch by provider. Migrate existing Google `provider`/`uid` rows. | 3-4 wk | Everything. Also fixes "sign out everywhere", which we cannot do today. |
| **1. Coverage that pays off immediately** | Microsoft/Entra (multi-tenant + admin-consent onboarding), generic per-company OIDC connections (`company_idp_connections` with discovery URL, client id, encrypted secret, `external_tenant_id`), GitHub if wanted. | 4 wk | The bulk of "more login options". |
| **2. Passwordless** | Passkeys (`webauthn` + `@simplewebauthn/browser`), TOTP + recovery codes, magic links on `generates_token_for` with login-grade single-use/short-expiry semantics. | 4-5 wk | Product differentiation; lets us start deprecating passwords. |
| **3. Enterprise** | Ory Polis sidecar: SAML SP per company, consumed as OIDC. Compose profile + Helm chart for self-hosters. | 2-3 wk | Enterprise deals, without a SAML parser in our process. |
| **4. Provisioning** | SCIM inbound — either Polis Directory Sync webhooks into our membership model, or `scimitar` if we want to own the endpoint. Decide after Stage 3 measures Polis in practice. | 3-4 wk | Enterprise deprovisioning requirements. |

Roughly **16-20 engineer-weeks** versus 18-26 for all-Rails, and it takes the 1-2 weeks/yr `ruby-saml`
maintenance burden off the team permanently.

**The escape hatch matters.** Because every external IdP is consumed as plain OIDC behind one seam,
swapping Polis for Keycloak, Casdoor or Authentik later — or, if the constraints ever change, for
WorkOS — is a connector change, not a re-platforming. Building shape D does not foreclose shape A;
adopting shape A now forecloses everything else.

**If the CTO's preference wins anyway:** the least-bad Keycloak adoption is as a **broker only** —
Keycloak holds no users, only IdP connections, and Rails stays the system of record. That keeps our
gates and org model intact and makes the bcrypt migration problem disappear. It is still a JVM on the
quarterly treadmill for a job Polis does in one Node container, but it is survivable, and it is what
we should argue for if we end up there.

---

## 10. Security findings that apply no matter what we choose

These are independent of the vendor decision and should be treated as requirements.

1. **Email is currently the cross-IdP join key and `email_verified` is never checked**
   (`google_omni_auth_service.rb:28`). With one trusted provider this is fine. The moment a second
   IdP can assert an email address, whoever controls *any* accepted IdP for a domain inherits the
   matching account. Requirement: match on `(provider, subject)` first; fall back to email **only**
   when the provider asserts `email_verified` **and** the domain is verified for the company that
   owns the connection.
2. **Validate issuer per connection.** For Entra, pin `iss` and the `tid` claim to the company's
   connection row and key users on the immutable `oid`, never on email or UPN.
3. **There is no server-side session record.** `session[:user_id]` in a cookie means an admin cannot
   revoke a session, a user cannot sign out everywhere, and SCIM deprovisioning cannot actually cut
   off access until the cookie expires. This becomes a compliance problem the first time an
   enterprise asks. Stage 0 fixes it.
4. **Copy `Oauth::State`, do not reinvent it.** Signed state, short TTL, single-use nonce, PKCE
   verifier held server-side — the login flow needs all of it and we already have a hardened
   implementation to model on.
5. **Rate-limit every new credential surface.** `rack-attack` is already in the Gemfile; magic links,
   TOTP verification and password auth all need explicit rules.
6. **Magic links are not invitations.** Invitation tokens are 7-day, reusable-until-consumed. A login
   magic link needs 5-15 minute expiry, hard single-use enforcement, and session-fixation-safe
   redemption.

---

## 11. Open questions and spikes

| # | Question | How to settle it |
|---|---|---|
| 1 | Does Polis's OSS edition support enough multi-tenancy for per-company connections? The README gates "advanced scaling and multi-tenancy support" behind the OEL without defining the line. SAML Jackson's core design is tenant/product-keyed, so this is *probably* fine, but it is decision-critical. | Half-day spike: run the container, create two tenants with distinct SAML connections via the API, complete both flows. |
| 2 | Does Polis Directory Sync cover our SCIM needs, or do we still want `scimitar`? | Defer to Stage 4, after Stage 3 gives us operational experience. |
| 3 | Polis's own SAML parsing risk. It moves the hazard out of our process, but it is still a SAML parser. | Check its advisory history and release cadence before Stage 3; subscribe to its GHSA feed. |
| 4 | Does keeping our own login page survive contact with enterprise buyers who expect IdP-initiated SSO? | IdP-initiated flows are a Polis feature; confirm during the Stage 3 spike. |
| 5 | Casdoor as an all-in-one alternative to Polis if Polis disappoints. Apache-2.0 throughout, SAML both directions, full REST API. Caveats: its Ruby SDK is effectively dead (irrelevant — we would use plain OIDC), and there is an unresolved third-party advisory on its SCIM endpoint ([Doyensec](https://doyensec.com/resources/Doyensec_Advisory_UnauthenticatedSCIM-CasdoorIdP.pdf)) with no matching entry on Casdoor's own GHSA page. | Read the advisory before considering it. |
| 6 | Do we ever want to *be* an OIDC provider (so customers' tools can log in with Aixle)? | Out of scope here. If yes, Ory Hydra (Apache-2.0, certified AS, no Kratos and no OEL needed) sits on top of our own user model — the lowest-risk option on the list. |

---

## 12. Sources

Keycloak: [26.7.0 release](https://www.keycloak.org/2026/07/keycloak-2670-released) ·
[passkeys GA](https://www.keycloak.org/2025/09/passkeys-support-26-4) ·
[SCIM experimental](https://www.keycloak.org/2026/04/scim-as-experimental-feature) ·
[Organizations](https://www.keycloak.org/2024/06/announcement-keycloak-organizations) ·
[no LTS](https://github.com/keycloak/keycloak/discussions/25688) ·
[support windows](https://endoflife.date/keycloak) ·
[Quarkus migration](https://www.keycloak.org/migration/migrating-to-quarkus) ·
[sizing](https://www.keycloak.org/high-availability/multi-cluster/concepts-memory-and-cpu-sizing) ·
[Keycloakify](https://www.keycloakify.dev/) · [ROPC deprecation](https://github.com/keycloak/keycloak/issues/30226)

SAML advisories: [ruby-saml security advisories](https://github.com/SAML-Toolkits/ruby-saml/security) ·
[GitHub parser-differential writeup](https://github.blog/security/sign-in-as-anyone-bypassing-saml-sso-authentication-with-parser-differentials/)

Self-hostable IdPs: [Ory Polis](https://github.com/ory/polis) ·
[Ory Enterprise License](https://www.ory.com/docs/self-hosted/oel) ·
[Zitadel relicensing](https://github.com/zitadel/zitadel/discussions/9529) ·
[Zitadel licensing FAQ](https://help.zitadel.com/zitadel-licensing-faqs) ·
[Logto self-hosted plans](https://logto.io/self-hosted-plans) ·
[Authentik SCIM](https://docs.goauthentik.io/docs/users-sources/sources/protocols/scim/) ·
[Authentik headless executor](https://docs.goauthentik.io/docs/add-secure-apps/flows-stages/flow/executors/headless) ·
[SuperTokens pricing](https://supertokens.com/pricing) ·
[FusionAuth license](https://fusionauth.io/license) ·
[Casdoor](https://casdoor.ai/docs/basic/public-api/) ·
[Authelia roadmap](https://www.authelia.com/roadmap/) ·
[Dex connectors](https://dexidp.io/docs/connectors/)

Commercial CIAM pricing: [WorkOS](https://workos.com/pricing) · [Auth0](https://auth0.com/pricing) ·
[Stytch](https://stytch.com/pricing) · [Clerk](https://clerk.com/pricing) ·
[Descope](https://www.descope.com/pricing) · [Frontegg](https://frontegg.com/pricing) ·
[Kinde](https://kinde.com/pricing/) · [PropelAuth](https://www.propelauth.com/pricing) ·
[Cognito](https://aws.amazon.com/cognito/pricing/) ·
[Entra External ID](https://learn.microsoft.com/en-us/entra/external-id/external-identities-pricing)

Market events: [Twilio acquires Stytch](https://www.twilio.com/en-us/blog/company/news/twilio-to-acquire-stytch) ·
[Clerk outage postmortem](https://clerk.com/blog/2026-03-10-service-outage-postmortem) ·
[WorkOS Oct 2025 disruption](https://workos.com/blog/service-disruption-on-october-20-2025) ·
[Auth0 pricing backlash](https://securityboulevard.com/2025/09/auth0-pricing-explained-and-why-startups-call-it-a-growth-penalty/)
