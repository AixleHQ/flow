# GitLab integration (architecture, no implementation)

## Why a separate document

In the product, GitHub follows the path "GitHub App → installation_id → list of repos → webhooks". GitLab has no full analog of GitHub Apps: typically you use an **OAuth application** (user) or a **Project/Group Access Token** / **Deploy Token** / **Service account** + **Project Hook** / **System Hook**. The goal is to preserve the **same UX**: first the "account/connection", then repository selection, then event delivery into Palad.

## Target UX (same as GitHub)

1. **Connection ("account")**  
   - The user goes through OAuth2 (or pastes a PAT with the required scope) → Palad stores encrypted credentials in an `Integration` entity with `provider: gitlab` (and if needed a `project_id` for project scope, see the company/project integration merge).  
   - Store metadata in `settings`: `base_url` (gitlab.com or self-managed), `user_id` / `username`, and for group access — `default_namespace_id`.

2. **Repository selection**  
   - API: list of available GitLab projects (`GET /projects` with pagination, filtered by membership).  
   - In Palad — the same `Repository` model (polymorphic scope Company/Project), the `full_name` field as `namespace/project` (slug path); do not store `clone_url` with the token in plaintext — only a reference to the integration.

3. **Webhooks**  
   - When a repository is linked to a Palad project, Palad registers a **Project Hook** on the target GitLab project: URL `https://<app>/api/v1/webhooks/gitlab`, secret in the integration `settings` or per-repo.  
   - Events: at minimum `push`, optionally `merge_request`, `pipeline` — depending on the workflow scenarios.  
   - For self-managed: explicitly specify `base_url` in the UI; the webhook uses the same host.

4. **No "app marketplace"**  
   - Instead of "Install app" — a "Connect GitLab" screen (OAuth) or "Paste group/project token" for a CI bot (enterprise scenario).  
   - Document the minimal OAuth scopes (`read_api`, `read_repository`, `write_repository` only if push from Palad is needed).

## Differences from GitHub to rely on in the code later

| Aspect | GitHub | GitLab |
|--------|--------|--------|
| Installation identifier | `installation_id` | None; there is an OAuth token / project id |
| Repo list | Installation repositories API | Projects API + membership |
| Webhooks | App or repo | Project Hook / Group Hook |
| Self-hosted | Less common | Common → mandatory `base_url` |

## Security

- Credentials encrypted only, as is currently done for integrations.  
- Webhook verification: `X-Gitlab-Token` or HMAC per the GitLab documentation for the chosen hook type.  
- Do not log tokens; per-repo secret rotation.

## Next implementation steps (when needed)

1. Extend `Integration.provider` with the value `gitlab`.  
2. A `Gitlab::TokenService` / `Gitlab::RepositoryService` service by analogy with Github.  
3. Webhook controller + idempotency + linking to `Repository` by GitLab `project_id`.  
4. UI: duplicate the MCP/repositories pattern — company integrations + project merge.
