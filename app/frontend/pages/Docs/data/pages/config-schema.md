# Configuration reference

Every environment variable Aixle Flow reads, what it does, and whether
it's required.

> **info** **Keep secrets out of git.** Variables live in `.env.development` for local dev, `.env.production` for production. Anything that's a secret should never be committed. See `.env.example` for the template.

## Core Rails

| Variable                | Required | Default              | Purpose                                                  |
| ----------------------- | -------- | -------------------- | -------------------------------------------------------- |
| `RAILS_SECRET_KEY_BASE` | yes (prod) | dev key             | Rails secret key base — session encryption, signed IDs.  |
| `RAILS_MAX_THREADS`     | no       | `5`                  | Thread budget: Puma pool, Temporal activity slots (80%), worker DB pool. |
| `RAILS_LOG_TO_STDOUT`   | no       | unset                | Log to stdout (use in containers).                       |
| `RAILS_PORT` / `PORT`   | no       | `4000`               | HTTP port the web server listens on.                     |
| `APP_VERSION`           | no       | unset                | App version string shown in UI footer / API headers.     |
| `DOMAIN`                | no       | `localhost:4000`     | Public host the app is reachable at.                     |
| `PROTOCOL`              | no       | `https`              | `http` or `https`.                                       |
| `ASSET_HOST`            | no       | unset                | CDN host for static assets, if any.                      |

## Database & cache

| Variable             | Required | Purpose                                |
| -------------------- | -------- | -------------------------------------- |
| `DB_HOST`            | yes      | Postgres host.                         |
| `DB_PORT`            | no       | Postgres port (`5432`).                |
| `DB_NAME`            | yes      | Database name.                         |
| `DB_USERNAME`        | yes      | DB user.                               |
| `DB_PASSWORD`        | yes      | DB password.                           |
| `REDIS_URL`          | yes      | Redis connection URL.                  |
| `REDIS_UI_URL`       | no       | UI Redis browser URL (dev).            |

## Encryption keys

> **warning** **Rotate carefully.** Generate with `bundle exec rails secret`. Rotate by re-encrypting stored values — there's no online rotation primitive yet.

| Variable                    | Purpose                                                       |
| --------------------------- | ------------------------------------------------------------- |
| `CREDENTIALS_SECRET_KEY`    | Encrypts user agent credentials at rest.                      |
| `CONFIG_ITEMS_SECRET_KEY`   | Encrypts Config Items (project/company secrets).              |
| `INTEGRATIONS_SECRET_KEY`   | Encrypts Git host integration tokens.                         |

## Temporal

| Variable                                  | Default            | Purpose                                                |
| ----------------------------------------- | ------------------ | ------------------------------------------------------ |
| `TEMPORAL_ENABLED`                        | `true`             | Toggle Temporal workflow execution.                    |
| `TEMPORAL_HOST` / `TEMPORAL_PORT`         | `temporal` / `7233`| Temporal server address.                               |
| `TEMPORAL_NAMESPACE`                      | `default`          | Temporal namespace.                                    |
| `TEMPORAL_TASK_QUEUE`                     | `aixle_ruby`       | Task queue name.                                       |
| `TEMPORAL_UI_URL`                         | unset              | Public URL for Temporal Web UI (linked from Admin).    |
| `TEMPORAL_WORKER_GRACEFUL_SHUTDOWN_PERIOD`| `30s`              | Worker drain time on shutdown.                         |

## Container runtime

| Variable                        | Default               | Purpose                                                  |
| ------------------------------- | --------------------- | -------------------------------------------------------- |
| `CONTAINER_RUNTIME`             | `docker`              | `docker` or `kubernetes`.                                |
| `DOCKER_NETWORK`                | host network          | Docker network agent containers join.                    |
| `AGENT_IMAGE_CLAUDE_CODE`       | `aixle/claude-code`   | Override image for the Claude Code runtime.              |
| `AGENT_IMAGE_CURSOR_CLI`        | `aixle/cursor-cli`    | Override image for Cursor CLI runtime.                   |
| `AGENT_IMAGE_CODEX`             | `aixle/codex`         | Override image for Codex runtime.                        |
| `AGENT_IMAGE_GEMINI_CLI`        | `aixle/gemini-cli`    | Override image for Gemini CLI runtime.                   |
| `AGENT_IMAGE_GROK`              | `aixle/grok`          | Override image for Grok CLI runtime.                     |
| `AGENT_MCP_STARTUP_TIMEOUT_MS`  | `90000`               | How long the platform waits for an agent's MCP handshake.|
| `MCP_SERVER_URL`                | computed              | Internal MCP server URL injected into agent containers.  |
| `CONTAINER_ASSET_HOST`          | computed              | Host the agent uses to fetch / upload assets.            |
| `MAX_FILE_SIZE`                 | env-dependent         | Max upload size in bytes. Test env defaults to 1 MB.    |

### Kubernetes runtime (when `CONTAINER_RUNTIME=kubernetes`)

| Variable                          | Default                                                       | Purpose                                                    |
| --------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------- |
| `KUBECONFIG`                      | in-cluster service account                                     | Path to a kubeconfig file when running outside the cluster. |
| `KUBERNETES_SERVICE_HOST`         | `kubernetes.default.svc`                                       | Kubernetes API host.                                       |
| `KUBERNETES_SERVICE_PORT`         | `443`                                                          | Kubernetes API port.                                       |
| `K8S_NAMESPACE`                   | `aixle`                                                        | Namespace agent pods are created in.                       |
| `K8S_SA_TOKEN_PATH`               | `/var/run/secrets/kubernetes.io/serviceaccount/token`          | Service account token path.                                |
| `K8S_SA_CA_PATH`                  | `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`         | Service account CA cert path.                              |
| `K8S_AGENTS_IMAGE_PULL_SECRETS`   | unset                                                          | Comma-separated image pull secrets.                        |
| `K8S_AGENTS_NODE_POOL`            | unset                                                          | Pin agent pods to a node group: `key=value[:Effect]`.      |
| `K8S_IMAGE_PULL_POLICY`           | `IfNotPresent`                                                 | Pod image pull policy.                                     |
| `K8S_READY_INTERVAL`              | a few seconds                                                  | Poll interval while waiting for a pod to become Ready.     |
| `K8S_READY_TIMEOUT`               | a few minutes                                                  | Max wait for pod ready before failing.                     |
| `K8S_RUNTIME_REQUESTS_CPU`        | unset                                                          | Pod CPU request.                                           |
| `K8S_RUNTIME_REQUESTS_MEMORY`     | unset                                                          | Pod memory request.                                        |
| `K8S_RUNTIME_LIMITS_CPU`          | unset                                                          | Pod CPU limit.                                             |
| `K8S_RUNTIME_LIMITS_MEMORY`       | unset                                                          | Pod memory limit.                                          |
| `K8S_SERVICE_PORTS`               | computed                                                       | Service ports the agent pod exposes.                       |
| `K8S_TRAEFIK_VERIFY_TLS`          | `true`                                                         | Verify Traefik TLS when routing into the cluster.          |
| `K8S_WORKSPACE_DIR`               | `/workspace`                                                   | Pod workspace directory.                                   |
| `K8S_EKS_VPC_CIDR`                | unset                                                          | EKS VPC CIDR (for security group calculations).            |

## Git host integration

| Variable                  | Purpose                                                 |
| ------------------------- | ------------------------------------------------------- |
| `GITHUB_APP_ID`           | GitHub App ID.                                          |
| `GITHUB_APP_PRIVATE_KEY`  | GitHub App private key (PEM, multi-line).               |
| `GITHUB_APP_SLUG`         | The App's slug.                                         |
| `GITHUB_WEBHOOK_SECRET`   | HMAC secret for `/webhooks/github` verification.        |
| `GITHUB_PUBLIC_READ_TOKEN`| Optional read-only token used only to list public repository trees while describing the skills catalog. Needs no scopes. Without it, api.github.com allows 60 requests/hour for the whole deployment and the catalog is described a couple of dozen publishers at a time; with it, 5,000/hour. |
| `GITLAB_ENDPOINT`         | GitLab API server URL (defaults to `https://gitlab.com/api/v4`). |

GitLab access uses a per-integration personal access token (stored
encrypted, not an env var). The GitLab webhook endpoint
(`/webhooks/gitlab`) is verified with a per-repository secret, also not
an env var.

## Auth

| Variable               | Purpose                                              |
| ---------------------- | ---------------------------------------------------- |
| `GOOGLE_CLIENT_ID`     | Google OAuth client ID.                              |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret.                          |
| `SUPER_ADMIN_EMAIL`    | First-boot bootstrap: this email becomes super admin.|
| `ADMIN_PASSWORD`       | First-boot bootstrap password for the admin user.    |

## Mail

| Variable                | Purpose                              |
| ----------------------- | ------------------------------------ |
| `MAILER_ADDRESS`        | SMTP server hostname.                |
| `MAILER_PORT`           | SMTP port.                           |
| `MAILER_USERNAME`       | SMTP username.                       |
| `MAILER_PASSWORD`       | SMTP password.                       |
| `MAILER_AUTHENTICATION` | SMTP auth mechanism (`plain`, etc.). |

## Storage (S3)

| Variable                | Purpose                                                |
| ----------------------- | ------------------------------------------------------ |
| `AWS_ACCESS_KEY_ID`     | S3-compatible access key.                              |
| `AWS_SECRET_ACCESS_KEY` | S3 secret.                                             |
| `AWS_DEFAULT_REGION`    | S3 region.                                             |
| `AWS_S3_BUCKET`         | Bucket name used for uploads and asset storage.        |

## Observability

| Variable                                | Purpose                                       |
| --------------------------------------- | --------------------------------------------- |
| `SENTRY_RAILS_DSN`                      | Sentry DSN for the Rails app.                 |
| `SENTRY_FRONTEND_DSN`                   | Sentry DSN for the React frontend.            |
| `SENTRY_TEMPORAL_DSN`                   | Sentry DSN for the Temporal worker.           |
| `OTEL_EXPORTER_OTLP_ENDPOINT`           | Default OpenTelemetry OTLP endpoint.          |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`      | Override for logs export.                     |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`   | Override for metrics export.                  |

## Author identity (for git commits made by agents)

| Variable       | Purpose                                                    |
| -------------- | ---------------------------------------------------------- |
| `AUTHOR_NAME`  | Default commit author name used when an agent commits.      |
| `AUTHOR_EMAIL` | Default commit author email.                                |

## Traefik (reverse proxy, optional)

| Variable                    | Purpose                                      |
| --------------------------- | -------------------------------------------- |
| `TRAEFIK_ENTRYPOINT`        | Traefik entrypoint name (e.g. `websecure`).  |
| `TRAEFIK_AUTH_MIDDLEWARE`   | Auth middleware name.                        |
| `TRAEFIK_CORS_ORIGINS`      | CORS origins.                                |
| `TRAEFIK_DASHBOARD_URL`     | Public Traefik dashboard URL.                |
| `TRAEFIK_HTTP_BASE`         | Base HTTP URL.                               |
| `TRAEFIK_WS_BASE`           | Base WebSocket URL.                          |
| `TRAEFIK_INTERNAL_URL`      | Internal Traefik URL (Docker network).       |

## Docs explorer

| Variable        | Purpose                                                 |
| --------------- | ------------------------------------------------------- |
| `DOCS_LOGIN`    | Basic-auth username for `/docs` (the OpenAPI explorer). |
| `DOCS_PASSWORD` | Basic-auth password for `/docs`.                        |

## Third-party APIs

No key is required. Skills are read from the public skills.sh endpoints: its
documented `/api/v1` surface authenticates with a Vercel OIDC token only, and
skills.sh issues no API keys to services hosted elsewhere.
