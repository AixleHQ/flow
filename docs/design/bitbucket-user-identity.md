# Agents act as the user on Bitbucket

**Task:** #239 · **Status:** built · **Date:** 2026-11-20

Builds on [gitlab-user-identity.md](./gitlab-user-identity.md) (#238, built), the closer
precedent, and [github-user-identity.md](./github-user-identity.md) (#214, built). Read
GitLab's §2.1–§2.3, §4.1–§4.3 first: this document says only what Bitbucket changes.
Anything not mentioned here is the same as for GitLab. The Bitbucket integration itself is
[bitbucket-integration.md](./bitbucket-integration.md) (Cloud only, §1).

A user connects their own Bitbucket account. An agent can then ask for a token that acts as
that user, push commits authored by them and call the Bitbucket API in their name. The
platform provides the mechanism; a workflow's instructions decide when to use it.

## 1. Overview

Today Bitbucket connects only at the integration level (`Bitbucket::CredentialProvider`:
the Forge app's bot, or a pasted access token or API token). Every push, pull request and
comment from an agent is that account's.

This design adds, for Bitbucket Cloud:

1. **A Bitbucket connection per user** on the unified OAuth engine (`provider: "bitbucket"`,
   owner `User`), made with an OAuth client the operator registers.
2. **Consent:** `act_as_consents.provider` gains `bitbucket`; same two switches per project.
3. **Two tools,** `bitbucket_user_token` and `bitbucket_user_token_for(user_id)`, sharing
   `InternalTools::Concerns::UserTokenContext` with the GitHub and GitLab pairs: same
   checks, messages, masking and issuance records.
4. **Docs:** this document, the Bitbucket user guide, the tool reference, the operator notes.

Nothing changes for a deployment or a user that does not use it. The Forge app, token mode,
`Bitbucket::CredentialProvider` and `GitCredentials::Vendor` are not touched. The pull-request
tools (`pull_request_*`) and gates keep acting as the integration; switching them is out of
scope (task).

## 2. Approach

### 2.1 What a person's Bitbucket connection is

Bitbucket Cloud offers a person's identity to a third party in one way that works offline:
**OAuth 2.0 authorization code grant** against an *OAuth client* (called an *OAuth consumer*
in older documentation and in some workspaces) that a workspace owner registers
([Use OAuth on Bitbucket Cloud](https://support.atlassian.com/bitbucket-cloud/docs/use-oauth-on-bitbucket-cloud)).
I checked the alternatives:

| Option | Acts as the person? | Limited to the session's repositories? | Verdict |
|---|---|---|---|
| OAuth client, authorization code grant, access token + rotating refresh token | Yes | **No**: scopes only | **Chosen** |
| Workspace / project / repository access token | No: a bot of the workspace, project or repository; Premium plan for the first two | Yes | Rejected: not the person. Already the integration's token mode |
| Scoped API token | Yes | No: scopes only, and the person must create and paste one | Rejected: the task says through the OAuth engine; a pasted token also expires within a year and is one more secret to hold |
| Forge app, `asUser` | Yes | No | Rejected: Forge delivers a user's token only inside an invocation started by that user in Bitbucket; there is nothing to hold or refresh |
| OAuth client credentials grant | No: authenticates as the client's `app_user` | n/a | Rejected: not a person |
| App passwords | Yes | No | Gone (removed 2026-07-28, [bitbucket-integration.md](./bitbucket-integration.md) §2) |

**Who registers the client.** The operator, as for GitLab (D2). They create an OAuth client
under **Workspace settings → Apps and features → OAuth clients** in any Bitbucket workspace
they own, with:

- **Authorization:** *Authorization code* ticked (Bitbucket then also issues refresh tokens);
- **Callback URL:** `<PROTOCOL>://<DOMAIN>/oauth/callback`. A client holds one callback URL, so
  staging and production each need their own client, which matches how the Forge app is
  already registered per environment;
- **Scopes:** `account`, `email`, `repository`, `repository:write`, `pullrequest`,
  `pullrequest:write` (§2.2 for why each).

Its key and secret go to the deployment as `BITBUCKET_OAUTH_CLIENT_ID` and
`BITBUCKET_OAUTH_CLIENT_SECRET`, read as `Settings.bitbucket.oauth.client_id` /
`.client_secret` (added to `config/settings.yml`, `.env.example` and the deploy config in
one change, per the configuration rule). The keys stay nested, unlike GitLab's flat
`gitlab.oauth_client_id`, because the `bitbucket` section already groups each connection
method's settings (`bitbucket.forge`), and `oauth` is one more method; `Bitbucket::AppConfig`
reads them as `oauth_client_id` / `oauth_client_secret` all the same. The same deploy change
(`aixle-infra`) **removes the unused `BITBUCKET_OAUTH_SECRET` from `aixle-app-secrets`**. Without both, the feature is off: the tools are
unavailable and the profile card says so. This client is separate from the Forge app and
unrelated to how the integration connects.

**Which Bitbucket.** Bitbucket Cloud only, as the integration. Data Center has a different
OAuth provider (application links, different endpoints and scopes) and no integration here;
supporting it would be a new provider entry and a new adapter. Nothing in this design makes
that harder: the hosts live in the provider entry, not in the tools.

### 2.2 The one real difference from GitHub: the token cannot be narrowed to repositories

As on GitLab, **Bitbucket cannot limit a user's OAuth token to repositories.** Scopes are
fixed on the client, and a grant request cannot ask for fewer: Bitbucket validates that the
`scope` parameter adds nothing and otherwise ignores it. `repository:write` covers every
repository the person can write to, in every workspace. The design says so instead of
pretending, and bounds the token the way GitLab's does (decision D1, for the reviewer):

- **The person's own access.** It acts as them and can do nothing they cannot.
- **Consent per project:** nobody's token is issued without their yes for that project.
- **Lifetime.** An access token lives two hours (§2.4).
- **A coverage check.** The tool verifies, with the person's token, that they can write to
  each of the session's Bitbucket repositories (§4.2). One they cannot reach is listed in
  `skipped`. This informs the agent; it does not restrict the token.
- **Masking and audit.** Every issued token is recorded in `user_token_issuances` and masked
  as a session secret, unchanged.
- **The guide says it plainly:** a person allowing it allows their Bitbucket account in that
  project's sessions, not only its repositories.

Scopes, chosen as the least set that does what agents do (push, read and write pull
requests, set a commit identity):

| Scope | Why |
|---|---|
| `account` | `GET /2.0/user` for the identity, and the permission lookup in §4.2 |
| `email` | `GET /2.0/user/emails` for the commit address (D8) |
| `repository`, `repository:write` | Clone, fetch and push over HTTPS; a write scope does not imply read, so both |
| `pullrequest`, `pullrequest:write` | Open, comment on and merge pull requests with the API |

No `admin`, `delete`, `webhook`, `pipeline` or `issue` scope. The request omits `scope`
(registry `scopes: ""`, the engine drops an empty value, as for GitHub), because the client
decides.

### 2.3 Connection: one more registry entry, and one engine change

`Oauth::Providers::REGISTRY` gets a `bitbucket` entry, built on the GitLab one (§2.2 there):

```ruby
"bitbucket" => {
  issuer: "https://bitbucket.org",
  authorization_endpoint: "https://bitbucket.org/site/oauth2/authorize",
  token_endpoint: "https://bitbucket.org/site/oauth2/access_token",
  scopes: "",
  oauth_app: -> { { client_id: Bitbucket::AppConfig.oauth_client_id, client_secret: Bitbucket::AppConfig.oauth_client_secret } },
  owner_types: %w[User],
  client_auth: :basic,
  after_connect: ->(credential) { Bitbucket::UserConnection.record_identity!(credential) }
}
```

Compared with GitLab:

| GitLab | Bitbucket |
|---|---|
| Endpoints derive from `GITLAB_ENDPOINT`, the operator's host is trusted for the token call | Constants: Cloud only, `Bitbucket::AppConfig` already fixes the hosts. No `endpoints:` resolver, no `trust_endpoint_host`: the SSRF guard stays as it is |
| Connections are tied to one instance (issuer filter, `on_other_gitlab_instance`) | No such thing: there is one Bitbucket Cloud |
| Client secret in the request body | **Client credentials as HTTP Basic** (below) |
| `revocation_endpoint`, `Oauth::TokenService.revoke!` on disconnect | **None**: Bitbucket documents no revocation endpoint (§2.5) |

**The engine change: `client_auth: :basic`.** Bitbucket's token endpoint authenticates the
client with HTTP Basic (`-u "client_id:secret"`), and the engine only sends `client_secret`
in the form body (`Web::OauthController#exchange_code!`, `Oauth::TokenService.perform_refresh!`).
Bitbucket reads the client as the Basic username and password and is reported to ignore the
body, so without the change the exchange fails with `invalid_client`. The change:

- `Oauth::Providers.client_auth(provider)` returns the entry's `client_auth`, default `:post`.
- Both call sites, which already receive the provider, send `Authorization: Basic
  base64(client_id:client_secret)` for `:basic` and leave the secret (and `client_id`) out of the body.
- Nothing changes for any other provider. A test covers each mode.
- A third call site sends the client secret in the body: `Oauth::TokenService.revoke!`.
  Bitbucket has no revocation endpoint, so it is never reached for this provider. If Atlassian
  adds one, it must be sent with Basic client authentication as well; `revoke!` reads
  `client_auth` like the other two.

**Standard and library comparison (D4).** Basic client authentication is the standard
mechanism (RFC 6749 §2.3.1), and the `oauth2` gem (2.0.25, already in the bundle) implements it
(`auth_scheme: :basic_auth`). The engine nevertheless keeps its own token calls: they carry the
SSRF guards, `SafeHttp`, the trusted-host rule and the refresh lease, which the gem does not
provide, and moving all providers onto the gem is a larger change than this task. So the engine
gets a small `client_auth` switch now, and the move to the gem is a deferred question (§9).

RFC 9207: Bitbucket sends no `iss`, which `issuer_matches?` already accepts. PKCE is sent as
for every provider; Bitbucket is reported to accept it, and staging item S1 confirms it
(a refusal would add a `pkce: false` entry key, nothing more).

`refuse_user_connect?` (`Web::OauthController`) already covers every provider in `UserConnections::PROVIDERS`.

The `after_connect` lambda calls `Bitbucket::UserConnection.record_identity!`. It composes the
identity from `Api#current_user` and `Api#user_emails`, picks the primary confirmed address
(D8), and stores
`metadata["bitbucket_user"] = { id, nickname, name, avatar_url, commit_email, fetched_at }`
(`id` is the account UUID). A failed lookup raises `Oauth::TokenExchangeError`, the stored
identity is cleared and the credential kept, as for GitLab.

**Alternatives considered**

- *Reuse the Forge app's identity for users.* The app's tokens belong to the app's bot and
  arrive only by push. Rejected: not a person.
- *A dedicated table.* Same rejection as in the GitHub design (§2.1).
- *A per-company OAuth client entered in the UI.* More surface and more secrets to hold.
  Rejected for the reason GitLab gave: one deployment, one client.

### 2.4 Token lifetime and refresh

Bitbucket access tokens last two hours (the support documentation; the older developer page
says one hour, so the engine reads `expires_in` from the response and assumes neither).
Since 2026-05-04 refresh tokens **rotate**: each use returns a new one, and a refresh token
unused for three months expires, which then needs a full re-authorization
([announcement](https://community.developer.atlassian.com/t/oauth-2-0-and-api-authentication-changes-for-bitbucket-cloud/99003)).
That is the shape the engine already handles for GitHub and GitLab: `RefreshLease`, the
five-minute sweep, `mark_refresh_error!` and the reconnect email for User owners. The sweep
refreshes every active credential within 15 minutes of expiry, used or not, so an idle
connection does not reach the three-month limit. `apply_token_response!` stores the new
refresh token when one comes back; a test pins it for Bitbucket's response (`scope`, not
`scopes`).

**What the tool hands out** is GitLab's rule (§2.3 there), for the same reason: a person has
one token for all their sessions, and it is not documented whether a refresh ends the old
access token. Until S2 shows that it does not, the tool assumes it does:

1. `Oauth::TokenService.fresh(credential, skew: Oauth::TokenService::REFRESH_SKEW)`: refresh
   only within the 10-minute skew, as the sweep does.
2. `expires_at` in the result is the stored expiry minus `REFRESH_SKEW`, the moment to ask
   again. With a two-hour token the agent has between about 1 h 50 min and 10 min.
3. Two sessions of one user receive the same token until the next refresh. Each gets its own
   issuance row.

If S2 shows the old token keeps working after a refresh, the floor can be raised later with
no change to the result shape (deferred).

### 2.5 Masking, audit and disconnect

Masking and `user_token_issuances` are unchanged. The row stores the person's own OAuth
token (as GitLab's does, §2.4 there); `target_login` stores the host name `bitbucket.org`,
since there is no per-owner grouping and the column is not null.

**Disconnect does not revoke at Bitbucket,** because no revocation endpoint is documented.
`Bitbucket::UserConnection.disconnect!` destroys the person's `bitbucket` credentials (so the
refresh token is gone with them) and deletes their `act_as_consents` rows for the provider;
it does not call `Oauth::TokenService.revoke!`. Already issued access tokens work until they
expire, at most two hours. The authorization stays listed in the person's Atlassian account
until they remove it there; the user guide says so, and S6 finds where it is listed. This is
weaker than GitHub's and GitLab's disconnect, and is called out in R5.

## 3. Data model changes

- **No migration.** `act_as_consents.provider` and `user_token_issuances.provider` are plain
  strings. `ActAsConsent`'s `enumerize :provider, in: %w[github gitlab]` gains `bitbucket`.
- `OauthCredential`: `BITBUCKET_PROVIDER = "bitbucket"`; `IDENTITY_FIELDS` gains
  `"bitbucket" => { metadata_key: "bitbucket_user", login: "nickname" }`; scopes
  `bitbucket_connections_of`, `latest_bitbucket_connection_of`, `live_bitbucket_connection_of`
  (no issuer filter). `account_name` and `account_avatar_url` already read generic keys, so
  `name` and `avatar_url` are the stored keys.
- The identity sits outside `SAFE_METADATA_KEYS`, written by `record_identity!`, as for the
  others.

## 4. API / interface changes

### 4.1 `Bitbucket::UserConnection` and the `Bitbucket::Api` extension

`Bitbucket::UserConnection` mirrors `Gitlab::UserConnection`: `PROVIDER`, `LABEL = "Bitbucket"`,
`configured?` (`AppConfig.oauth_enabled?`: both values set), `record_identity!`,
`identity_for` (refetch when older than 24 hours), `commit_email(identity)`,
`latest_connection_of`, `disconnect!` (§2.5).

There is no second Bitbucket seam. `Bitbucket::Api` is the typed Bitbucket API and the one seam
tests replace (`FakeBitbucket::Api` is its canonical fake), so calls made with a person's token
extend it instead of adding a service and a fake of their own. `Bitbucket::Api` is instantiated
with the person's credential, `Bitbucket::Credential.new(kind: :access_token, ...)`. That kind
already behaves as the person's token does: Bearer headers, git username `x-token-auth`, no
refresher. No new credential kind. The host is `Bitbucket::AppConfig::API_HOST`, never one a
request names. One existing operation is extended and two are added, with the matching methods
on `FakeBitbucket::Api`:

- `current_user` (exists, `GET /2.0/user`): extended compatibly. It keeps `uuid`, `account_id`,
  `display_name` and `nickname`, and gains `avatar_url`. Nothing else about it changes, so
  `Bitbucket::IntegrationService` and its tests are unaffected, and the integration check
  never calls `/user/emails`. `username` is not used: Bitbucket removed it from user objects in
  its privacy changes.
- `user_emails`: `GET /2.0/user/emails`, one endpoint per operation as in the rest of
  `Bitbucket::Api`. Returns the person's addresses with their `is_primary` and `is_confirmed`
  flags. Pages are followed.
- `repository_permissions(full_names)`: for each workspace among the names, one
  `GET /2.0/user/workspaces/{workspace}/permissions/repositories` (documented in Bitbucket's
  OpenAPI spec as "List repository permissions in a workspace for a user", scopes `account` and
  `repository`; it is not the admin-only `GET /2.0/workspaces/{workspace}/permissions/repositories`).
  `q` is documented on `repository.name`, not `full_name`, so the call may filter by name and
  the code **matches `full_name` exactly**. Pages are followed. Returns
  `{ full_name => "admin" | "write" | "read" | nil }`. The cross-workspace form of this endpoint
  is gone (410 since 2026-04-14), hence per workspace. Only `admin` and `write` cover a
  repository. If the staging check (S4) shows a gap, `GET /2.0/repositories/{workspace}?role=contributor`
  (paginated, exact `full_name` match) is the fallback.

Errors map to `InvalidToken` (401), `Forbidden` (403, 404 and other refusals), `Unavailable`
(5xx, network, and a 429 that outlasted the client's own retries: the message says to retry in a
moment), from `Bitbucket::Error`. A user credential has no refresher, so `Bitbucket::Client`
raises on the first 401 and makes no retry. Nothing carries a token or a response body.

### 4.2 Tools

`InternalTools::BitbucketUserToken` and `BitbucketUserTokenFor`, built like the GitLab pair:

```ruby
tags :bitbucket_identity          # new TagCatalog entry, label "Bitbucket as a user", ui_visible: true
requires_integration :bitbucket
availability ->(_ctx) { Bitbucket::UserConnection.configured? }
unavailable_message "Connecting Bitbucket accounts is not configured on this installation."
```

Same `user_attachable`, no auto-injection, same consent rule and `user_id` resolution.

`InternalTools::Concerns::BitbucketUserTokenContext` includes `UserTokenContext` and supplies
the provider part, as `GitlabUserTokenContext` does:

- **Repositories:** `session.repositories` whose integration is Bitbucket and active. Both
  integration modes (Forge app, token) qualify; the integration's own credential is never
  used. None: "This session has no Bitbucket repositories on an active Bitbucket connection."
- **Coverage:** `repository_access` once per call. `write` or `admin` covers; anything else
  goes into `skipped` ("<name> cannot push to it"). None covered: refuse, naming them. On a 401 the tool
  calls `credential.mark_refresh_error!` (status `error` only at the third consecutive failure,
  with the reconnect email on that edge, as for GitLab) and refuses with the reconnect message,
  as `GitlabUserTokenContext` does. The tool never writes the status itself.
- **Identity:** usable only with `id`, `nickname` and `commit_email`. Without a confirmed
  email the tool refuses with a Bitbucket-specific message (it overrides `no_identity_message`):
  the person needs a confirmed email address on Bitbucket, which commits are made with.
- **Token:** §2.4. One entry, with `reported_expiry` as for GitLab.
- **Issuance:** one `UserTokenIssuance` row, then `SecretRegistry.publish!`; refuse if it fails.

Result:

```json
{
  "user": { "id": 82, "name": "Artem" },
  "identity": { "login": "artem", "bitbucket_uuid": "{…}", "name": "Artem", "email": "artem@example.com" },
  "tokens": [
    { "token": "…", "host": "https://bitbucket.org", "scopes": ["account", "email", "repository",
      "repository:write", "pullrequest", "pullrequest:write"],
      "git_username": "x-token-auth", "api_url": "https://api.bitbucket.org/2.0",
      "repositories": ["workspace/repo"], "expires_at": "2026-11-20T17:00:00Z" }
  ],
  "skipped": [],
  "note": "…"
}
```

`git_username` is `x-token-auth`: Bitbucket's documented username for an OAuth access token,
the same one `Bitbucket::Credential` gives the Forge app and access tokens. `GitCredentials::Vendor`
(which answers `oauth2` for non-GitHub hosts apart from its Bitbucket branch) is not touched:
the person's token never goes through it. REST calls use `Authorization: Bearer` against
`api_url`; since 2026-05-04 Bitbucket refuses a token in the query string or body, and refuses
tokens sent to `bitbucket.org` rather than `api.bitbucket.org`. The `note` adds that the token
is not limited to these repositories, and that REST calls with it spend the person's own
request quota (§7, R3).

### 4.3 Profile page and `UserConnections`

`UserConnections::PROVIDERS` gains `Bitbucket::UserConnection`. The page props are already
maps by provider after #238, so each gains a `bitbucket` key (`available`, `connections`,
`consents`) and the generated types change with them. `Connections.tsx` adds `bitbucket` to
`Provider` and `PROVIDERS` with `IconBrandBitbucket` and its copy: the not-configured message,
the disconnect text (which says the authorization stays listed in Atlassian), and the same
"not only in that project's repositories" warning GitLab shows.

## 5. Implementation steps

1. **Engine** (GitHub and GitLab behaviour unchanged).
   - `Oauth::Providers`: the `bitbucket` entry, `client_auth` and its helper.
   - `Web::OauthController#exchange_code!` and `Oauth::TokenService.perform_refresh!`: Basic
     client authentication for `:basic`.
   - `Bitbucket::AppConfig.oauth_client_id`, `oauth_client_secret`, `oauth_enabled?`;
     `config/settings.yml` (`bitbucket.oauth`), `.env.example`, deploy config.
2. **Connection.**    `Bitbucket::Api` and `FakeBitbucket::Api` (`current_user` gains `avatar_url`; `user_emails`, `repository_permissions` are new);
   `Bitbucket::UserConnection`; `OauthCredential` constants and scopes; `ActAsConsent` provider
   list; strict input in `ActAsConsentsController` (D12).
3. **Tools.** `BitbucketUserTokenContext`, the two tools, the `:bitbucket_identity` tag in
   `Tools::TagCatalog`. Steps 1–2 can merge alone, since nothing calls them.
4. **Profile.** `UserConnections`, resources (`rails typelizer:generate`), `Connections.tsx`
   and its test. Needs step 2.
5. **Docs.**
   - `docs/user-guide/bitbucket.md` and its mirror
     `app/frontend/pages/Docs/data/pages/bitbucket.md`: "Acting as yourself" (connect, the
     two switches, the tools, errors, the confirmed-email requirement, that the token is not
     limited to the session's repositories, that disconnect cannot revoke at Bitbucket and
     where to remove the authorization, the rate limit); the two rows in the tool tables
     (`docs/user-guide/tools.md` and its mirror).
   - `docs/operations/bitbucket-app.md`: a section on registering the OAuth client
     (callback URL, grant, scopes, one client per environment).
   - `docs/reference/configuration.md` and its mirror: the two variables.
   - `docs/user-guide/github.md` and `gitlab.md` "Acting as yourself": a pointer to
     Bitbucket. `github-user-identity.md` and `gitlab-user-identity.md`: their deferred
     "Bitbucket" bullets point here.
   - `CHANGELOG.md`: an entry under `### Added`, area **Integrations**
     (`docs/product/changelog-product-areas.md`).
   - `docs/index.md`: the design entry (this change); mark this design built in the
     implementation pull request.
6. **Staging check** (§6). No spike runs first. As with GitLab (#238, checked on staging in
   #266), the implementation uses the cautious defaults: Basic client auth, PKCE, no early
   refresh. S1–S8 are the checklist of the check against a real Bitbucket on staging.
   Prerequisites (Alex):
   - a staging OAuth client (callback `https://staging.flow.aixle.com/oauth/callback`,
     Authorization code, the scopes of §2.2);
   - its secret in SSM and its id in the config map, through an `aixle-infra` change that also
     removes the unused `BITBUCKET_OAUTH_SECRET` from `aixle-app-secrets`;
   - a Bitbucket account with write access to the staging test company's repository.

## 6. Testing approach

Following `docs/testing.md` (real database, app-owned seams, WebMock only in adapter
contract tests; no `any_instance`, no stubbing a vendor library).

- **Adapter:** the `Bitbucket::Api` tests, WebMock contract tests on `Bitbucket::Client` for
  `GET /2.0/user` (including `avatar_url`; the existing keys unchanged) and `GET /2.0/user/emails` (primary and confirmed, only an unconfirmed one, none), the
  per-workspace permission lookup (admin, write, read, absent, a non-admin caller, several
  workspaces, pagination, exact `full_name` match) and the error mappings including 429. Payloads taken from the OpenAPI spec.
- **Engine:** `test/services/oauth/providers_test.rb` for `client_auth`; a token exchange and a
  refresh with `:basic` send the Basic header and no secret in the body, while Sentry, Railway,
  GitHub and GitLab still send it in the body; the callback for a `User` owner connecting
  Bitbucket stores `metadata["bitbucket_user"]` and keeps the credential when the identity fetch
  fails; a refresh response with a rotated refresh token and `scope` is stored.
- **Models:** `ActAsConsent` accepts `bitbucket`; the connection scopes.
- **Tools:** `bitbucket_user_token_test.rb`, `bitbucket_user_token_for_test.rb` in the shape of
  the GitLab ones: every error, the consent matrix, a read-only repository in `skipped`,
  nothing covered refuses, no confirmed email refuses, a 401 raises the failure counter and refuses with the reconnect message (the third marks `error`), the refresh
  floor (under `REFRESH_SKEW` left is refreshed first, more is not), the issuance row, masking,
  no token in any error. Repositories in app mode and in token mode both qualify.
- **Refactor guard:** the GitHub and GitLab tool tests pass unchanged.
- **Requests / frontend:** `profile_connections_test.rb` for the third key in each prop, a
  Bitbucket consent update and disconnect (no revocation call); `Connections.test.tsx` for the
  third card.
- **Manual, on staging against real Bitbucket (acceptance):** connect with a user who is not a
  member of the OAuth client's workspace; push and open a pull request as that user with the
  token; a repository where the user has only read access appears in `skipped`; the same token
  value is returned twice inside a refresh window and a fresh one after the sweep; disconnect and
  confirm that the credential and consent rows are gone and that no call to Bitbucket was made
  (the refresh path cannot be observed: we hold no refresh token afterwards and do not revoke).

**Staging checklist, run against a real Bitbucket after the implementation merges** (it replaces
a spike before the implementation; a result that differs is a follow-up change).

| # | Question | If the answer differs |
|---|---|---|
| S1 | The token endpoint accepts Basic client auth with PKCE and `redirect_uri` in the body, and the authorize URL with PKCE and no `scope` | Adjust `client_auth`, add a `pkce` key |
| S2 | Does a refresh end the previous access token? What is `expires_in`? | If not: raise the refresh floor, as GitLab's R2 allows |
| S3 | The refresh response carries a new refresh token; the old one stops working | Already assumed; a different result changes `RefreshLease` expectations |
| S4 | `q` on the permission endpoint filters by `repository.slug` or `repository.full_name`; `OR` works | Filter by name and match `full_name` in code, or page the list |
| S5 | A user outside the client's workspace can authorize | Re-think who registers it |
| S6 | Where the person sees and removes the authorization; whether a refresh token survives deleting our row | Wording of the guide |
| S7 | Git over HTTPS with `x-token-auth` and the OAuth token pushes, and honours branch restrictions as the user | Adjust `git_username` |
| S8 | Rate-limit headers on user-token calls and what git over HTTPS counts toward | Wording of the guide and the note |

## 7. Edge cases & risks

- **R1. The token reaches everything the person can write to.** §2.2. Accepted only with the
  reviewer's agreement (D1); wider than GitHub's, the same as GitLab's.
- **R2. Refresh may revoke the previous access token.** Handled by the no-early-refresh rule
  (§2.4) until S2 says otherwise.
- **R3. The person's own request quota is spent by agents.** Bitbucket limits REST calls per
  user, 1,000 an hour on repository endpoints (more on large paid workspaces)
  ([limits](https://support.atlassian.com/bitbucket-cloud/docs/api-request-limits/)). The
  integration's calls are the bot's or the token's, so today agents never touch a person's
  quota; with this token they do, and the person's own work and every concurrent session of
  theirs share it. What bounds it: the platform itself makes one permission lookup per workspace
  per issuance and two identity calls a day; git over HTTPS is the intended path for code and
  the `note` says to prefer it over REST; a 429 reaches the agent as a retryable error, never a
  hang. There is no quota accounting per person (deferred); the user guide states the limit.
- **R4. The commit address is the person's real email.** Bitbucket has no noreply address, so
  commits expose the primary email to everyone who can read the repository's history (D8). The
  guide and the connect card say so; a person who does not want that does not connect.
- **R5. Disconnect cannot revoke the grant at Bitbucket** (§2.5): an issued access token lives up
  to two hours, and the authorization stays in the person's account until they remove it. We do
  not hold a refresh token afterwards.
- **R6. The consent screen shows on every authorization.** Reported by other integrators since
  late July 2026 ([report](https://community.developer.atlassian.com/t/bitbucket-cloud-oauth-consent-screen-shown-on-every-authorization-consent-no-longer-remembered/102357)).
  It only affects the connect and reconnect click; the design does not depend on it.
- **R7. Rotating refresh tokens fail hard on a lost response.** A refresh whose answer we never
  stored leaves the old token invalid. `RefreshLease` and the existing `mark_refresh_error!` path
  already treat this as "needs reconnect" for GitHub and GitLab; the reconnect email reaches the
  person.
- **R8. Naming.** Workspace UIs call the registration an *OAuth client* or an *OAuth consumer*.
  The operator notes use "OAuth client (OAuth consumer in older workspaces)".
- **R9. Same Bitbucket account for two Flow users** is allowed, as for GitHub and GitLab.
- **R10. Frontend contract change.** The profile page's props gain a key (§4.3); page, test and
  generated types move in one change.
- **R12. Rotating the OAuth client.** Credentials are keyed by `(issuer, client_id)`, and GitHub,
  GitLab and Bitbucket alike have no current-client filter. Rotating the client means deleting
  the old one at Bitbucket; the old connections then fail to refresh, end in `error` and their
  owners get the reconnect email. A current-client filter, if wanted, is one change for every
  provider (#275).
- **R11. Repositories in a workspace the person is not in.** A Forge-app integration can reach a
  workspace its user is not a member of; the lookup returns nothing for it and the repository is
  `skipped`, as intended.

## 8. Decisions & assumptions

| # | Decision | Source |
|---|---|---|
| D1 | The token is the user's own OAuth token, not narrowed to repositories, because Bitbucket offers no way to narrow it; the limits are consent, the user's own access, lifetime, the coverage check and masking. **For the reviewer to confirm.** | Task: "how the token is limited"; Bitbucket scopes (§2.2) |
| D2 | The operator registers one OAuth client per deployment; no per-company clients. | Task #238 precedent; one callback URL per client |
| D3 | Bitbucket Cloud only. Data Center is out of scope and not made harder. | `bitbucket-integration.md` §1 |
| D4 | The engine gains `client_auth: :basic`; nothing else in the engine changes for this provider (no trusted host, no instance filter, no revocation). | Bitbucket OAuth documentation; `Oauth::TokenService` |
| D5 | The refresh rule is GitLab's: refresh only within `REFRESH_SKEW`, report expiry minus the skew, until S2 proves a refresh keeps the old token valid. | gitlab-user-identity.md §2.3 R2 |
| D6 | Git username `x-token-auth`; the token does not pass through `GitCredentials::Vendor`. | Bitbucket OAuth documentation; `Bitbucket::Credential` |
| D7 | Both integration modes (Forge app, token) are covered; the integration's own credential is never used for the person. | Task scope |
| D8 | The commit address is the primary confirmed email from `GET /user/emails`; none confirmed refuses. **For the reviewer to confirm**, because it exposes the address (R4). | Bitbucket has no noreply address |
| D9 | `write` or `admin` on the repository is the coverage threshold. | Bitbucket permission levels |
| D10 | Disconnect deletes the credential and consents and does not revoke, as no endpoint is documented. | §2.5 |
| D11 | Tool steps stay shared through `UserTokenContext`; GitHub and GitLab messages are unchanged. | `UserTokenContext` |
| D12 | Consent, issuance, masking and impersonation rules are GitHub's, except that `ActAsConsentsController` gets strict input: at least one recognized switch is required, unknown request-body keys are refused, and the switches stay exact JSON booleans. Today it selects recognized keys before validating, so `{}`, a misspelled key or an unknown extra key is accepted and can create a no-op row. Cases for `{}`, misspellings, unknown extras, strings, integers, null and mixed valid/invalid payloads are added for Bitbucket. | github-user-identity.md; implementation-patterns.md strict input |
| D13 | Calls with the person's token go through `Bitbucket::Api` (on our `Bitbucket::Client`), not a library, because none is in use and `Bitbucket::Api` is the one seam. | implementation-patterns.md "API clients"; testing.md |

## 9. Deferred questions

- **Raising the refresh floor** if S2 shows a refresh keeps the old access token valid.
- **Per-person request-quota accounting** or a cap on REST calls with the token (R3).
- **Revoking at Bitbucket** if Atlassian adds an endpoint; a per-person revoke link until then.
- **Narrowing, if Bitbucket adds repository-scoped user tokens:** the result shape already has `repositories`.
- **Routing the token through the git credential helper:** later opt-in, as for GitHub and GitLab.
- **Bitbucket Data Center** (D3).
- **Switching the board's workflows, `pull_request_*` and gates to act as the user:** out of scope (task).
- **Move the engine's token, refresh and revoke calls onto the `oauth2` gem** (2.0.25, already
  bundled), see D4.
- **Client rotation** (a current-client filter for display, vending and the sweep), for every
  provider at once: #275, after the rest of this work (R12).
- **Atomic connect:** verify the identity before the credential is stored or promoted, and keep
  the previous known-good credential when a reconnect fails. Today a failed `after_connect`
  keeps the credential, as GitHub and GitLab do; this design follows them. One engine change
  for every provider: #275.
- **Azure DevOps provider:** out of scope, as in the GitHub design.
