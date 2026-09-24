# Configuration reference

Every environment variable Aixle Flow reads, what it does, and whether
it's required.

> **info** **Keep secrets out of git.** Variables live in `.env.development` for local dev, `.env.production` for production. Anything that's a secret should never be committed. See `.env.example` for the template.

Almost everything here is read in one place — `config/settings.yml` (plus the
per-environment files beside it) — and reached from code as `Settings.*`. The
handful of variables read before the settings file loads (the web server's own
knobs) are called out in *Process and boot* below. A test
(`test/config/configuration_reference_test.rb`) fails if a variable is added to
the settings files without a row here, or if a row here names a variable
nothing reads, and a rubocop cop (`Configuration/NoEnvInApp`) keeps application
code from reading the environment behind this file's back.

## Core Rails

| Variable                | Required   | Default          | Purpose                                                       |
| ----------------------- | ---------- | ---------------- | ------------------------------------------------------------- |
| `RAILS_SECRET_KEY_BASE` | yes (deployed) | dev key      | Rails secret key base — session encryption, signed IDs.       |
| `RAILS_MAX_THREADS`     | no         | `10`             | Thread budget: Puma pool, the Active Record pool (`+3`), and the Temporal worker's activity slots (80% of it). |
| `APP_VERSION`           | no         | `unknown`        | Version string shown in the UI and used as the Sentry release. Set as a build arg by the Dockerfile. |
| `DOMAIN`                | no         | `localhost:4000` | Public host the app is reachable at. Also the mailer's domain. |
| `PROTOCOL`              | no         | `https`          | `http` or `https` (development and test default to `http`).   |
| `ASSET_HOST`            | no         | `localhost:4000` | Host static assets are served from; also becomes the frontend build's asset host. |
| `CONTAINER_ASSET_HOST`  | no         | `web:4000`       | Host an agent container uses to fetch and upload assets.      |
| `CSP_ENFORCE`           | no         | `false`          | `true` enforces the full Content-Security-Policy; otherwise it is sent report-only (violations go to Sentry's security endpoint when `SENTRY_FRONTEND_DSN` is set). `base-uri`, `object-src` and `frame-ancestors` are enforced either way. |
| `ALLOWED_HOSTS`         | no         | unset            | Comma-separated `Host` header allowlist (DNS rebinding and Host header protection). Unset leaves it off. Name every host the app is dialed on: `DOMAIN` and its `www.`, a separate webhook host, and the in-cluster service names agent containers (`INTERNAL_BASE_URL`) and Traefik's ForwardAuth use — anything missing gets a 403. `/up` is always allowed. |

## Process and boot

Read straight from the environment, before or outside the settings files.

| Variable                        | Required | Default             | Purpose                                                     |
| ------------------------------- | -------- | ------------------- | ----------------------------------------------------------- |
| `PORT`                          | no       | `4000`              | Port the web Puma listens on (`config/puma.rb`). Also the port `domain`, `asset_host` and `container_asset_host` default to, so overriding it moves the whole stack — which is how a second stack runs beside the first on one machine. |
| `RAILS_MIN_THREADS`             | no       | `RAILS_MAX_THREADS` | Puma's minimum thread count.                                 |
| `PIDFILE`                       | no       | `tmp/pids/server.pid` | Web Puma pidfile.                                          |
| `SOLID_QUEUE_IN_PUMA`           | no       | unset               | `false` stops Puma from supervising Solid Queue in-process — set it wherever the queue runs as its own workload. |
| `MCP_PORT`                      | no       | `4002`              | Port the MCP Puma listens on (`config/puma_mcp.rb`), and the port `INTERNAL_BASE_URL` defaults to. |
| `MCP_MAX_THREADS`               | no       | `RAILS_MAX_THREADS` | MCP Puma thread budget.                                      |
| `MCP_MIN_THREADS`               | no       | `MCP_MAX_THREADS`   | MCP Puma minimum thread count.                               |
| `MCP_PIDFILE`                   | no       | `tmp/pids/mcp.pid`  | MCP Puma pidfile.                                            |
| `RAILS_ENV`                     | no       | `development`       | Rails environment; also selects the per-environment settings file. |
| `RAILS_LOG_TO_STDOUT`           | no       | unset               | Log to stdout — set it in containers.                        |
| `RAILS_LOG_LEVEL`               | no       | `info`              | Log level in production and QA (`error` in test).            |
| `AIXLE_TOOLS_RECONCILE_ON_BOOT` | no       | unset               | `0` skips the internal-tool registry reconciliation at boot. |
| `WORKER_BOOT_CHECK_TIMEOUT`     | no       | `180`               | Seconds `bin/worker_boot_check` waits for the Temporal worker to come up. |

## Database & cache

| Variable      | Required | Default               | Purpose                                                        |
| ------------- | -------- | --------------------- | -------------------------------------------------------------- |
| `DB_HOST`     | yes      | `127.0.0.1`           | Postgres host.                                                 |
| `DB_PORT`     | no       | `5432`                | Postgres port.                                                 |
| `DB_NAME`     | yes      | unset                 | Database name.                                                 |
| `DB_USERNAME` | no       | `postgres`            | DB user.                                                       |
| `DB_PASSWORD` | no       | empty                 | DB password.                                                   |
| `DB_POOL`     | no       | `RAILS_MAX_THREADS+3` | Overrides the derived Active Record pool size outright. Keep it above the process' thread count: one request thread holds one connection, and an equal pool leaves no headroom for checkouts that are not request-bound. |
| `REDIS_URL`   | yes      | `redis://redis:6379/1` | Redis connection URL.                                         |

## Encryption keys

> **warning** **Rotate carefully.** Generate with `openssl rand -hex 32`. To rotate one, set the new value, move the old one into its `_PREVIOUS` variable, deploy, then run `bin/rails encryption:reencrypt`; clear `_PREVIOUS` once it reports nothing left on an old key (`DRY_RUN=true` only reads and lists what no key can read). A secret no configured key can read is refused loudly (the session or request fails and asks for a reconnect) — it is never treated as empty.

All four are mandatory in every deployed environment (production and staging):
`config/initializers/required_env.rb` fails the boot if any is blank. Development
and test fall back to fixed non-secret values.

| Variable                  | Purpose                                                       |
| ------------------------- | ------------------------------------------------------------- |
| `CREDENTIALS_SECRET_KEY`  | Encrypts user agent credentials at rest.                      |
| `CONFIG_ITEMS_SECRET_KEY` | Encrypts config items (project/company secrets).              |
| `INTEGRATIONS_SECRET_KEY` | Encrypts git host and other integration tokens.               |
| `OAUTH_SECRET_KEY`        | Encrypts OAuth client secrets and stored provider tokens.     |
| `CREDENTIALS_SECRET_KEY_PREVIOUS`  | Optional. Retired `CREDENTIALS_SECRET_KEY` value(s), comma-separated, still read during a rotation. |
| `CONFIG_ITEMS_SECRET_KEY_PREVIOUS` | Optional. Retired `CONFIG_ITEMS_SECRET_KEY` value(s), as above. |
| `INTEGRATIONS_SECRET_KEY_PREVIOUS` | Optional. Retired `INTEGRATIONS_SECRET_KEY` value(s), as above. |
| `OAUTH_SECRET_KEY_PREVIOUS`        | Optional. Retired `OAUTH_SECRET_KEY` value(s), as above.        |
| `ENCRYPTION_BIND_PURPOSE`          | Optional, default `false`. `true` binds every new ciphertext to its model and column. Turn it on once no pod of the previous release can run (that release reads a bound value as empty), then run `bin/rails encryption:reencrypt`. |

## Session queue

| Variable                              | Required | Default | Purpose                                                        |
| ------------------------------------- | -------- | ------- | -------------------------------------------------------------- |
| `DEPLOYMENT_MODE`                     | no       | `saas`  | One of `self_hosted`, `saas`, `aws_marketplace`. Decides who may move a company's session limit and where the installation's capacity is metered: nowhere for `self_hosted`, Stripe for `saas`, AWS Marketplace for `aws_marketplace`. Unset or unrecognised reads as `saas`, so a hosted installation cannot grant itself capacity by omission. Development and test default to `self_hosted`. |
| `SESSION_PROJECT_CONCURRENCY_DEFAULT` | no       | `4`     | Queue size for a project that has set no limit of its own. Read live — takes effect on the next boot of each pod. |
| `SESSION_PINNED_RELEASE_ENABLED` | no | `true` | `false` stops the reconciler from ending a pinned reservation on its own, leaving it for an operator. A reservation is pinned when a create or start never reported its outcome; the slot is held so a late Pod cannot land on someone else's. |
| `SESSION_PINNED_RELEASE_CONFIRMATION_MINUTES` | no | `5` | How long the reconciler must keep re-proving that no workload exists before it abandons such an operation and releases the slot. A pass that sees the workload again resets the clock. |

A row in `session_concurrency_limits` overrides the default for one project or
user; edit those in the admin, not here.

## Internal URLs & routing

| Variable                | Required | Default                              | Purpose                                                    |
| ----------------------- | -------- | ------------------------------------ | ---------------------------------------------------------- |
| `INTERNAL_BASE_URL`     | no       | `http://web:4002`                    | How agent containers reach this app over the docker network or cluster DNS. The two URLs below are derived from it. |
| `MCP_SERVER_URL`        | no       | `<internal base>/action_mcp`         | Overrides the internal MCP endpoint injected into agent containers. |
| `MCP_PUBLIC_SERVER_URL` | no       | `<protocol>://<domain>/mcp`          | The URL users configure their own MCP clients with (personal token) — a public host, unlike `MCP_SERVER_URL`. |
| `CLOUD_CREDENTIALS_URL` | no       | `<internal base>/cloud/aws/credentials` | Where the in-container credential helper asks for short-lived cloud credentials. Never a public host: the request carries a per-session vending key. |
| `TRAEFIK_HTTP_BASE`     | no       | `http://localhost`                   | Public base URL agent session URLs are built on. Serve containers from a host of their own (`https://t.example.com` beside `DOMAIN=example.com`): whatever a container answers is its agent's, and on the app's host it would run with the viewer's standing in the app. On another host the container links carry a short-lived ticket that the gate trades for a cookie on that host; route the host to Traefik and give it a certificate. |
| `TRAEFIK_WS_BASE`       | no       | derived from `TRAEFIK_HTTP_BASE`     | Same origin over websockets (`http`→`ws`, `https`→`wss`). Set it only to override the derived value. |
| `TRAEFIK_INTERNAL_URL`  | no       | `http://traefik`                     | Traefik as seen from inside the docker network.            |

## Temporal

| Variable                                   | Required | Default             | Purpose                                     |
| ------------------------------------------ | -------- | ------------------- | ------------------------------------------- |
| `TEMPORAL_ENABLED`                         | no       | unset (on in dev and prod) | Toggles Temporal workflow execution. |
| `TEMPORAL_HOST`                            | no       | `temporal`          | Temporal server host.                       |
| `TEMPORAL_PORT`                            | no       | `7233`              | Temporal server port.                       |
| `TEMPORAL_NAMESPACE`                       | no       | `default`           | Temporal namespace.                         |
| `TEMPORAL_TASK_QUEUE`                      | no       | `aixle_ruby`        | Task queue name.                            |
| `TEMPORAL_WORKER_GRACEFUL_SHUTDOWN_PERIOD` | no       | `900`               | Seconds the worker drains for on shutdown.  |
| `TEMPORAL_WORKER_MAX_THREADS`              | no       | `RAILS_MAX_THREADS`, else `5` | The worker's thread budget: activity slots are 80% of it, and the worker's Active Record pool is sized from it. Set it to scale worker concurrency without touching the web pods. |

## Container runtime

The Docker runtime is single-tenant: every company's agents run on one host and
share one agent network, so it suits one team's own installation. It keeps
agents off the platform's data stores (see `DOCKER_AGENT_NETWORK`), but a
deployment that serves several companies runs the Kubernetes runtime, whose
per-project namespaces and network policies separate them.

| Variable                       | Required | Default           | Purpose                                                          |
| ------------------------------ | -------- | ----------------- | ---------------------------------------------------------------- |
| `CONTAINER_RUNTIME`            | no       | `docker`          | `kubernetes` (or `k8s`, which the deployed ConfigMaps use) selects the Kubernetes runtime; anything else, including the default, selects Docker. |
| `DOCKER_NETWORK`               | no       | `app_default`     | The stack's own Docker network (web, db, redis, temporal).       |
| `DOCKER_AGENT_NETWORK`         | no       | `DOCKER_NETWORK`, else `app_agents` | The Docker network agent containers join. Keep it separate from `DOCKER_NETWORK`: it should reach web, otlp-ingest and traefik and nothing else. |
| `AGENT_IMAGE_PREFIX`           | no       | `aixle/`          | Registry/name prefix every built-in runtime image is derived from: runtime `claude_code` becomes `<prefix>claude-code[:<tag>]`. Deployed environments default to `ghcr.io/aixlehq/flow-`, where the images are published. |
| `AGENT_IMAGE_TAG`              | no       | `latest`          | Tag appended to derived images; blank means the registry default. Deployed environments default to blank. |
| `AGENT_IMAGE_CLAUDE_CODE`      | no       | derived           | Per-runtime override (a digest pin, or a different registry).    |
| `AGENT_IMAGE_CURSOR_CLI`       | no       | derived           | Per-runtime override.                                            |
| `AGENT_IMAGE_CODEX`            | no       | derived           | Per-runtime override.                                            |
| `AGENT_IMAGE_GEMINI_CLI`       | no       | derived           | Per-runtime override.                                            |
| `AGENT_IMAGE_ANTIGRAVITY_CLI`  | no       | derived           | Per-runtime override.                                            |
| `AGENT_IMAGE_GROK`             | no       | derived           | Per-runtime override.                                            |
| `AGENT_IMAGE_KIRO_CLI`         | no       | derived           | Per-runtime override.                                            |
| `AGENT_MCP_STARTUP_TIMEOUT_MS` | no       | `90000`           | How long an agent CLI waits for its MCP servers to hand shake.   |
| `AGENT_CREDENTIAL_SYNC_URL`    | no       | derived from `INTERNAL_BASE_URL` | Where the in-container watcher reports a token the CLI rotated. Internal host only: the request carries a per-session write-back key. |
| `ANTIGRAVITY_OAUTH_CLIENT_ID`  | no       | —                 | Google OAuth client `agy` signs a consumer login in with. With the secret, Antigravity tokens are refreshed server-side; unset, only the CLI in the container renews them. |
| `ANTIGRAVITY_OAUTH_CLIENT_SECRET` | no    | —                 | The matching secret. Never commit it: secret scanning reports it to Google, which revokes the client for every `agy` user. |

### Kubernetes runtime (when `CONTAINER_RUNTIME=kubernetes`)

| Variable                          | Required | Default                                                | Purpose                                                     |
| --------------------------------- | -------- | ------------------------------------------------------ | ----------------------------------------------------------- |
| `KUBECONFIG`                      | no       | `$HOME/.kube/config`                                   | Kubeconfig path when running outside the cluster.           |
| `KUBERNETES_SERVICE_HOST`         | no       | `kubernetes.default.svc`                               | Kubernetes API host (the kubelet injects this in-cluster).  |
| `KUBERNETES_SERVICE_PORT`         | no       | `443`                                                  | Kubernetes API port.                                        |
| `K8S_NAMESPACE`                   | no       | `aixle`                                                | Namespace agent pods are created in.                        |
| `K8S_SA_TOKEN_PATH`               | no       | `/var/run/secrets/kubernetes.io/serviceaccount/token`  | Service account token path.                                 |
| `K8S_SA_CA_PATH`                  | no       | `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` | Service account CA certificate path.                        |
| `K8S_AGENTS_IMAGE_PULL_SECRETS`   | no       | empty                                                  | Comma-separated image pull secrets for agent pods.          |
| `K8S_AGENTS_NODE_POOL`            | no       | empty                                                  | Pin agent pods to a node group: comma-separated `key=value[:Effect]`. Each entry becomes both a `nodeSelector` label and a matching toleration. Leave unset where no such node group exists, or every agent pod stays Pending. |
| `K8S_IMAGE_PULL_POLICY`           | no       | `IfNotPresent`                                         | Pod image pull policy for a pinned image; an image with no tag or `latest` is always pulled. |
| `K8S_READY_TIMEOUT`               | no       | `60`                                                   | Seconds to wait for a pod to become Ready.                  |
| `K8S_READY_INTERVAL`              | no       | `1`                                                    | Seconds between readiness polls.                            |
| `K8S_RUNTIME_REQUESTS_CPU`        | no       | `100m`                                                 | Agent pod CPU request.                                      |
| `K8S_RUNTIME_REQUESTS_MEMORY`     | no       | `512Mi`                                                | Agent pod memory request.                                   |
| `K8S_RUNTIME_LIMITS_CPU`          | no       | `1000m`                                                | Agent pod CPU limit.                                        |
| `K8S_RUNTIME_LIMITS_MEMORY`       | no       | `1Gi`                                                  | Agent pod memory limit.                                     |
| `K8S_RESTRICTED_AGENT_PODS`   | no       | `false`           | `true` applies the Pod Security *restricted* profile to agent pods: non-root, every capability dropped, RuntimeDefault seccomp. Requires agent images that run as a non-root user. Without it agent pods still run with no privilege escalation and no raw sockets. |
| `K8S_SERVICE_PORTS`               | no       | `7681,4040`                                            | Ports the agent pod's service exposes.                      |
| `K8S_WORKSPACE_DIR`               | no       | `/workspace`                                           | Workspace directory inside the pod.                         |
| `K8S_EKS_VPC_CIDR`                | no       | `10.10.0.0/16`                                         | Cluster VPC CIDR, allowed through the agent egress policy.   |
| `K8S_RUNTIME_BLOCKED_IPV4_CIDRS`  | no       | RFC1918 + CGNAT + link-local                           | IPv4 ranges agent pods may not reach.                       |
| `K8S_RUNTIME_BLOCKED_IPV6_CIDRS`  | no       | `fc00::/7,fe80::/10`                                   | IPv6 ranges agent pods may not reach.                       |
| `K8S_TRAEFIK_VERIFY_TLS`          | no       | `true`                                                 | Verifies the certificate of `TRAEFIK_HTTP_BASE` when the app probes a new session's route. Set `false` only when that points at a listener with a self-signed certificate (a probe that cannot verify waits out `K8S_READY_TIMEOUT` before the session starts). |
| `TRAEFIK_ENTRYPOINT`              | no       | `websecure`                                            | Traefik entrypoint agent routes are attached to.            |
| `TRAEFIK_AUTH_MIDDLEWARE`         | no       | `terminal-auth`                                        | Traefik middleware that authenticates agent routes.         |

## Coder integration

| Variable                           | Required | Default  | Purpose                                                                 |
| ---------------------------------- | -------- | -------- | ----------------------------------------------------------------------- |
| `CODER_AWAIT_BUILD_TIMEOUT`        | no       | `240`    | Seconds `await_build` polls a workspace build for.                      |
| `CODER_HEALTH_PROBE_ENABLED`       | no       | `true`   | `false` falls back to passive (agent-reported) health filtering, and also disables the dead-workspace reaper. |
| `CODER_HEALTH_PROBE_TIMEOUT`       | no       | `15`     | Seconds the active SSH health probe may take.                           |
| `CODER_HEALTH_LOAD_FACTOR`         | no       | `2.0`    | Reject a workspace when its 1-minute load average exceeds `cores × this`. |
| `CODER_UNHEALTHY_COOLDOWN_MINUTES` | no       | `30`     | How long a workspace stays out of the pool after failing a probe.       |
| `CODER_SSH_EXEC_INLINE_BYTES`      | no       | `262144` | Total response budget for one `coder_ssh_exec`; the rest is read back through the tool-result path. |
| `CODER_SSH_EXEC_CEILING_SECONDS`   | no       | `120`    | Wall-clock ceiling one `coder_ssh_exec` can reach regardless of its own timeout. Longer work must run detached. |
| `CODER_JOB_STATUS_TAIL_LINES`      | no       | `40`     | Log tail `coder_job_status` returns by default.                          |
| `CODER_REAP_ENABLED`               | no       | `true`   | `false` disables deletion of dead workspaces. The reaper only ever looks at workspaces the integration's token owns under its machine prefix, and does nothing for an integration without one; a workspace whose last start or stop failed is confirmed twice like a dead one, and one whose delete failed is left for an operator. |
| `CODER_REAP_CONFIRMATION_MINUTES`  | no       | `10`     | How far apart the two "this box is dead" observations must be before a workspace is deleted. |
| `CODER_REAP_MAX_DELETIONS_PER_RUN` | no       | `3`      | Cap on deletions in one reaper sweep, however dead the pool looks.       |

A Coder integration's template and machine prefix are per-integration settings
stored on the integration row, not environment variables.

## CI gates

| Variable                         | Required | Default | Purpose                                                            |
| -------------------------------- | -------- | ------- | ------------------------------------------------------------------ |
| `GATES_TTL_HOURS`                | no       | `12`    | How long a pending CI gate may wait for a webhook before it is marked stale. |
| `GATES_RECONCILE_AFTER_MINUTES`  | no       | `10`    | Grace before the first provider probe, and the minimum gap between probes. |
| `GATES_RECONCILE_BATCH_SIZE`     | no       | `100`   | Gates probed per reconciliation sweep.                              |

## Git host integration

| Variable                       | Required | Default                       | Purpose                                                    |
| ------------------------------ | -------- | ----------------------------- | ---------------------------------------------------------- |
| `GITHUB_APP_ID`                | no       | unset                         | GitHub App ID.                                             |
| `GITHUB_APP_SLUG`              | no       | unset                         | The App's slug (used to build install URLs).               |
| `GITHUB_APP_PRIVATE_KEY`       | no       | unset                         | GitHub App private key, inline (multi-line PEM).           |
| `GITHUB_APP_PRIVATE_KEY_PATH`  | no       | unset                         | Path to the key file instead, for deployments that mount the PEM as a secret. Read only when the inline key is blank. |
| `GITHUB_WEBHOOK_SECRET`        | no       | unset                         | HMAC secret verifying `/webhooks/github`.                  |
| `GITHUB_APP_CLIENT_ID`         | no       | unset                         | The App's OAuth client id. With the secret below (and "Request user authorization (OAuth) during installation" on the App), a new installation connects only for a user who can see it on GitHub. |
| `GITHUB_APP_CLIENT_SECRET`     | no       | unset                         | The App's OAuth client secret, paired with `GITHUB_APP_CLIENT_ID`. |
| `GITLAB_ENDPOINT`              | no       | `https://gitlab.com/api/v4`   | GitLab API base URL. Repositories clone from the same host. |
| `GIT_CREDENTIALS_URL`                   | no       | `<internal base>/agents/git/credentials`       | Where the in-container git credential helper asks for a short-lived GitHub or GitLab token. Never a public host: the request carries a per-session vending key. |

None of the `GITHUB_APP_*` variables is needed to connect GitHub: a project can
connect with a personal access token instead (stored encrypted per integration,
not an environment variable), which is the path a local deployment uses. The App
variables buy the production path — installation tokens scoped per repository,
and webhooks. Without them the connect dialog offers only the token path.

GitLab access uses a per-integration personal access token (stored encrypted,
not an environment variable). The GitLab webhook endpoint is verified with a
per-repository secret, also not an environment variable.

### Azure DevOps

One operator-owned multi-tenant Entra app registration per deployment (see
`docs/design/azure-devops-integration.md`). Customers do not register their own
app: their Entra administrator provisions a tenant-local service principal for
this client id. There is no enable flag — the feature is offered exactly when a
client id and one credential are present, or PAT mode is on.

| Variable                                | Required | Default                                        | Purpose                                                    |
| --------------------------------------- | -------- | ---------------------------------------------- | ---------------------------------------------------------- |
| `AZURE_DEVOPS_CLIENT_ID`                | no       | unset                                          | Client id of the deployment's Entra app registration (public). |
| `AZURE_DEVOPS_PRIVATE_KEY`              | no       | unset                                          | PEM private key of the certificate uploaded to that app — the production credential. Stays server-side. |
| `AZURE_DEVOPS_CERT_THUMBPRINT`          | no       | unset                                          | Thumbprint of that certificate.                            |
| `AZURE_DEVOPS_CLIENT_SECRET`            | no       | unset                                          | Client secret instead of the certificate — a setup/pilot alternative. Set exactly one of the two. |
| `AZURE_DEVOPS_CREDENTIAL_GENERATION`    | no       | `v1`                                           | Bump on every credential rotation: cached tokens minted under an older generation stop being served. |
| `AZURE_DEVOPS_PAT_MODE_ENABLED`         | no       | `false`                                        | `true` permits the PAT fallback identity, which acts as the token's owner and carries that person's upstream permissions. Opt-in per deployment. |
| `AZURE_DEVOPS_RESOURCE`                 | no       | `https://app.vssps.visualstudio.com/.default`  | OAuth resource for the client-credentials flow. Not a legacy ADAL value — do not "fix" it. |
| `AZURE_DEVOPS_LOGIN_HOST`               | no       | `https://login.microsoftonline.com`            | Entra token endpoint host; sovereign clouds use a different one. |
| `AZURE_DEVOPS_API_HOST`                 | no       | `https://dev.azure.com`                        | Azure DevOps API host.                                     |
| `AZURE_DEVOPS_WEBHOOK_BASE_URL`         | no       | `<protocol>://<domain>`                        | Where Azure posts Service Hook deliveries — the only inbound part of this integration. Set it only when the deployment's own domain is not reachable from Azure (a tunnel in development); a loopback or private host provisions no subscriptions at all. |
| `AZURE_DEVOPS_GIT_CREDENTIALS_URL`      | no       | `<internal base>/azure/git/credentials`        | Where the in-container git credential helper asks for a short-lived token. Never a public host: the request carries a per-session vending key. |
| `AZURE_DEVOPS_TOKEN_REFRESH_SKEW`       | no       | `300`                                          | Seconds before the recorded expiry at which a cached token counts as spent. |
| `AZURE_DEVOPS_COMPLETION_POLL_INTERVAL` | no       | `1.0`                                          | Seconds between re-reads while confirming a pull-request completion (Azure merges asynchronously). |
| `AZURE_DEVOPS_OPEN_TIMEOUT`             | no       | `5`                                            | Connection open timeout, in seconds.                       |
| `AZURE_DEVOPS_READ_TIMEOUT`             | no       | `30`                                           | Response read timeout, in seconds.                         |

## Auth & OAuth providers

| Variable                     | Required | Default            | Purpose                                                      |
| ---------------------------- | -------- | ------------------ | ------------------------------------------------------------ |
| `GOOGLE_CLIENT_ID`           | no       | unset              | Google SSO client ID.                                        |
| `GOOGLE_CLIENT_SECRET`       | no       | unset              | Google SSO client secret.                                     |
| `SUPER_ADMIN_EMAIL`          | no       | `admin@example.com` | The super admin `db/seeds.rb` creates (development and test only). |
| `ADMIN_PASSWORD`             | no       | unset              | First-boot bootstrap password for that admin.                  |
| `SESSION_IDLE_TIMEOUT_HOURS` | no       | `336` (14 days)    | A browser sign-in unused for this long is ended; the person signs in again. |
| `SESSION_MAX_AGE_HOURS`      | no       | `720` (30 days)    | A browser sign-in is ended this long after it began, however much it is used. |
| `SLACK_CLIENT_ID`            | no       | unset              | Slack app client ID — one app per deployment, multi-workspace via OAuth. |
| `SLACK_CLIENT_SECRET`        | no       | unset              | Slack app client secret.                                      |
| `SLACK_SIGNING_SECRET`       | no       | unset              | Verifies Slack event and interaction payloads.                |
| `SLACK_SCOPES`               | no       | `app_mentions:read,channels:history,groups:history,files:read,files:write,chat:write` | Bot scopes requested at install time. |
| `SENTRY_OAUTH_CLIENT_ID`     | no       | unset              | Client ID of the Sentry OAuth app users connect their org with. |
| `SENTRY_OAUTH_CLIENT_SECRET` | no       | unset              | Its client secret.                                            |
| `RAILWAY_OAUTH_CLIENT_ID`    | no       | unset              | Client ID of the Railway OAuth app.                           |
| `RAILWAY_OAUTH_CLIENT_SECRET` | no      | unset              | Its client secret.                                            |

## Mail

| Variable                | Required | Default | Purpose                              |
| ----------------------- | -------- | ------- | ------------------------------------ |
| `MAILER_ADDRESS`        | no       | unset   | SMTP server hostname.                |
| `MAILER_PORT`           | no       | unset   | SMTP port.                           |
| `MAILER_USERNAME`       | no       | unset   | SMTP username.                       |
| `MAILER_PASSWORD`       | no       | unset   | SMTP password.                       |
| `MAILER_AUTHENTICATION` | no       | `plain` | SMTP auth mechanism.                 |

## Storage (S3)

| Variable                | Required | Default | Purpose                                         |
| ----------------------- | -------- | ------- | ----------------------------------------------- |
| `AWS_ACCESS_KEY_ID`     | no       | unset   | S3-compatible access key.                       |
| `AWS_SECRET_ACCESS_KEY` | no       | unset   | S3 secret.                                      |
| `AWS_DEFAULT_REGION`    | no       | `fake`  | S3 region.                                      |
| `AWS_S3_BUCKET`         | yes (deployed) | `fake` (development, test) | Bucket used for uploads and asset storage. A deployed environment refuses to boot without it. |

## Observability

| Variable                      | Required | Default                      | Purpose                                                    |
| ----------------------------- | -------- | ---------------------------- | ---------------------------------------------------------- |
| `SENTRY_RAILS_DSN`            | no       | unset                        | Sentry DSN for the Rails app.                              |
| `SENTRY_FRONTEND_DSN`         | no       | unset                        | Sentry DSN for the React frontend (public by design).      |
| `SENTRY_TEMPORAL_DSN`         | no       | unset                        | Sentry DSN for the Temporal worker.                        |
| `SENTRY_TRACES_SAMPLE_RATE`   | no       | `1.0`                        | Share of requests (web) and activities (worker) traced; the OTLP ingest route is never traced. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no       | `http://otlp-ingest:4318`    | Base OTLP endpoint handed to agent containers, which append their own signal paths. No OpenTelemetry SDK runs in this app. |

## Catalogs & limits

| Variable                       | Required | Default                | Purpose                                                       |
| ------------------------------ | -------- | ---------------------- | ------------------------------------------------------------- |
| `MCP_REGISTRY_BASE_URL`        | no       | official MCP registry  | Point the connector catalog at a private subregistry implementing the same API. |
| `GITHUB_PUBLIC_READ_TOKEN`     | no       | unset                  | Raises the `api.github.com` limit from 60 to 5,000 requests/hour for the two paths that read public repositories (skills catalog, BMAD module tags). The anonymous 60/hour is per source IP, so every agent container shares one budget. Needs no scopes; never use a tenant installation token. |
| `URL_SAFETY_TRUSTED_HOSTS`     | no       | empty                  | Comma-separated public hostnames allowed to resolve to a private IP (split-horizon DNS for our own staging hosts). |
| `TOOL_RESULTS_RETENTION_DAYS`  | no       | `30`                   | How long a tool result's stored payload is kept.               |
| `CONTEXT_TOKEN_BUDGET`         | no       | `6000`                 | Token budget for rendered prompt context.                      |

## Docs explorer

| Variable        | Required | Default | Purpose                                                 |
| --------------- | -------- | ------- | ------------------------------------------------------- |
| `DOCS_LOGIN`    | no       | unset   | Basic-auth username for `/api-docs` (outside development). With it or the password unset, `/api-docs` admits nobody. |
| `DOCS_PASSWORD` | no       | unset   | Basic-auth password for `/api-docs`.                    |

## Development, test and CI

| Variable                    | Required | Default                    | Purpose                                                     |
| --------------------------- | -------- | -------------------------- | ----------------------------------------------------------- |
| `CI`                        | no       | unset                      | Marks a CI run: eager loading in test, slower frontend timeouts. |
| `SKIP_COVERAGE`             | no       | unset                      | `1` disables SimpleCov instrumentation.                     |
| `COVERAGE_MIN`              | no       | unset                      | Coverage floor for the run; set by the `make` check targets. |
| `PARALLEL_WORKERS`          | no       | number of processors       | `1` forces a serial test run.                               |
| `CHROMIUM_PATH`             | no       | `/usr/bin/chromium`        | Browser binary for system tests.                            |
| `ACTION_CABLE_URL`          | no       | `ws://localhost:4000/cable` | Cable URL in development.                                   |
| `VITE_RUBY_PORT`            | no       | `4001`                     | Port the Vite dev server binds to; Compose publishes the same one. |
| `SEED_COMPANY_SLUG`         | no       | `demo`                     | Company slug `db/seeds.rb` creates (development and test only — deployed environments never seed). |
| `SEED_COMPANY_NAME`         | no       | `Demo Company`             | Its display name.                                           |
| `SEED_COMPANY_EMAIL_DOMAIN` | no       | `example.com`              | Email domain seeded users get.                              |
| `SEED_COMPANY_ADMIN_EMAIL`  | no       | derived                    | Seeded admin's email address.                               |

## Catalog seed

Both catalogs are local mirrors filled by weekly sweeps, so a deployment that has
never run one would open the Connectors and Skills pages on an empty grid. To avoid
that, the curated entries (`Connector::FEATURED`, `CatalogSkill::FEATURED`) are
committed to the repo as `db/seeds/catalog/*.json` and loaded at boot — no network,
no token, no Temporal worker. The sweeps fill in the rest of the catalog later, and
never overwrite a mirrored row with the committed copy.

- `bin/docker-entrypoint` (the Compose entrypoint) runs `rails catalog:featured:load`
  after `db:prepare`. Nothing to configure.
- A deployment that does **not** use that entrypoint — Kubernetes, or any image
  started straight on `bundle exec puma` — should run `rails catalog:featured:load`
  wherever it runs migrations. The task is idempotent and safe to run on every deploy.
- After editing either `FEATURED` list, regenerate the files with
  `rails catalog:featured:dump` against a database whose mirror is already synced,
  and commit the result. A test fails if the two drift apart.

The Skills.sh registry needs no key: its v1 API authenticates with Vercel OIDC
only, so the catalog is browsed through the local mirror instead.

## Removed variables

These were read by nothing (or by a key nothing read) and have been deleted.
Setting them now has no effect, so they can be dropped from ConfigMaps, compose
files and CI build args:

- AUTHOR_NAME, AUTHOR_EMAIL — fed a settings key no code consulted. Agent
  commit identity does not come from here.
- RAILS_PORT — a second name for PORT that nothing read.
- TEMPORAL_UI_URL, REDIS_UI_URL, TRAEFIK_DASHBOARD_URL — no admin link ever
  consumed them.
- TRAEFIK_CORS_ORIGINS — CORS is not configured from a setting.
- OTEL_EXPORTER_OTLP_METRICS_ENDPOINT, OTEL_EXPORTER_OTLP_LOGS_ENDPOINT — only
  OTEL_EXPORTER_OTLP_ENDPOINT is read now; the one reader of the metrics
  endpoint stripped the signal suffix back off to recover the base.
- CODER_DEFAULT_TEMPLATE, CODER_MACHINE_PREFIX — both are per-integration
  columns, read straight off the integration row with no settings fallback.
- MAX_FILE_SIZE — read by nothing; upload limits come from the uploaders.
- ENVIRONMENT — a stray CI-only variable nothing read.
