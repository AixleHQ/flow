# Self-managed GitLab on a self-hosted Aixle

Status: **Proposed (task #218), 2026-11-10.** Assessment from the code on `develop` at `e2e66134`,
not yet checked against a live self-managed instance. §6 lists the cases for that check.
Related: [`gitlab-tracker.md`](./gitlab-tracker.md) (the tracker and the service account),
`docs/user-guide/gitlab.md` (the user guide), `docs/reference/configuration.md` (the variables).

## 1. Overview

A prospective customer runs a self-managed GitLab and wants to run Aixle self-hosted next to it. The user
guide already says self-managed GitLab is supported ("Self-managed GitLab" in `docs/user-guide/gitlab.md`
and its portal copy `app/frontend/pages/Docs/data/pages/gitlab.md`). This document checks that claim area
by area (§2), then designs what is missing (§3–§5).

The customer's setup is assumed, until we know more, to be:

- **A1.** A recent GitLab, CE or EE.
- **A2.** HTTPS, possibly with a certificate from a private CA.
- **A3.** Aixle and GitLab on the same private network.
- **A4.** No access to gitlab.com from that deployment.

Each finding below names the assumption it depends on.

**Verdict:** several things are missing, and two of them block a typical private-network installation
completely:

- On Kubernetes, session pods cannot reach a GitLab on a private address.
- A certificate from a private CA is trusted neither by session containers nor by their proxy.

The other gaps are smaller: a relative URL root breaks two flows, the service-account sign-in fails with
a gitlab.com-only explanation, the hook heuristic can refuse a reachable address, and the docs are out
of date.

## 2. Assessment

`Gitlab::Host` (`app/services/gitlab/host.rb`) is the single source of the instance:

- `api_endpoint` is `GITLAB_ENDPOINT`, defaulting to `https://gitlab.com/api/v4`.
- `web_base` is that endpoint without `/api/vN`. A port and a relative URL root
  (`https://corp.example:8443/gitlab/api/v4`) both survive it.

Legend: ✅ works, ⚠️ works with a caveat or operator setup, ❌ broken or missing.

### 2.1 Connecting GitLab

| Feature | State | Evidence | Depends on |
|---|---|---|---|
| Personal, group or project access token | ✅ | `Gitlab::IntegrationService#create` → `Gitlab::TokenService#verify_token` (`GET /user` through the gitlab gem, configured endpoint). `NETWORK_ERRORS` includes `OpenSSL::SSL::SSLError`, so a bad certificate reads "Could not reach GitLab at … (SSLError)" | A2 (§2.6) |
| `TokenService` reads the endpoint itself | ⚠️ | `token_service.rb:47` repeats `Settings.gitlab.endpoint.presence \|\| "https://gitlab.com/api/v4"` instead of calling `Gitlab::Host.api_endpoint`. The value is the same today, but there are two copies | — |
| Sign in with GitLab: authorize | ✅ | `Gitlab::Oauth.authorize_url` builds `"#{Host.web_base}/oauth/authorize"`. The button is gated on `Gitlab::AppConfig.oauth_enabled?` (`integrations_controller.rb:21`) | OAuth app on the instance (Admin → Applications, trusted) |
| Sign in with GitLab: code exchange | ❌ under a relative URL root | `oauth.rb:31` calls `Faraday.new(url: Host.web_base).post("/oauth/token", …)`. Faraday treats a leading `/` as an absolute path and drops the base path, so under `https://corp.example/gitlab` the POST goes to `https://corp.example/oauth/token` | GitLab served under a path |
| Service account creation | ⚠️ | `Gitlab::ServiceAccountSetup#create!` calls `POST /groups/:id/service_accounts`. On self-managed GitLab, by default only an administrator may create one. A group Owner can create one only after an administrator turns on *Allow top-level group owners to create service accounts* (GitLab 17.6+). On Free and unlicensed EE the API exists only from 18.11, and the instance allows 100 accounts in total. Whether the CE build ships it is unverified (§6). A refusal is explained only in gitlab.com terms (`integration_service.rb:212`), and a 404 gets the generic "GitLab has no such resource" | A1, GitLab admin setting |
| Token rotation and revocation | ✅ on 16.10+ | `Gitlab::ServiceAccountToken` (`POST /personal_access_tokens/self/rotate`, `DELETE /personal_access_tokens/self`) | A1 |

### 2.2 Repositories and session git

| Feature | State | Evidence | Depends on |
|---|---|---|---|
| Listing and attaching | ✅ | `Gitlab::RepositoryService#list_available` / `#find_repo` (gem, configured endpoint). `Repository#set_clone_url` builds `"#{Gitlab::Host.web_base}/#{full_name}.git"` | — |
| Clone (session start) | ⚠️ / ❌ | `GitCredentials::SessionGitSetup#clone` runs `git clone` through `runtime.exec`, so without the proxy, and verifies TLS against the image's system bundle. On **Kubernetes** the pod's egress policy `runtime-allow-public-internet-egress` excludes `K8S_RUNTIME_BLOCKED_IPV4_CIDRS`, which defaults to RFC 1918 + CGNAT + link-local (`settings.yml:600`). A GitLab on `10.x` is therefore unreachable, and the clone fails. There is no allowlist | A3, A2 |
| Fetch and push (agent) | ⚠️ / ❌ | The credential helper (`docker/base/git/git-credential-aixle`) asks `GitCredentialsController`, and `GitCredentials::Vendor#same_repository?` compares host and path, so a port and a relative root work. Git in the agent's tmux runs behind `mitmdump` (`HTTPS_PROXY`, `start-mitm.sh`). `mitmdump` is started with no `ssl_verify_upstream_trusted_ca`, so it verifies upstream TLS against **certifi**, not the system store. A private-CA GitLab fails even if the CA were in `/etc/ssl/certs`. The same egress policy applies | A2, A3 |
| HTTPS only | ✅ (documented) | The helper answers only for `protocol=https` | A2 |
| Public repositories | ⚠️ (by design) | `Repository::PUBLIC_HOSTS` and `PublicRepositoryService::GITLAB_API` are gitlab.com only. This is an SSRF boundary (`repository.rb:5-8`). Without gitlab.com egress (A4), the option fails at verification. A public project on the self-managed instance is attached through the connection instead | A4 |
| Coder workspaces | ❌ (not self-managed specific) | `Coder::RepoBootstrap#token_for` supports GitHub and public clones only | — |

### 2.3 Merge requests and the agent's GitLab tools

| Feature | State | Evidence |
|---|---|---|
| `pull_request_*` calls | ✅ on 15.7+ | `PullRequests::Gitlab::Provider` uses the gem client on the configured endpoint. The newest endpoint it calls is `GET /projects/:id/merge_requests/:iid/diffs` (15.7). `detailed_merge_status` (15.6) falls back to `merge_status` |
| Merge-request URLs | ⚠️ | `owns_reference?` (`provider.rb:136`) is an exact, case-insensitive string-prefix match on `"#{web_base}/#{full_name}/-/merge_requests/"`. When `GITLAB_ENDPOINT` names a different hostname than GitLab's `external_url` (an internal alias, an IP, an explicit `:443`), the URL an agent copies from GitLab is refused, and the `url` Flow returns differs from GitLab's own |

### 2.4 Pipeline gates and the pipeline webhook

| Feature | State | Evidence | Depends on |
|---|---|---|---|
| Gate creation, the reconciliation sweep | ✅ | `board_create_gate`, `Ci::GateProbe` → `Gitlab::PipelineStatusService` (`GET /projects/:id/pipelines/:id`), any version | — |
| Webhook ingress | ✅ | `Webhooks::GitlabController` matches `project.path_with_namespace` and the per-repository `X-Gitlab-Token`. It never reads a host | — |
| Hook registration | ⚠️ | `Repositories::CiWebhook.register` registers only if `Gitlab::AppConfig.webhooks_enabled?`. That check classifies hosts **by their spelling**: no dot, `.local`, `.internal`, `.localdomain` or a private-IPv4 literal means private. It never looks a name up. Take a GitLab at `gitlab.corp.example.com` that resolves to `10.x`, with Flow at `aixle.internal`: GitLab counts as public and Flow as private, so no hook is registered, even when the operator sets `GITLAB_WEBHOOK_BASE_URL` on purpose. Gates then resolve only through the sweep (10+ min) | A3 |
| GitLab → Flow delivery | ⚠️ (operator, GitLab side) | GitLab refuses hooks to private addresses unless an administrator allows *requests to the local network from webhooks and integrations*. Hooks verify TLS (`enable_ssl_verification: true` in `tracker_api.rb:90`, and GitLab's default for the pipeline hook), so GitLab must trust Flow's certificate | A2, A3 |

### 2.5 The GitLab tracker (`docs/design/gitlab-tracker.md`)

| Feature | State | Evidence | Depends on |
|---|---|---|---|
| Issues, boards, notes, members, moves | ✅ | `Gitlab::TrackerApi` over `Gitlab::Rest` (Faraday on `Host.api_endpoint`, port and root kept, no SSRF filter) | — |
| Files | ✅ on 17.4+ | Download is `GET /projects/:id/uploads/:secret/:filename` (17.4). `Rest#files` goes through `SafeHttp` with the GitLab host in `trusted_hosts`, so a hostname that resolves privately is allowed. An IP-literal `GITLAB_ENDPOINT` is refused for files only | A1 |
| Issue URLs as references | ❌ under a relative URL root | `ISSUE_URL` (`trackers/gitlab/provider.rb:25`) captures everything after the host as the project path, so `/gitlab/grp/proj/-/issues/5` yields `gitlab/grp/proj`, which never equals the tracked path `grp/proj` | GitLab served under a path |
| Events | ⚠️ | Same hook heuristic as §2.4. Unlike gates, the tracker has **no polling fallback**: without the hook, issues start no workflow | A3 |

### 2.6 A certificate from a private CA (A2)

| Side | State | Evidence |
|---|---|---|
| Flow server → GitLab API | ⚠️ undocumented | Every client (gitlab gem / HTTParty, Faraday, `SafeHttp` Net::HTTP) uses OpenSSL's default store, which honours `SSL_CERT_FILE`. Nothing sets a CA. The app image (`ruby:…-alpine`, runs as `app`) has no hook to add one. An operator can work around it by building a full bundle and setting `SSL_CERT_FILE`, but nothing documents this |
| Session container → GitLab | ❌ | The clone uses the image's system bundle, and the agent's git goes through `mitmdump`, which uses certifi (§2.2). No operator setting adds an environment variable, a file or a volume to session pods (`KubernetesRuntime#build_pod`) |
| GitLab → Flow (hooks) | ⚠️ operator | GitLab's own trust store must hold the CA behind Flow's certificate |

### 2.7 The lowest GitLab version

| Feature | Lowest version |
|---|---|
| Token connection, repositories, clones, pipeline gates | Any supported version |
| Merge-request tools | 15.7 (`/diffs`) |
| Tracker | 17.4 (file download). The rest needs ~15.x |
| Sign in with GitLab (service account) | Premium/Ultimate: 17.6+ with the admin setting for a group Owner, or any version with service accounts when an administrator signs in. Free / unlicensed EE: 18.11+ |
| Token rotation | 16.10 |

The recommended floor for the customer is **18.11**, the version at which every feature works on every
tier. Versions come from GitLab's documentation
([service accounts](https://docs.gitlab.com/user/profile/service_accounts/),
[uploads](https://docs.gitlab.com/api/project_markdown_uploads/)) and are re-checked in §6.

### 2.8 How Aixle is deployed self-hosted, and what the operator sets

- `DEPLOYMENT_MODE=self_hosted` (`app/services/deployment.rb`) changes billing and capacity only, not
  networking or integrations.
- Production runs on Kubernetes. The manifests live in the separate deployment repository. In this
  repository, Compose (`docker-compose.yml`) is for local development.
- GitLab today needs:
  - `GITLAB_ENDPOINT` (external URL + `/api/v4`);
  - `GITLAB_WEBHOOK_BASE_URL` when `DOMAIN` is not what GitLab reaches;
  - `GITLAB_OAUTH_CLIENT_ID` / `GITLAB_OAUTH_CLIENT_SECRET` for the sign-in;
  - `GIT_CREDENTIALS_URL` (default internal).

  None of these is in `.env.example`, which the configuration rule requires (context.md, "Config").
- The frontend makes no gitlab.com assumption. It never learns the host. The only literal is the
  public-repository help text in `AddRepositoryModal.tsx:272`, which is true by design.
- The user guide's **Limits** section is stale. It still says there is no OAuth app and that GitLab
  issues cannot be a tracker.

## 3. Approach

Each gap is fixed in the place that owns it today. Nothing new is added where the existing seam suffices.

| Gap | Fix | Alternatives rejected |
|---|---|---|
| Session pods cannot reach a private GitLab | An operator-set **allowlist** of private CIDRs and ports, added as one more `NetworkPolicy` next to the existing ones in `KubernetesRuntime#runtime_network_policies`. Policies add up, so the existing block list stays as it is | (a) Telling operators to shrink `K8S_RUNTIME_BLOCKED_IPV4_CIDRS`: an `except` list cannot carve one host out without rewriting the whole range, and it widens the sandbox. (b) Resolving the GitLab host and allowing its IPs automatically: a policy is fixed at namespace bootstrap and DNS changes underneath it, and it would silently widen egress |
| Private CA, both sides | One deployment variable, `EXTRA_CA_CERTS_FILE` (a PEM file of CA certificates). The Flow server adds it to its OpenSSL trust at boot. Sessions get its content as an environment variable, and the image adds it to the system bundle and to `mitmdump`'s upstream trust | (a) Per-integration CA field: the instance is deployment-wide, and so is the trust. (b) `SSL_CERT_FILE` documented only: it replaces the public roots unless the operator builds a full bundle, and it does nothing for session containers. (c) A Kubernetes volume for sessions: `build_pod` has no volumes, and Docker and runners would need their own path. An environment variable covers all three. (d) `ssl_insecure` in mitmdump: turns off verification |
| Relative URL root | Fix the two places that drop or keep the path wrongly: the OAuth token POST and the tracker's issue-URL path | — |
| MR URL matching | Compare as URIs (case-insensitive host, default port dropped), and document that `GITLAB_ENDPOINT` must use GitLab's `external_url` | Accepting any host: a reference to another instance would then resolve to a local MR |
| Hook heuristic | An explicitly set `GITLAB_WEBHOOK_BASE_URL` is trusted: hooks are registered unless it is a loopback host. The heuristic remains for the default (`DOMAIN`) | A DNS lookup in the heuristic: split-horizon DNS on the Flow pod says nothing about GitLab's view |
| Service-account refusal | Explain a self-managed refusal (403/404) in self-managed terms: the admin setting, the version and tier, the token alternative | Probing the instance's version and license up front: one more privileged call before the person has even picked a group |
| Endpoint duplication, config inventory, docs | `TokenService` uses `Gitlab::Host`. `.env.example` gets the GitLab block. The user guide and reference are rewritten for self-managed | — |

All changes are inert on gitlab.com and on a deployment that sets none of the new variables:

- no new policy;
- no extra environment variable in sessions;
- `mitmdump` keeps certifi;
- boot is unchanged.

## 4. Data model, API and configuration changes

- **Data model:** none.
- **HTTP API / tools:** none. `pull_request_*` and `tracker_*` keep their contracts, and only reference
  parsing gets more lenient.
- **New settings** (`config/settings.yml` + `.env.example` + `docs/reference/configuration.md` + its portal
  copy `app/frontend/pages/Docs/data/pages/config-schema.md`):

| Env var | Setting | Default | Meaning |
|---|---|---|---|
| `EXTRA_CA_CERTS_FILE` | `tls.extra_ca_certs_file` | unset | Path, on the Flow server and Temporal worker, to a PEM file with one or more CA certificates to trust in addition to the public roots. Its content is also passed to every agent session |
| `K8S_RUNTIME_ALLOWED_EGRESS_CIDRS` | `kubernetes.runtime_allowed_egress_cidrs` | empty | Private CIDRs agent pods may reach despite the block list, e.g. `10.20.0.15/32` for GitLab |
| `K8S_RUNTIME_ALLOWED_EGRESS_PORTS` | `kubernetes.runtime_allowed_egress_ports` | `443` | TCP ports for those CIDRs |

- **New container environment variable:** `AIXLE_EXTRA_CA_CERTS`, the PEM text. It is set only when
  `EXTRA_CA_CERTS_FILE` is. CA certificates are public, so an environment variable (visible in the pod
  spec) is acceptable. It is never a secret.

## 5. Implementation steps

Ordered. Each step is small and lands with its tests in the same implementation PR.

1. **Endpoint in one place.** `Gitlab::TokenService#gitlab_endpoint` returns `Gitlab::Host.api_endpoint`.
   Add `Gitlab::Host.self_managed?` (`URI(web_base).host` is not `gitlab.com`) for messages only.
2. **OAuth under a relative root.** In `Gitlab::Oauth.exchange_code`, post to the absolute
   `"#{Host.web_base}/oauth/token"` (or a relative `"oauth/token"` against a base ending in `/`), so that
   Faraday keeps the path.
3. **Tracker issue URLs under a relative root.** In `Trackers::Gitlab::Provider#reference_path`, strip the
   path of `URI(Gitlab::Host.web_base)` from the front of the captured path before it is compared. The
   host comparison stays as it is.
4. **Merge-request URLs.** In `PullRequests::Gitlab::Provider#owns_reference?`, parse both the reference and
   `web_url(repository, "")` with `URI`, and compare these:
   - scheme;
   - host, case-insensitively;
   - `port` (so an explicit `:443` equals none);
   - path prefix.

   `number_of` reuses the same check.
5. **Hook registration.** In `Gitlab::AppConfig.webhooks_enabled?`, return `!loopback?(host)` when
   `Settings.gitlab.webhook_base_url` is present. Otherwise keep today's rule. Update the comment and the
   `GITLAB_WEBHOOK_BASE_URL` description: on self-managed, set it to confirm the address GitLab reaches.
6. **Service-account refusals.** In `Gitlab::IntegrationService#service_account_refusal`, when
   `Gitlab::Host.self_managed?` and the code is `permission_denied` or `not_found`, answer in self-managed
   terms:

   > "This GitLab did not let you create a service account in that group. An administrator can create
   > it, or allow group Owners to (Admin → Settings → General → Account and limit). Service accounts
   > need GitLab 18.11 on Free, or Premium. You can connect with a token instead."

   The gitlab.com text stays as it is.
7. **Flow server trust.**
   - Add `lib/extra_ca_certs.rb`, a plain Ruby module with no Rails dependency, because it runs from
     `config/boot.rb`, which is an allowed `ENV` exception. Its `ExtraCaCerts.install!(path)` does nothing
     for a blank path. Otherwise it:
     - fails the boot if the file is unreadable or holds no certificate;
     - writes `Dir.tmpdir/aixle-ca-bundle.pem` = `OpenSSL::X509::DEFAULT_CERT_FILE` (when readable) + the
       file;
     - sets `ENV["SSL_CERT_FILE"]` to it. This covers every new `OpenSSL::X509::Store#set_default_paths`,
       for example `faraday-net_http`'s store;
     - calls `OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_file(path)`. This covers Net::HTTP and
       HTTParty, whose store was created when `openssl` loaded.
   - Call it first in `config/boot.rb` with `ENV["EXTRA_CA_CERTS_FILE"]`.
   - Add `tls.extra_ca_certs_file` to `settings.yml` for app code.
8. **Session trust, server side.**
   - Add `ExtraCaCerts.pem`, the file's content, memoized and read through `Settings.tls.extra_ca_certs_file`.
   - In `ContainerStrategies::AgentBaseStrategy#build_env_vars`, merge
     `{ "AIXLE_EXTRA_CA_CERTS" => ExtraCaCerts.pem }` when present, next to
     `GitCredentials::SessionGitSetup.container_env`.
9. **Session trust, image side.** In `docker/base/entrypoint.sh`, before `source /opt/mitm/start-mitm.sh`,
   add a block that runs when `AIXLE_EXTRA_CA_CERTS` is set:
   - write it to `$HOME/.aixle/extra-ca.pem`;
   - append it to `/etc/ssl/certs/ca-certificates.crt` (already 0666, `docker/base/Dockerfile:128`), only
     if it is not there yet;
   - this runs even with `MITM_DISABLED=true`.

   In `start-mitm.sh`, when `$HOME/.aixle/extra-ca.pem` exists:
   - copy the system bundle to `$MITMPROXY_DIR/upstream-ca-bundle.pem` **before** the MITM CA is
     appended;
   - add `--set ssl_verify_upstream_trusted_ca=<that file>` to `mitmdump`.

   The clone runs through `exec` after `wait_for_ready`, whose ports open only after this block has run,
   so it already sees the appended system bundle. `SessionGitSetup` does not change. Agent images are
   rebuilt from `docker/base` as usual.
10. **Kubernetes egress allowlist.** In `KubernetesRuntime`:
    - add `build_private_egress_network_policy(namespace)` to `runtime_network_policies` when
      `runtime_allowed_egress_cidrs` is non-empty;
    - the policy is `podSelector: {}`, `Egress` to each CIDR as an `ipBlock`, on the configured TCP ports;
    - name it `runtime-allow-private-egress-<first 8 hex of SHA-256 of the sorted CIDRs and ports>`, with
      the label `aixle.com/policy: private-egress`.

    `ensure_network_policy` only creates, never updates (see the comment above
    `build_traefik_ingress_network_policy`). The digest in the name is what makes a changed value take
    effect in existing namespaces. The policy it replaces is **not** deleted: the runtime has no delete
    permission on network policies. The operator removes it, and the docs give the
    `kubectl delete networkpolicy -l aixle.com/policy=private-egress` step. Reuse
    `kube_cidr_list_setting` for parsing.
11. **Configuration inventory.** Add a `# --- GitLab ---` block to `.env.example` (the existing four
    variables plus `EXTRA_CA_CERTS_FILE`), and the two `K8S_RUNTIME_ALLOWED_EGRESS_*` variables next to
    the blocked-CIDR ones. Add the three new rows to `docs/reference/configuration.md` and `config-schema.md`.
12. **User guide.** Rewrite "Self-managed GitLab" in `docs/user-guide/gitlab.md` and its portal copy. Cover:
    - the operator's checklist (§8 of this document);
    - `GITLAB_ENDPOINT` = `external_url` + `/api/v4`;
    - the version table (§2.7);
    - service accounts on self-managed: who may create them, the admin setting, the 100-per-instance limit
      on Free;
    - the private CA;
    - the egress allowlist;
    - the GitLab admin's *local network* setting for hooks.

    Fix the stale **Limits** section. Fix `gitlab.com/oauth/authorize` in `gitlab-tracker.md` §4 to
    `<GitLab>/oauth/authorize`.
13. **CHANGELOG** (implementation PR): under `[Unreleased]`, add `- **Integrations**:` entries for the CA,
    the egress allowlist and the self-managed fixes. Check the area name against
    `docs/product/changelog-product-areas.md`.

## 6. Testing approach

Follow `docs/testing.md`: WebMock at the HTTP boundary, real collaborators, no `any_instance`. The GitLab
contract tests stub `Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: GITLAB_API))`. The new
cases use `GITLAB_API = "https://gitlab.corp.example:8443/gitlab/api/v4"`.

| Test file | New cases |
|---|---|
| `test/services/gitlab/token_service_test.rb` | the client uses `Gitlab::Host.api_endpoint` (a non-default endpoint is the one called) |
| `test/services/gitlab/integration_service_test.rb` (OAuth connect) | under a relative root the token POST hits `…/gitlab/oauth/token`. On a self-managed host, a 403 and a 404 from `POST /groups/:id/service_accounts` produce the self-managed message, and gitlab.com keeps its text |
| `test/services/internal_tools/tracker_tools_gitlab_test.rb` (or the provider's own test) | `https://corp.example/gitlab/grp/proj/-/issues/5` resolves to `grp/proj#5`, and a URL on another host is still refused |
| `test/services/pull_requests/gitlab/provider_test.rb` | `owns_reference?` accepts an upper-case host and an explicit `:443`, and refuses another host and another root |
| `test/services/gitlab/app_config_test.rb` | an explicit private `GITLAB_WEBHOOK_BASE_URL` with a public-looking GitLab registers hooks, and a loopback one still does not |
| `test/lib/extra_ca_certs_test.rb` | blank path → nothing changes. A valid PEM (a test CA generated in the test) → the bundle is written, `SSL_CERT_FILE` points at it, and a certificate signed by the test CA verifies against both a fresh `OpenSSL::X509::Store#set_default_paths` and `DEFAULT_CERT_STORE`. An unreadable or certificate-free file raises. Restore `ENV` in `teardown` |
| `test/services/container_strategies/…agent_base_strategy…` (where `build_env_vars` is tested) | `AIXLE_EXTRA_CA_CERTS` is present only when the setting is |
| `test/services/container_runtime/kubernetes_runtime_test.rb` | the existing bootstrap test still sees exactly the seven policies when the allowlist is empty. With CIDRs, an eighth policy with the digest name, the label, the `ipBlock`s and the ports. A changed value gives a different name |

Shell changes (`entrypoint.sh`, `start-mitm.sh`) have no unit tests in this repository. They are covered
by the live check below.

**Live check on Coder** (implementation step, recorded in the PR):

1. Allocate a Coder workspace.
2. Create a private CA with `openssl`, and issue `gitlab.test` from it.
3. Run `gitlab/gitlab-ce:<latest 18.x>` with `external_url 'https://gitlab.test/gitlab'` (a relative root on
   purpose) and that certificate. Then repeat the service-account cases on `gitlab/gitlab-ee` unlicensed
   (= Free).
4. Run the Flow stack from the branch with Compose on the same workspace (Docker runtime), with:
   - `GITLAB_ENDPOINT=https://gitlab.test/gitlab/api/v4`;
   - `EXTRA_CA_CERTS_FILE`;
   - `GITLAB_WEBHOOK_BASE_URL` set to Flow's address on the Docker network;
   - GitLab's local-network hook setting on, and Flow's CA in GitLab's trust (`/etc/gitlab/trusted-certs`).

Cases:

1. Connect with a personal access token. The connection is Active.
2. Sign in with GitLab as a group Owner, without the admin setting: the self-managed refusal text. With the
   setting on: a service account is created. Record CE vs EE.
3. List and attach a repository. The pipeline hook is registered (GitLab → Settings → Webhooks).
4. A session clones the repository, then the agent fetches and pushes a branch (through `mitmdump`).
5. `pull_request_create`, `pull_request_get` (by URL copied from GitLab), `pull_request_checks`,
   `pull_request_add_comment`, `pull_request_merge`.
6. A pipeline gate resolves through the hook within a minute. With the hook deleted, it resolves through the
   sweep.
7. Tracker: pick a project and board, an issue event starts a workflow, an issue referenced by URL
   resolves, and a file both ways.
8. Without `EXTRA_CA_CERTS_FILE`: the token check reports the SSL error, and the clone fails. This proves
   the CA is what makes it work.

The Kubernetes allowlist is not exercised on Compose. It is covered by the runtime test, and checked on
staging by attaching a repository from an in-cluster GitLab address with and without the allowlist.

## 7. Edge cases and risks

- **Changing the allowlist leaves the old policy behind** (step 10), and the old policy still allows its
  CIDRs. The docs give the cleanup command. If the deployment repository later grants delete on
  network policies, the runtime can remove labelled policies whose name is not the current one.
- **The allowlist widens the sandbox.** Every agent session in every project can reach those CIDRs on those
  ports. The docs say to list `/32`s of the GitLab host, not subnets. The ports default to 443 only.
- **`mitmdump` trust changes source** when `EXTRA_CA_CERTS_FILE` is set, from certifi to the image's Debian
  bundle plus the extra CA. Both carry the Mozilla roots, so public hosts behave the same. Without the
  variable nothing changes.
- **Boot failure on a bad CA file** is deliberate: a silently missing CA shows up later as clone failures
  in sessions, which are hard to trace back.
- **Long PEM in the environment.** A bundle of a few certificates is a few KB, well within environment
  limits. The docs recommend only the issuing CA chain.
- **Agent images must be rebuilt** for step 9. An image older than the server ignores
  `AIXLE_EXTRA_CA_CERTS`, and private-CA clones keep failing. The release notes say so.
- **A different hostname in `GITLAB_ENDPOINT`** than GitLab's `external_url` still breaks MR URL references,
  by design. It is documented as a requirement.
- **Service accounts on CE** may not exist at all (EE code). Then only the token connection works on CE.
  The live check records it, and the docs state the outcome.
- **The tracker without a hook** starts nothing. With step 5, an operator who sets
  `GITLAB_WEBHOOK_BASE_URL` gets hooks. A hook GitLab refuses (local network not allowed) shows on the
  tracker as `failing` with GitLab's message (`Trackers::Gitlab::Subscriptions#failure_message`).
- **Step 5 on gitlab.com:** an operator who sets a private `GITLAB_WEBHOOK_BASE_URL` while on gitlab.com now
  gets an attempted hook, which gitlab.com refuses. `CiWebhook.register` logs it and does not raise, and
  the sweep resolves gates as before.

## 8. Operator checklist (goes into the user guide)

1. `GITLAB_ENDPOINT=https://<external_url host>[/<root>]/api/v4`.
2. If GitLab's certificate is from a private CA: `EXTRA_CA_CERTS_FILE=/path/ca.pem` on web and worker. Then
   rebuild or upgrade agent images to this release.
3. On Kubernetes, with GitLab on a private address:
   `K8S_RUNTIME_ALLOWED_EGRESS_CIDRS=<GitLab IP>/32`. Also make sure session pods resolve the GitLab name
   (cluster DNS).
4. `GITLAB_WEBHOOK_BASE_URL=<Flow address GitLab reaches>`. In GitLab: Admin → Settings → Network →
   Outbound requests → allow requests to the local network from webhooks. GitLab must trust Flow's
   certificate.
5. Optional, for Sign in with GitLab: an OAuth application (Admin → Applications, trusted, `api`, redirect
   `<PROTOCOL>://<DOMAIN>/integrations/gitlab/oauth/callback`) →
   `GITLAB_OAUTH_CLIENT_ID` / `GITLAB_OAUTH_CLIENT_SECRET`. Also turn on *Allow top-level group owners to
   create service accounts*, or have an administrator connect. Requires GitLab 18.11 on Free.

## 9. Decisions and assumptions

| # | Decision | Source |
|---|---|---|
| D1 | Write a design rather than an assessment-only comment: §2 has ❌ items | Task, Stage 2 |
| D2 | One instance per deployment stays. No per-connection URL | Task, out of scope. `gitlab-tracker.md` §6 |
| D3 | The CA is deployment-wide and also covers non-GitLab hosts (Jira Data Center, YouTrack), because the trust is per process | `Gitlab::Host` is deployment-wide. The process uses one OpenSSL store |
| D4 | Server-side CA through `config/boot.rb` + `lib/` | context.md: `config/boot.rb` is an allowed `ENV` exception, and the store must be set before any client is built |
| D5 | Session CA as an environment variable, not a file or a volume | `KubernetesRuntime#build_pod` has no volumes. Environment reaches Docker, Kubernetes and runners alike. The exec'd clone sees pod env |
| D6 | The egress allowlist is explicit, by CIDR, operator-owned | The default-deny sandbox in `runtime_network_policies`. Least privilege |
| D7 | `GITLAB_ENDPOINT` must be GitLab's `external_url`. Only URI normalization is added | GitLab writes `external_url` into every web URL. Accepting other hosts would weaken reference ownership |
| D8 | An explicit `GITLAB_WEBHOOK_BASE_URL` is trusted | It is the operator's statement of what GitLab reaches. The default stays heuristic |
| D9 | Public repositories stay gitlab.com-only | `Repository::PUBLIC_HOSTS` is an SSRF boundary. Self-managed projects attach through the connection |
| D10 | Kubernetes is the self-hosted production runtime, and its manifests are outside this repository | context.md, "Container Runtime". The agent-runtime registry doc names the deployment repository |
| D11 | Assumptions A1–A4 hold until the customer says otherwise. Recommended floor: GitLab 18.11 | Task, "Assumptions" |

## 10. Deferred

- **A polling fallback for GitLab tracker events** when no hook can be registered. This is a feature, not a
  self-managed fix, and the hook path covers the customer's setup (A3).
- **GitLab on Coder workspaces** (`Coder::RepoBootstrap`). It is missing for gitlab.com too.
- **A "create a token" link** in the GitLab connect dialog, built from the instance URL. It is convenient,
  but nothing is broken without it.
- **Relative `/-/project/<id>/uploads/…` links** not matched by `Trackers::Gitlab::Provider::UPLOAD`. GitLab
  writes `/uploads/…` in Markdown, so this is not specific to self-managed. File it separately if it is
  seen.
- **Several GitLab instances per deployment.** Out of scope, a documented limit.
- **External runners (`kubernetes`, `manual`)** get `AIXLE_EXTRA_CA_CERTS` through the same environment.
  Their own egress rules are the runner's (`docs/design/agent-runtimes/DESIGN.md`).
