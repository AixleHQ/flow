# Agents act as the user on GitLab

**Task:** #238 · **Status:** built · **Date:** 2026-11-13

Builds on [github-user-identity.md](./github-user-identity.md) (#214, built). Read its
§2.1–§2.3, §3 and §4.3 first: this document says only what GitLab changes. Anything not
mentioned here is the same as for GitHub.

A user connects their own GitLab account. An agent can then ask for a token that acts as
that user, push commits authored by them and open the merge request in their name. The
platform provides the mechanism; a workflow's instructions decide when to use it.

## 1. Overview

Today GitLab connects only at the integration level (`Gitlab::TokenService`, one token
per integration, a PAT or a service account). Every push, merge request and comment from
an agent is the integration account's.

This design adds, for GitLab:

1. **A GitLab connection per user** on the unified OAuth engine (`provider: "gitlab"`,
   owner `User`), made with the deployment's existing GitLab OAuth app.
2. **Consent:** `act_as_consents.provider` gains `gitlab`; same two switches per project.
3. **Two tools,** `gitlab_user_token` and `gitlab_user_token_for(user_id)`, with the same
   checks, messages, masking and issuance records as the GitHub pair.
4. **Docs:** this document, the GitLab user guide, the tool tables.

Nothing changes for a deployment or a user that does not use it. The GitLab integration
connection, the service-account flow and `GitCredentials::Vendor` are not touched.

## 2. Approach

### 2.1 The one real difference: the token cannot be narrowed to repositories

GitHub mints a token limited to chosen repositories and permissions
(`POST /applications/{client_id}/token/scoped`). **GitLab has no equivalent.** An OAuth
access token is limited by its **scopes** only, and the scope that opens merge requests
and comments, `api`, covers everything the user can reach on the instance. I checked the
options GitLab offers for a token that acts as a person:

| Option | Acts as the person? | Limited to the session's repositories? | Verdict |
|---|---|---|---|
| The user's OAuth access token, scope `api` | Yes | **No**: all the user can reach | **Chosen** |
| Narrower OAuth scopes (`write_repository`, `read_api`) | Yes | No, and merge requests and comments need `api` | Rejected: no gain for what agents do |
| Project access token | No: a bot user of the project | Yes | Rejected: it is not the person. Commits, merge requests and comments would be the bot's. Needs Maintainer to create |
| Impersonation token | Yes | No | Rejected: administrators only |
| Personal access token created for the user | Yes | No | Rejected: the API creates one only for an administrator, or the person pastes it (task: excluded) |
| Deploy token / job token | No | Yes / per job | Rejected: not a person, no merge requests |

So the answer to the task's first question is: **the token is not limited to the
session's repositories, and the design says so rather than pretend.** What bounds it
instead:

- **The person's own access.** It acts as them and can do nothing they cannot.
- **Consent per project** (two switches, as for GitHub): nobody's token is issued
  without their yes for this project.
- **Lifetime.** A GitLab OAuth access token lives two hours (§2.3).
- **A coverage check.** The tool verifies, with the person's token, that they can push
  to each of the session's GitLab repositories (§4.2). A repository they cannot reach is
  listed in `skipped`, so the agent learns it at once. This informs the agent; it does
  not restrict the token.
- **Masking and audit.** Every issued token is recorded and masked as a session secret.
- **Docs say it plainly:** the GitHub guide's "limited to the session's repositories"
  has no counterpart here, and a person allowing it is allowing their GitLab account in
  that project's sessions.

This is the main decision for the reviewer (D1).

### 2.2 Connection: the unified OAuth engine, one more registry entry

`Oauth::Providers::REGISTRY` gets a `gitlab` entry. The connect flow is the existing
`Web::OauthController#authorize` / `#callback` with `owner_type: "User"`, as for GitHub.
The deployment's existing GitLab OAuth app is reused (`Gitlab::AppConfig.oauth_client_id`
and `_secret`, scope `api`, the same app as "Sign in with GitLab"): the operator adds
**one redirect URI** to it, `<PROTOCOL>://<DOMAIN>/oauth/callback`, next to
`/integrations/gitlab/oauth/callback`. The scope is the same, so no existing consent
changes. A deployment without the OAuth app (token-only GitLab) cannot offer the feature:
the tools are unavailable and the page says so.

What the registry cannot do today, and the change:

| Today | For GitLab | Change |
|---|---|---|
| Endpoints and issuer are constants | They derive from `GITLAB_ENDPOINT` (`Gitlab::Host.web_base`) | An entry may name a resolver: `endpoints: "Gitlab::UserConnection"`, whose `.endpoints` returns `{ issuer:, authorization_endpoint:, token_endpoint: }`. `Providers.config` merges it, as `after_connect` is looked up today |
| Client id and secret read as `Settings.<key>.client_id` / `.client_secret` | `Settings.gitlab.oauth_client_id` / `oauth_client_secret` | Optional `client_id_key` and `client_secret_key` on the entry; default to the current names |
| `Oauth::Providers.client_for` finds or creates the `OauthClient` by `(issuer, client_id)` | Same | No change. The issuer is `Host.web_base`, so a different `GITLAB_ENDPOINT` yields a different client (see below) |
| The token endpoint must clear the SSRF guard (`UrlSafetyValidator`, `SafeHttp`), refusing private hosts | A self-managed GitLab is often on a private network (`Gitlab::AppConfig` already says so) | The two engine call sites (`Web::OauthController#exchange_code!`, `Oauth::TokenService.perform_refresh!`) pass the registry's operator host as trusted: `trusted_hosts_override:` / `trusted_hosts:`. The host is the operator's own `GITLAB_ENDPOINT`, as trusted as `Gitlab::Rest` already treats it. A literal private IP address stays refused by `SafeHttp`: the instance needs a host name |
| `refuse_github_connect?` refuses connecting while impersonating | Same rule | Generalised to every provider in `UserConnections::PROVIDERS` |

`after_connect: "Gitlab::UserConnection"` calls `record_identity!` (`GET /user` with the
new token) and stores `metadata["gitlab_user"] = { id, username, name, avatar_url,
commit_email, fetched_at }`. As for GitHub, a failed lookup raises
`Oauth::TokenExchangeError` ("Failed to complete connection") and the stored identity is
cleared, not the credential.

RFC 9207: GitLab sends no `iss` in the authorization response; `issuer_matches?` already
accepts that unless the server advertises support.

**A different `GITLAB_ENDPOINT`.** The issuer changes, `client_for` makes another
`OauthClient`, and a user's credentials on the old client belong to the old instance.
`OauthCredential.live_gitlab_connection_of(user)` and `latest_gitlab_connection_of`
therefore only consider rows whose `oauth_client.issuer` equals the current
`Gitlab::Host.web_base`. An old-host row is invisible and lapses; Disconnect removes all
of the user's `gitlab` rows. The limit is the existing one: one instance per deployment.

**Alternatives considered**

- *A second GitLab OAuth app just for users.* More for the operator to create, and two
  secrets. Rejected: one app, one added redirect URI.
- *Reuse `/integrations/gitlab/oauth/callback`.* That callback creates a service account
  for a Project owner and has no `User` path. Rejected: it would grow a second purpose.
- *A dedicated table.* Same rejection as in the GitHub design (§2.1).

### 2.3 Token lifetime and refresh

GitLab OAuth access tokens expire after two hours, and the refresh token rotates on use.
That is the same shape as GitHub's expiring user tokens, so the engine already handles
it: `RefreshLease`, the five-minute sweep (`Oauth::RefreshExpiringTokensActivity`),
`mark_refresh_error!` and the reconnect email for User owners. `expires_in` arrives in
the token response and `apply_token_response!` stores `expires_at`.

**What the tool hands out.** The stored token itself, since GitLab cannot mint a narrower
one (GitHub mints a new one per call). Steps:

1. `Oauth::TokenService.fresh(credential, skew: MIN_LIFETIME)` with
   `MIN_LIFETIME = 30.minutes`, so the agent never gets a token about to lapse. The
   sweep and `fresh` refresh at 10 minutes left (`REFRESH_SKEW`), so a token is handed
   out with at least 20 minutes of use before the platform replaces it.
2. The result's `expires_at` is the stored `expires_at` minus `REFRESH_SKEW`: the moment
   to ask again, not GitLab's expiry. A refresh issues a new access token. Whether
   GitLab's Doorkeeper revokes the previous access token at that moment is unverified
   (R2), so the earlier time is the safe one to report.
3. Two sessions of one user receive the same token value until the next refresh. Each
   gets its own issuance row.

The 30-minute floor, not `PRE_START_SKEW` (one hour), keeps refreshes to about one per
credential per two hours however many calls agents make.

**Alternative:** refresh on every call for a full two hours each time. It multiplies
rotations, and if refreshing revokes the previous access token it would cut off other
sessions of the same user. Rejected.

### 2.4 Masking and audit: unchanged

`user_token_issuances` already holds any provider's token and feeds `SecretRegistry` and
`SecretRedactor`; nothing there changes. For GitLab, the row stores the same value the
credential holds. `target_login` (not null) stores the GitLab host name, since there is
no per-owner grouping. `provider` is `gitlab`; `repository_full_names` lists the
covered repositories.

## 3. Data model changes

- **No migration.** `act_as_consents.provider` and `user_token_issuances.provider` are
  plain strings (`db/schema.rb`, no check constraint). `ActAsConsent`'s
  `enumerize :provider, in: %w[github]` becomes `in: %w[github gitlab]`.
- `OauthCredential`: `GITLAB_PROVIDER = "gitlab"` and the scopes `gitlab_connections_of`,
  `latest_gitlab_connection_of`, `live_gitlab_connection_of` (issuer-filtered, §2.2).
  The identity lives in `metadata["gitlab_user"]`, outside `SAFE_METADATA_KEYS`, as
  `github_user` does (written by `record_identity!`, not from the token response).
- Disconnect, as for GitHub: revoke the grant, destroy the rows, delete the
  `act_as_consents` rows for the provider. Issuance rows stay.

## 4. API / interface changes

### 4.1 `Gitlab::UserConnection` and `Gitlab::UserTokenService` (new)

`Gitlab::UserConnection` mirrors `Github::UserConnection`: `PROVIDER`, `configured?`
(`Gitlab::AppConfig.oauth_enabled?`), `endpoints`, `record_identity!`, `identity_for`
(refetch when older than 24 hours), `disconnect!(user)`.

`Gitlab::UserTokenService` (`app/services/gitlab/user_token_service.rb`) is the adapter
for calls made with a user's token, using `Gitlab::Rest` against `Host.api_endpoint`
(the endpoint is the deployment's, never a request's):

- `user(token)`: `GET /user`, returns `{ id:, username:, name:, avatar_url:,
  commit_email: }`. `commit_email` is the address GitLab itself uses for web commits (a
  private `<id>-<username>@users.noreply.<host>` unless the person chose another), so a
  self-managed instance gets its own domain without guessing it.
- `project_access(token, full_path)`: `GET /projects/:id` with the project path encoded;
  returns the effective `access_level` (the larger of `project_access` and
  `group_access`) or `nil` for 404.
- `revoke(token)`: `POST /oauth/revoke` with the app's client id and secret; best effort,
  as for GitHub.

Errors map to `InvalidToken` (401), `Forbidden` (403), `Unavailable` (5xx, network).
`Gitlab::Rest` raises `Trackers::Error` with a code; the adapter translates, as
`Github::UserTokenService` does for Octokit. A canonical fake,
`FakeGitlab::UserTokenService`, goes in `test/support/fakes/` next to the GitHub one.

`Gitlab::TokenService` reads the endpoint itself rather than through `Gitlab::Host`;
that is #218's, and this design uses only `Gitlab::Host`.

### 4.2 Tools

`InternalTools::GitlabUserToken` and `GitlabUserTokenFor`, built like the GitHub pair:

```ruby
tags :gitlab_identity            # new TagCatalog entry, label "GitLab as a user", ui_visible: true
requires_integration :gitlab
availability ->(_ctx) { Gitlab::UserConnection.configured? }
unavailable_message "Connecting GitLab accounts is not configured on this installation."
```

`user_attachable`, no auto-injection, same consent rule (`gitlab_user_token`: in my
tasks; `_for`: in my tasks when the named user is `session_user`, otherwise in tasks that
aren't mine; same resolution of `user_id` among the company's members).

**Shared code.** `GithubUserTokenContext` holds the nine steps (§4.3 of the GitHub
design) with GitHub's calls inline. Copying it would leave two sets of messages to keep
equal, so the steps move to `InternalTools::Concerns::UserTokenContext`, which calls a
small per-provider part: `provider_label`, `connection_for`, `collect_repositories`,
`fresh_user_token!`, `mint_tokens!` and `result`. `GithubUserTokenContext` and the new
`GitlabUserTokenContext` supply them. With the label `GitHub`, every message stays
byte-identical, so the GitHub tests do not change (a rename of constants only).

GitLab's provider part:

- **Repositories:** `session.repositories` whose integration is GitLab and active.
  Both auth modes (PAT, service account) qualify; the integration's own token is not
  used. None: "This session has no GitLab repositories on an active GitLab connection."
- **Coverage check:** `project_access` per repository with the user's token. Access
  level 30 (Developer) or more covers the repository. Less, or nil, puts it in `skipped`
  with the reason "<name> cannot push to it". If nothing is covered, the tool refuses
  naming the repositories. A 401 marks the credential `error` (`mark_refresh_error!`,
  which sends the existing email) and answers with the reconnect message.
- **Token:** §2.3. One entry, not one per owner.
- **Issuance:** one `UserTokenIssuance` row, then `SecretRegistry.publish!`; refuse if it
  fails, as for GitHub.

Result:

```json
{
  "user": { "id": 82, "name": "Artem" },
  "identity": { "login": "artem", "gitlab_id": 123, "name": "Artem",
                "email": "123-artem@users.noreply.gitlab.com" },
  "tokens": [
    { "token": "…", "host": "https://gitlab.example.com", "scopes": ["api"],
      "git_username": "oauth2", "api_url": "https://gitlab.example.com/api/v4",
      "repositories": ["group/sub/project"], "expires_at": "2026-11-13T17:00:00Z" }
  ],
  "skipped": [],
  "note": "…"
}
```

`tokens` stays a list so instructions written for the GitHub tool read the same.
`git_username` is `oauth2`, what `GitCredentials::Vendor` already uses for GitLab. The
note adds that the token is not limited to these repositories, so it must not be used
elsewhere. Error messages never carry a token or a GitLab response body.

### 4.3 Profile page and `UserConnections`

`UserConnections::PROVIDERS` becomes a map from provider to its connection module
(`Github::UserConnection`, `Gitlab::UserConnection`), and `available?`, `connection`,
`disconnect!` dispatch on it. `Web::Profile::ConnectionsController` stops using a single
`PROVIDER` constant; the disconnect notice names the provider. The routes already carry
`:provider`.

Page props change shape, so the page, its test and the generated types change together:

- `available`: `{ github: bool, gitlab: bool }`;
- `connections`: `{ github: UserConnection | null, gitlab: UserConnection | null }`
  (`UserConnectionResource` gains `provider` and reads `gitlab_user` for GitLab);
- `consents`: `{ github: ActAsConsent[], gitlab: ActAsConsent[] }`
  (`ActAsConsentResource` gains `provider`).

`Connections.tsx`: `GithubCard` becomes `ProviderCard` taking the provider's name and
icon (`IconBrandGitlab`); the projects table renders once per connected provider.

## 5. Implementation steps

1. **Engine changes** (backend; GitHub behaviour unchanged).
   - `Oauth::Providers`: the `gitlab` entry, `endpoints:` resolver, `client_id_key` /
     `client_secret_key`, and a trusted-host helper.
   - Pass the trusted host in `Web::OauthController#exchange_code!` and
     `Oauth::TokenService.perform_refresh!`; generalise `refuse_github_connect?`.
2. **Connection.** `Gitlab::UserConnection`, `Gitlab::UserTokenService` and its fake,
   the `OauthCredential` scopes, `ActAsConsent` provider list.
3. **Tools.** Extract `UserTokenContext`; add `GitlabUserTokenContext`, the two tools and
   the `:gitlab_identity` tag in `Tools::TagCatalog`.
4. **Profile.** `UserConnections`, the controller, resources (`rails
   typelizer:generate`), `Connections.tsx` and its test.
5. **Docs.**
   - `docs/user-guide/gitlab.md` and its mirror
     `app/frontend/pages/Docs/data/pages/gitlab.md`: a section "Acting as yourself"
     (connecting, the two switches, the tools, the errors, the example below, and the
     plain statement that the token is not limited to the session's repositories); under
     "Self-managed GitLab" the extra redirect URI; in the tool tables the two new rows.
   - `docs/user-guide/github.md` "Acting as yourself" and its mirror: one line pointing
     to GitLab for the same.
   - `CHANGELOG.md`: an entry under `### Added`, area **Integrations**
     (`docs/product/changelog-product-areas.md`).
   - `docs/index.md`: the design entry (this change); update `github-user-identity.md`'s
     deferred bullet in the implementation pull request.
6. **Staging check** (§6).

Steps 1–2 can merge alone, since nothing calls them. Step 3 needs 1–2, step 4 needs 2.

The docs example of instructions that push and open a merge request as the user:

```bash
# token, email, name come from gitlab_user_token
export GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" \
       GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL"
git commit -s -m "feat: ..."
git -c credential.helper= \
    -c credential.helper='!f() { echo username=oauth2; echo "password=$TOKEN"; }; f' \
    push origin HEAD:feature/x
curl -sS -H "Authorization: Bearer $TOKEN" -X POST "$API_URL/projects/$ID/merge_requests" \
     -d source_branch=feature/x -d target_branch=main -d title="..."
```

## 6. Testing approach

Following `docs/testing.md` (real database, app-owned seams, WebMock only in adapter
contract tests).

- **Adapter:** `test/services/gitlab/user_token_service_test.rb`, WebMock contract tests
  for `GET /user` (with and without `commit_email`), `GET /projects/:id` (project and
  group access, 404), `POST /oauth/revoke`, and the error mappings. The payloads pin the
  fake.
- **Engine:** `test/services/oauth/providers_test.rb` for the resolver and the key
  names; the callback request test for a `User` owner connecting GitLab, storing
  `metadata["gitlab_user"]`, and leaving the credential when the identity fetch fails; a
  token exchange and a refresh against a private-resolving operator host succeed while
  the same host under another provider stays refused.
- **Models:** `ActAsConsent` accepts `gitlab`; issuer-filtered `live_gitlab_connection_of`
  (a row on another host is ignored).
- **Tools:** `gitlab_user_token_test.rb`, `gitlab_user_token_for_test.rb` in the shape
  of the GitHub ones: every error, the consent matrix, a user without Developer access in
  `skipped`, nothing covered refuses, a 401 marks the credential, the token floor
  (a credential with under 30 minutes is refreshed first), issuance row, masking, no
  token in any error.
- **Refactor guard:** the existing GitHub tool tests pass unchanged after the extraction.
- **Requests / frontend:** `profile_connections_test.rb` for the new prop shape, a
  GitLab consent update and disconnect; `Connections.test.tsx` for both cards.
- **Manual, on staging against a real GitLab (acceptance):**
  - connect; use the token: the push and merge request are the user's; a user with
    only Reporter on a repository gets it in `skipped`;
  - a token returned twice within a refresh window is the same value; after the sweep
    refreshes, ask again works;
  - spike R2 (does a refresh revoke the previous access token?);
  - the same on a self-managed instance served over HTTPS on a private host.

## 7. Edge cases & risks

- **R1. The token reaches every project the user can.** §2.1. The main residual risk, and
  accepted only with the reviewer's agreement (D1). A token in a model's context is
  already accepted for GitHub (its R6); here the blast radius is wider.
- **R2. Does refreshing revoke the previous access token?** Unverified. If it does, a
  token handed out stops working when the sweep refreshes. The reported `expires_at`
  already allows for it (§2.3); the spike on staging decides whether the docs say more.
- **R3. Commit email.** If the person's profile hides the email, `commit_email` still
  returns the noreply address. If GitLab returns none, the tool falls back to
  `<id>-<username>@users.noreply.<host>` built from the connection's host.
- **R4. Instance settings.** The OAuth app must be confidential with scope `api`. An
  instance that sets a short or unlimited token lifetime changes `expires_in`, which the
  engine reads from the response, so nothing is assumed.
- **R5. Changing `GITLAB_ENDPOINT`.** Existing user connections stop applying (§2.2) and
  consents stay, harmlessly, until reconnect.
- **R6. Self-managed hosts.** HTTPS only (the credential helper's existing limit); a host
  name, not a literal IP, for the trusted-host rule; a private CA is #218's, and applies
  here to the token endpoint call too (`Oauth::TokenService` uses `Net::HTTP` through
  `SafeHttp`, so it follows whatever #218 decides for server-side trust).
- **R7. Gate and tracker ownership.** Nothing here changes who a pipeline gate or the
  tracker acts as; they stay on the integration.
- **R8. Revocation at GitLab** has no webhook. A revoked grant shows as a 401 on the next
  use and is escalated by the existing path.
- **R9. Same GitLab account for two Flow users** is allowed, as for GitHub.
- **R10. Frontend contract change.** The profile page's props change shape (§4.3); the
  page, test and generated types move in one change.

## 8. Decisions & assumptions

| # | Decision | Source |
|---|---|---|
| D1 | The token is the user's OAuth token with scope `api`, not narrowed to repositories, because GitLab offers no way to narrow it; the limits are consent, the user's own access, lifetime, the coverage check and masking. **For the reviewer to confirm.** | Task: "must answer how the token is limited"; GitLab OAuth scopes (§2.1) |
| D2 | One shared GitLab OAuth app, with one added redirect URI. | Task: "through the unified OAuth engine"; `Gitlab::AppConfig`, `docs/user-guide/gitlab.md` |
| D3 | Feature requires the OAuth app; absent, the tools are unavailable. | `Gitlab::AppConfig.oauth_enabled?` |
| D4 | The stored access token is returned, refreshed when under 30 minutes remain; `expires_at` reported minus the 10-minute refresh skew. | §2.3 |
| D5 | The engine treats the operator's GitLab host as trusted for the token endpoint; a literal IP stays refused. | `Gitlab::Rest` trusts `GITLAB_ENDPOINT`; `SafeHttp` `trusted_hosts` |
| D6 | Issuer is the GitLab web base, so connections belong to one instance; other-instance rows are ignored. | `Gitlab::Host`, one instance per deployment |
| D7 | Both integration auth modes (PAT, service account) are covered; the integration's token is never used for the person's. | Task scope |
| D8 | Tool steps are shared with GitHub through one concern; GitHub messages unchanged. | `GithubUserTokenContext` |
| D9 | Commit identity comes from GitLab's `commit_email`. | Self-managed domains differ |
| D10 | Developer (30) is the coverage threshold. | GitLab roles: push to unprotected branches |
| D11 | Consent, issuance, masking, disconnect and impersonation rules are GitHub's, unchanged. | `github-user-identity.md` |
| D12 | The task points to #218 for self-managed; its assessment was not available in the repository, so this design takes only what the code and user guide show (`Gitlab::Host`, `Gitlab::AppConfig`, `SafeHttp`) and defers private-CA trust to it. | Task #238; task #218 (in progress) |

## 9. Deferred questions

- **Revoking issued tokens at session end.** Revoking the shared stored token would end
  the user's other sessions; a distinct token per issuance is impossible here. Waits on R2.
- **Narrowing, if GitLab adds it.** A repository-scoped user token would replace §2.1's
  mitigations; the tool's result shape already has `repositories`.
- **Private-CA trust for the token endpoint** and any other self-managed gap: #218.
- **Routing the token through the git credential helper** (as for GitHub): later opt-in.
- **Bitbucket and Azure DevOps providers:** out of scope, as in the GitHub design.
- **Switching the board's workflows to the new tools:** out of scope (task).
