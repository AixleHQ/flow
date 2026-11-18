# Aixle as the OAuth server of its personal MCP

Built 2026-11-18. Aixle's personal MCP server (`/mcp`, the user-level server that
`Tools::PersonalMCPRequestHandler` serves) accepted only a static `amcp_` bearer
token. Claude's connector stack — claude.ai, Claude Desktop, Cowork, mobile — signs
each person in with OAuth and has no per-user static-token option: its
"request headers" are an organization-wide credential, in beta, and would make
every member act as whoever's token was pasted. So a team could not add Aixle as
a connector for its members.

Aixle is now an OAuth 2.1 authorization server for that one resource. Both ways in
stay: the static token for CLIs, scripts and clients that cannot sign in; OAuth
for everything that can.

## The flow

1. A client sends an MCP request without a token. `MCPController` answers 401 with
   `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource/mcp", scope="mcp"`.
   An invalid `amcp_` or OAuth token gets the same header plus `error="invalid_token"`.
   An agent container's session key never does: nothing in a container can sign in,
   and a CLI that sees the challenge would wait on a browser nobody opens.
2. The client reads the protected resource metadata (RFC 9728) and then
   `/.well-known/oauth-authorization-server` (RFC 8414) at the issuer
   (`Settings.protocol://Settings.domain`).
3. The client identifies itself:
   - **CIMD** (a `client_id` that is an https URL, e.g. Claude Code's
     `https://claude.ai/oauth/claude-code-client-metadata`). Aixle fetches the
     document through `SafeHttp` (no redirects, 5 s, 16 KB, cached 10 min),
     requires its `client_id` to equal the URL, and takes its `redirect_uris`.
     Claude uses CIMD only when the metadata advertises
     `client_id_metadata_document_supported: true` **and** `"none"` in
     `token_endpoint_auth_methods_supported`; both are there.
   - **DCR** (`POST /mcp-oauth/register`, RFC 7591) for clients without a
     document. Every registration is a public client (`token_endpoint_auth_method:
     none`, whatever it asked for), throttled to 30 an hour per address.
4. `GET /mcp-oauth/authorize` (`Web::MCPAuthorizationsController`). An unknown
   client, or a `redirect_uri` the client did not register, is shown on Aixle's
   page and never redirected. Any other error (no S256 PKCE, a `resource` that is
   not ours) goes back to the client. A guest signs in first: the validated
   parameters ride across the sign-in like the other login continuations
   (`AuthConcern#take_pending_sign_in_path`).
5. The consent screen names the app (a CIMD client by the host its document is
   served from, since its `client_name` is self-asserted; a DCR client with an
   "unverified" warning), the account, the companies it will reach, and where
   the browser goes next. Allow creates an `MCPAuthGrant` and redirects with
   `code`, `state` and `iss` (RFC 9207). The decision is a top-level form POST
   (`postNavigate`), because an Inertia visit cannot follow a redirect to
   another host or a native app's scheme.
6. `POST /mcp-oauth/token` (`MCPAuth::TokenExchange`) exchanges the code (5 min,
   single use, PKCE S256) for an access token (1 hour) and a refresh token
   (30 days, sliding). Form-encoded and JSON bodies are both read.
7. MCP requests carry `Authorization: Bearer aoat_…`. `MCPController` routes the
   prefix to `MCPAuthToken.authenticate`, and the same
   `Tools::PersonalMCPRequestHandler` serves them, with the grant as the
   credential.

## What a grant reaches

The static token reaches the companies whose sign-in policy its issuing session's
proofs satisfy. A grant records the proofs of the browser session that gave the
consent, and reaches exactly the companies they satisfy — so connecting from an
SSO session reaches the SSO company even when the static token cannot.
`Tools::PersonalMCP::Credential` is that rule for both, and
`PersonalTools::Base#membership_company_ids` reads it. The consent screen lists
the companies reached and the ones left out; if none is reached, it does not
offer Allow.

Membership and policy are read on every call, so leaving a company or a policy
change takes effect at once. The tool selection on the MCP tab applies to the
token and to every app alike.

## Tokens

| | Prefix | Lifetime | Stored |
|---|---|---|---|
| Authorization code | `aoac_` | 5 minutes, single use | digest on the grant |
| Access token | `aoat_` | 1 hour | digest in `mcp_auth_tokens` |
| Refresh token | `aort_` | 30 days from its issue | digest in `mcp_auth_tokens` |
| DCR client id | `aocl_` | — | `mcp_auth_clients` |

Refresh tokens rotate. Presenting a rotated one again within 30 seconds is a
client retrying a refresh whose response it lost, and gets a fresh pair.
Presenting it later means a copy is in someone else's hands, and the whole grant
ends (OAuth 2.1 §4.3.1). A second use of a code ends its grant too.

## Ending access

- **Disconnect** on Profile → MCP → Connected apps revokes one grant.
- **Disable all MCP access** (`User#disable_mcp_token!`) revokes the static token
  and every grant.
- **Sign out other sessions**, a password change, suspension and an admin's
  revoke (`UserSession.revoke_all_for!`) end grants with the token.
- `POST /mcp-oauth/revoke` (RFC 7009) with either token ends its grant: a client
  that hands a token back is disconnecting.
- A suspended or deleted account's tokens stop working
  (`User.authenticatable`); deleting the user cascades to grants and tokens.

An operator impersonating someone can neither connect nor disconnect an app as
them, as with the static token.

## Endpoints

| Path | Controller |
|---|---|
| `GET /.well-known/oauth-protected-resource(/mcp, /action_mcp)` | `MCPAuth::MetadataController#protected_resource` |
| `GET /.well-known/oauth-authorization-server` | `MCPAuth::MetadataController#authorization_server` |
| `GET, POST /mcp-oauth/authorize` | `Web::MCPAuthorizationsController` |
| `POST /mcp-oauth/token` | `MCPAuth::TokensController` |
| `POST /mcp-oauth/register` | `MCPAuth::RegistrationsController` |
| `POST /mcp-oauth/revoke` | `MCPAuth::RevocationsController` |

Rack::Attack caps registration at 30 an hour, authorize at 60 a minute (a guest's
request makes Aixle fetch a metadata document) and token/revoke at 300 a minute
per address — Claude and ChatGPT reach the token endpoint from a few shared
egress addresses.

`/mcp-oauth/*` is a separate namespace because `/oauth/*` is Aixle's *client*
side (connecting to other MCP servers, `Web::OauthController`). The discovery
and token endpoints allow any CORS origin without credentials, for MCP clients
that run in a browser.

## Redirect URIs

`MCPAuth::RedirectUri`: https anywhere, http on loopback only (`localhost`,
`127.0.0.1`, `[::1]`), or a native app's private-use scheme (`cursor://…`,
RFC 8252 §7.1), never `javascript:`, `data:`, `file:` and the like, never with a
fragment or credentials. A loopback URI matches on any port (RFC 8252 §7.3;
Claude Code declares `http://localhost/callback` and signs in on an ephemeral
port); everything else matches exactly.

Hosted Claude (claude.ai, Desktop, Cowork, mobile) returns to
`https://claude.ai/api/mcp/auth_callback`; Claude Code to a loopback port.

## Deployment

Nothing to configure. The issuer is the app's own host, and discovery,
authorize and token are web routes on it. The resource is
`Tools::PersonalMCP.public_url`, so `MCP_PUBLIC_SERVER_URL` moves it, and that
host must route `/.well-known/oauth-protected-resource/*` to the app as well.
A self-hosted Aixle that Claude's servers cannot reach (Anthropic's egress is
`160.79.104.0/21`) works with Claude Code but not with claude.ai or Cowork.

## Not done

- Enterprise Managed Auth (Claude connecting an organization's members without a
  consent screen) needs token exchange against the company's IdP.
- Scopes: there is one, `mcp`, and the tool selection is per user, not per app.
- Pruning: expired tokens, revoked grants and unused DCR clients stay in their
  tables.
