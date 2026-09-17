---
review: version-reality
reviewer: reviewer-gate lens #1 (version/reality-check)
target: docs/planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md
date: 2026-09-17
method: >
  Repository-first verification (Gemfile, Gemfile.lock, .ruby-version, package.json) for everything
  claimed to exist in-repo; WebFetch of rubygems.org/npmjs.org registry JSON and github.com for
  every "to add" dependency and for Ory Polis, since WebSearch budget was exhausted for this session.
  No `ruby`/`bundle`/`rails`/`rake` commands were run; all repo checks used cat/grep/sed only.
---

# Review: Version & Reality Check — Federated Identity Architecture Spine

## Verdict

**PASS with two flags.** Every version number in the Stack table checks out against either the
repository itself or the live package registry — nothing found to be stale, invented, or
mismatched. The two open items are (1) Ory Polis is the one dependency in the table with no
version pin at all, which is a materially different kind of claim than everything around it, and
(2) one existing gem the design diagram actually depends on (`omniauth-google-oauth2`) is missing
from the Stack table entirely.

## Findings

- **MEDIUM — Ory Polis carries no version pin, unlike every other new dependency in the table.**
  Every other "to add" row (`omniauth-entra-id`, `openid_connect`, `webauthn`, `@simplewebauthn/browser`,
  `scimitar`) names an exact version, and every one of those exact versions is independently
  confirmed live (see Verified table below). Polis's row reads "Apache-2.0 sidecar, pinned at
  adoption (STAGE-3)" — no version, not even a floor/reference version as of doc date. AD-8 ("SAML
  never enters the Rails process") and AD-9 (sidecar reachability/database split) bind the *entire*
  SAML strategy to this one piece of software, so the one row with no version is also the row
  carrying the most architectural weight. I confirmed independently (github.com/ory/polis, fetched
  live) that the repo is real, Apache-2.0, 2.3k stars, and that its docs do state an Ory Enterprise
  License is required for "advanced scaling and multi-tenancy" — exactly what the spine's own Open
  Question #1 already flags. So this is a **disclosed** risk, not a concealed one, and deferring the
  exact tag to adoption time is defensible for a sidecar (you don't want to hand-pin a container tag
  months before you build against it). But as written, "pinned at adoption" is a process promise,
  not a version claim — nothing here was reality-checked against a specific release, only the
  project's existence and license. Recommend the spine at minimum record the version current as of
  research date (there is one — the research doc doesn't cite a Polis release number either) or
  explicitly say why it's exempt from the same pinning discipline every other row got.

- **LOW — Stack table omits `omniauth-google-oauth2`, a technology the design diagram itself keeps in play.**
  The paradigm diagram routes `google` through `Methods::Oidc` alongside microsoft/generic/saml, and
  AD-2's own "prevents" clause cites `google_omni_auth_service.rb:28` as existing code the new
  adapter replaces. `omniauth-google-oauth2` (1.2.3) is already in Gemfile.lock and is the gem that
  makes the existing Google flow work — it doesn't disappear under the new architecture, Google just
  moves behind the new adapter. It should be a Stack table row like `omniauth` is (marked
  "present"), not left out. Not a version-accuracy problem (nothing false is claimed), just an
  incomplete inventory in a table whose whole job is to be the version inventory.

- **INFO — Everything else checked is accurate.** See the two tables below for the line-by-line
  evidence. No stale, fabricated, or mismatched version found among Ruby/Rails/omniauth/rotp
  (in-repo) or omniauth-entra-id/openid_connect/webauthn/scimitar/@simplewebauthn-browser (registry).
  The `rotp` "already in the Gemfile, currently unused" claim is correct on both halves. The
  Consistency Conventions row citing `Encryptable`, `rack-attack`, `Audited::Audit`, and
  `Oauth::State`'s shape all match real, existing code exactly as described — none of these are
  invented machinery.

## Verified against the repository

| Claim | Spine says | Found | Verdict |
| --- | --- | --- | --- |
| Ruby | 4.0.6 | `.ruby-version` → `ruby-4.0.6` | Match |
| Rails | 8.1.3.1 | `Gemfile:6` `gem "rails", "~> 8.1.3"`; `Gemfile.lock:531` `rails (8.1.3.1)` | Match |
| omniauth | 2.1.4 (present) | `Gemfile:24` `gem "omniauth"`; `Gemfile.lock:456` `omniauth (2.1.4)` | Match |
| rotp | 6.3.0, already in Gemfile, currently unused | `Gemfile:185` `gem "rotp", "~> 6.3"` (exact line cited in spine is correct); `Gemfile.lock:600` `rotp (6.3.0)`. `grep -rniE "rotp" app lib config` → **zero hits** in `app/`, `lib/`, or `config/`. | Match — both halves confirmed |
| rack-attack | "already in the Gemfile" (convention row) | `Gemfile:52` `gem "rack-attack"`; `Gemfile.lock:513` `rack-attack (6.8.0)` | Match |
| `Encryptable` concern | exists, used by `OauthCredential` and `AgentCredential` | `app/models/concerns/encryptable.rb` exists; `app/models/oauth_credential.rb:7` and `app/models/agent_credential.rb:5` both `include Encryptable` (plus 5 other models: `Integration`, `ConfigItem`, `WebhookEndpoint`, `OauthClient`, `AzureDevopsInstallation/Subscription`) | Match |
| `Audited::Audit` for impersonation | used by the existing audit trail | `app/controllers/admin/users_controller.rb:31-49` — `impersonate`/`stop_impersonate` actions call `Audited::Audit.create!` with `action: "impersonate_start"/"impersonate_stop"` | Match |
| `Oauth::State` shape | "signed, short TTL, single-use nonce, user-pinned, PKCE verifier held server-side" | `app/services/oauth/state.rb`: signed via `Rails.application.message_verifier("oauth")`; `TTL = 10.minutes`; `#consume` reads-then-deletes the cache entry (single-use); `user_id` is written into both the signed payload and the cached side-data (double-pinned); `code_verifier` is only ever in the server-side cache entry, never in the signed/URL payload | Match, precisely |

## Verified against live package registries (WebSearch budget exhausted; WebFetch used instead)

| Gem/package | Spine claims | Registry says (fetched live) | Verdict |
| --- | --- | --- | --- |
| `omniauth-entra-id` | 3.1.1 | rubygems.org: latest is 3.1.1 (released 2025-09-12) | Match |
| `openid_connect` | 2.5.0 | rubygems.org: latest is 2.5.0 | Match |
| `webauthn` (cedarcode) | 3.4.3 | rubygems.org: latest is 3.4.3 (released 2025-10-23) | Match |
| `scimitar` | 2.15.0 | rubygems.org: latest is 2.15.0 (created 2026-03-05) | Match |
| `@simplewebauthn/browser` | 14.x | npm registry `dist-tags.latest` = 14.0.0 | Match |
| Ory Polis | "Apache-2.0 sidecar, pinned at adoption" (no version) | github.com/ory/polis: real, active, Apache-2.0, 2.3k stars; docs confirm OEL gates "advanced scaling and multi-tenancy features" | Project confirmed real; no version was claimed to check — see MEDIUM finding above |

None of the "to add" packages confirmed above are present in this repo's `Gemfile`/`Gemfile.lock`/
`package.json`/`yarn.lock` today (grepped for all five names/scopes — zero hits), consistent with
the spine correctly labeling them "to add" rather than already-installed.

## Not in scope for this lens

Line-number citations for existing-code problem statements outside the four items the review brief
named (`sessions_controller.rb:63`, `google_omni_auth_service.rb:28`, `auth_concern.rb:8-18/87-106`,
`invitations_controller.rb:27,114`, `company.rb`, `company_membership_state_machine.rb`) were not
re-verified here — that's a code-sweep-accuracy question for a different lens, not a
version/reality-of-named-technology question.
