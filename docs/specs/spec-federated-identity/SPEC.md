---
id: SPEC-federated-identity
companions:
  - ../../planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md
  - ../../design/federated-identity.md
sources:
  - ../../research/technical-federated-identity-and-sso-provider-research-2026-09-16.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete contract for what to build, test, and validate. The spine holds the enforceable invariants (`AD-1`..`AD-18`) and every diagram; the RFC holds the current-state audit, phasing and the alternatives that were declined. Source documents are traceability only.

# Federated identity and SSO

## Why

A pain, and an opportunity behind it. Today a person can prove who they are two ways — a Google account or a password — and the schema allows exactly one external identity per user, with providers registered as boot-time constants. That caps what we can sell (an enterprise buyer's IT department cannot connect their own identity provider), and it carries two live defects: email is the cross-provider join key with no verification check, so a second provider would become an account-takeover path, and a session is only a cookie, so nothing can revoke access once granted. The same work fixes both and opens the enterprise door, and it must land in a product that is Apache-2.0 and run by strangers as often as by us.

## Capabilities

- **CAP-1** — foundation
  - **intent:** A person holds several distinct sign-in identities on one account, and any session they hold can be listed and revoked.
  - **success:** A user who has signed in through two different providers has two identity records and one account, with neither overwriting the other; revoking a session ends its access on the session's next request.

- **CAP-2** — company auth policy
  - **intent:** A company admin chooses which authentication methods are accepted for entry into their company, and cannot strand a member by doing so.
  - **success:** Disabling a method stops it satisfying entry on the next request and leaves the member's access to other companies untouched; an edit that would leave any active member with no usable method is refused and names them; deleting a connection is refused on the same terms as disabling it.

- **CAP-3** — Microsoft and generic OIDC
  - **intent:** A person signs in with a Microsoft work or school account, and a company connects its own OIDC provider.
  - **success:** A user from a customer's Entra tenant completes sign-in and lands in that customer's company; an assertion minted for a different tenant is rejected rather than falling back to an email match.

- **CAP-4** — passwordless and second factors
  - **intent:** A person signs in without a password — a passkey, a one-time code, or an emailed link — and can add a second factor.
  - **success:** A user registers a passkey and later signs in with no password entered; an emailed sign-in link works exactly once and expires in minutes, not days; a company that stops accepting passkeys has not deleted anyone's passkey.

- **CAP-6** — directory provisioning
  - **intent:** A customer's directory provisions and deprovisions members of their company automatically.
  - **success:** Deprovisioning at the customer's directory revokes the membership through the same audited transitions the UI produces, and the person loses access on their next request.

## Constraints

- Enterprise SSO must work for self-hosted installs. Nothing in the login path may require an account with a vendor, and no paid dependency may sit in it. This is what eliminates the entire commercial CIAM market from the decision.
- The product is Apache-2.0 and publicly redistributed: a bundled component must be redistributable, and anything run in the managed cloud must not create copyleft-as-a-service obligations. This is what eliminates the AGPL and source-available identity products.
- Rails remains the system of record for users, companies, memberships and sessions. The existing login page and organization model survive.
- Company policy is enforced at company entry with step-up re-authentication, re-evaluated every request — never at the login screen, which cannot know which company a person is heading for.
- The default self-hosted footprint stays one Rails app and a Postgres. A self-hoster who does not want SAML gains no service to run.
- At the CAP-1 cutover every live cookie session is invalidated once. One forced global re-authentication is accepted; no legacy proof shape is built.
- A passkey is the user's credential. Registration, listing and deletion belong to the user alone; a company may decline to accept one but may not destroy it.
- A `super_admin` bypasses every company auth surface — it satisfies any company without a proof and is never counted as a stranded member — and in exchange may authenticate **by password only**. No OIDC, no SAML, no passkey, no magic link, whatever the deployment allowlist or a company policy says.
- Every Rails, test and migration command runs inside the `web` container, and the full check suite must be green before a branch is pushed.

## Non-goals

- Becoming an OIDC provider for customers' own tools.
- Replacing `companies` / `company_memberships` with a vendor's organization model — no evaluated product models this domain better.
- SAML. Enterprise SSO is per-company OIDC, which every identity provider our customers run speaks. Supporting SAML means either `ruby-saml` in the web process (five Critical authentication-bypass advisories in fifteen months) or a second service to deploy — and neither is worth what it buys. CAP-5 was built, measured and removed; a test keeps the gem out of the lockfile.
- Adopting Keycloak as the primary identity provider. It was evaluated on its merits and declined on fit; the broker-only fallback shape is recorded in the RFC §6.
- Additive MFA ("SAML *and* TOTP"). The proof test is deliberately OR-only; making it conjunctive later is a one-predicate change.
- Per-company login-page branding beyond the existing `Company#branding`.

## Success signal

A customer's IT department connects their own identity provider, restricts their company to accept only it, and a contractor on a foreign email domain has no other way in — while a self-hosted operator reaches the same outcome with containers they run themselves, no vendor account, and no bill.

## Assumptions

- Scale is low thousands of monthly active users, B2B. Nothing depends on this, but it is why no session-store tier or sharding is considered.

## Open questions

- IdP-initiated SSO inverts the "authenticate, then enter a company" order the entry gate assumes. **Withdrawn with CAP-5:** per-company OIDC is SP-initiated, so nothing in the shipped flow starts at the identity provider. It returns only if SAML ever does.
