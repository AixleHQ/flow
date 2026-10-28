# OpenCode on self-hosted models — runtime plan

**Status:** proposed, 2026-10-28. Nothing here is built yet. The Phase 0 spike ran the same
day — OpenCode 1.19.5 in a container on `aixle/agent-base-core`, against a Splash (MLX) server
on another machine on the LAN — and §12 records what it measured.

This adds [OpenCode](https://opencode.ai) (`opencode-ai` on npm, MIT, source at
`anomalyco/opencode`) as the eighth agent runtime, `opencode`, for one purpose: running
agent sessions against **language models a company hosts itself** — on the same machine
as Flow or reachable over its network — with token cost recorded as **$0**.

It follows the runtime playbook in `docs/architecture/agent-runtime-registry.md` and
Appendix A of the Kiro CLI research report. What is new is not the adapter but the three
things a self-hosted model needs that no hosted runtime did: a company-owned model
endpoint, a way for agent containers to reach a private network, and a server-side probe
that is allowed to dial one.

## 1. Decisions

| # | Decision | Consequence |
| --- | --- | --- |
| D1 | OpenCode is offered for **self-hosted OpenAI-compatible endpoints only**. Hosted providers (Anthropic, OpenAI, Copilot, OpenCode Zen) are disabled in every generated config. | No login capture, no auth container, no vendor-terms gate. Claude subscription OAuth — which Anthropic's terms bar from third-party harnesses — is unreachable by construction, not by a check. |
| D2 | The endpoint belongs to the **company**, registered by a company admin, not typed by each user. | One key to rotate; a member who leaves holds nothing; a user "connects OpenCode" by choosing an endpoint. |
| D3 | Reaching a private network is an **operator** setting, empty by default. A company admin can only choose an endpoint inside what the operator allowed. | A hosted tenant cannot point Flow at Flow's own VPC. Agent pods' private-range block (§4) stays the default. |
| D4 | The credential is a **static key**: `{ expiry: :none, refresh: :none, rotation: :static }`. | `credential_lifecycle_contract_test.rb` passes unchanged and the pinned list of server-refreshed runtimes stays as it is. |
| D5 | Token cost is **0**, recorded only when usage was actually collected. | `cost_cents: 0` means "measured, free"; `null` keeps its documented meaning, "the runtime emitted no usage". |

**Out of scope for v1:** hosted providers through OpenCode; OAuth-based provider logins;
per-session keys minted by a gateway (Phase 2, §11); fully air-gapped installs (OpenCode has
no offline mode upstream — §12); notional pricing for internal chargeback.

## 2. Shape

```
operator ──► SELF_HOSTED_LLM_ALLOWED_CIDRS / _NAMESPACES   (empty = feature unreachable)
                 │                         │
                 ▼                         ▼
   SafeHttp (server probes)        agent-pod egress NetworkPolicy
                 │                         │
company admin ──► Integration(provider: llm_endpoint)
                    settings:    base_url, models[{id, context, output}]
                    credentials: api_key (encrypted)
                 │
user ──► AgentCredential(agent_type: opencode, config_data: { integration_id })
                 │
session container ─ ~/.config/opencode/opencode.json  (one custom provider, others disabled)
                    OPENCODE_LLM_API_KEY  (env, referenced as {env:…})
                    ──HTTP(S)_PROXY──► mitmproxy ──► self-hosted endpoint
```

Prompts and completions go from the session container to the company's endpoint. They do
not pass through Flow's application servers — the same property the Bedrock connection
documents in `docs/design/cloud-connection-security.md` §2.

## 3. The model server

Every server must require a key, including one on the same machine as Flow: session
containers run arbitrary agent code, and on a shared host other companies' containers can
reach the same host gateway.

| Server | Key | Notes |
| --- | --- | --- |
| vLLM | `--api-key` / `VLLM_API_KEY` | Tool calling needs `--enable-auto-tool-choice --tool-call-parser <parser for the model>`. Without it the endpoint answers chat but every agent tool call fails. |
| llama.cpp `llama-server` | `--api-key` | Tool calling needs `--jinja` and a model whose template supports tools. |
| Ollama | none of its own | Bind it to `127.0.0.1` and put a reverse proxy in front that checks `Authorization: Bearer` (Traefik, Caddy, nginx). Raise `num_ctx` to 16k–32k — OpenCode's own docs name a small context as the cause of failing tool calls. |
| Splash (MLX, macOS) | Bearer key | Verified in the spike (§12): tool calls with `tool_choice: "required"`, streamed usage only with `include_usage`, context window reported in `/v1/models`. |
| Several servers or teams | a gateway (LiteLLM or similar) | One virtual key per company, rate limits, its own usage log; the servers' own keys never leave the gateway host. The Phase 2 per-session keys build on this. |

- **Transport:** plain HTTP only on loopback or the Docker host bridge. TLS for anything
  that crosses a network.
- **Firewall:** the model port open to the agent nodes or pod CIDR only.
- **Models:** a model that cannot call tools cannot run an agent session. Context below
  ~32k tokens works for small tasks only; the endpoint records each model's context window
  so OpenCode compacts in time (§6).

## 4. Network reachability

### What blocks it today

- **Kubernetes.** Agent pods are default-deny. Their only internet egress,
  `runtime-allow-public-internet-egress`, excludes `runtime_blocked_ipv4_cidrs`
  (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, `169.254/16`) and `eks_vpc_cidr`
  (`config/settings.yml`, `kubernetes:`). Any private endpoint is unreachable.
- **Server-side calls.** `SafeHttp.vetted_address` refuses every private IP literal and
  every name resolving to one. Its `trusted_hosts:` escape resolves through internal DNS and
  **does not pin** the address, so it is the wrong tool for a URL a company admin typed.
- **Docker.** Agent containers join `docker_network` with no `ExtraHosts`, so on Linux
  `host.docker.internal` does not resolve.

### Operator settings

| Variable | Meaning |
| --- | --- |
| `SELF_HOSTED_LLM_ALLOWED_CIDRS` | Comma-separated `cidr[:port]` entries agent containers may reach and endpoint URLs may point at. Empty (the default) disables `llm_endpoint` integrations entirely. |
| `SELF_HOSTED_LLM_ALLOWED_NAMESPACES` | Kubernetes only: namespaces whose pods agent pods may reach, for an in-cluster model Service (`http://vllm.llm.svc:8000`). `ipBlock` does not match Service traffic reliably, so in-cluster endpoints need a `namespaceSelector` rule. |

Both get a row in `docs/reference/configuration.md` and a `Settings` entry under a new
`self_hosted_llm:` key. They are read whatever `Deployment.mode` is: on `saas` the operator
is us, and leaving them empty is the default that keeps tenants out of the VPC.

`169.254.0.0/16`, `fe80::/10` and loopback are refused even when an allowed CIDR covers
them — cloud metadata and the container's own loopback are never a model endpoint.

### Kubernetes

A new policy, built like the existing `runtime-allow-*` ones, allowing egress to the allowed
CIDRs/ports and namespaces. NetworkPolicies add up, so it opens these ranges without
touching the public-internet policy's exclusions.

The runtime **creates policies but never updates them** (`ensure_network_policy` does
`get`, then `create` on failure). A changed allowlist would otherwise never reach a project
namespace that already has the policy, so the policy's name carries a digest of its rule
set — `runtime-allow-self-hosted-llm-<digest>` — and `ensure_runtime_network_policies`
deletes `runtime-allow-self-hosted-llm-*` policies whose digest is not the current one.
With an empty allowlist no policy is created and stale ones are removed.

### Docker

- Same machine: add `"ExtraHosts" => ["host.docker.internal:host-gateway"]` to the agent
  session host config, so `http://host.docker.internal:<port>/v1` works on Linux as it does
  on Docker Desktop.
- Or run the model server on `docker_network` and use its service name.

The Docker runtime applies no egress filtering, so the allowlist there governs the server
side only. That is acceptable: Docker is the development runtime.

### Server side

Add an `allowed_cidrs:` option to `SafeHttp.http_for` / `vetted_address`: a private address
inside an allowed CIDR is accepted, **and is still the pinned address dialed**, so a
rebinding name cannot move the probe to a different private host. `UrlSafetyValidator` gets
the same option for validating the endpoint form. Neither changes for any other caller.

The web pod's route to the endpoint can differ from an agent pod's (different namespace,
different policy), so a passing server-side health check proves the endpoint works, not
that sessions can reach it. The endpoint page says so, and the first session failing to
connect is reported as a connection error naming the endpoint (§6, error detection).

## 5. Data model

No migration: `integrations` already has `provider` (string), `settings` (jsonb) and the
encrypted `credentials` column.

**`Integration(provider: "llm_endpoint")`**, company-level (`project_id` null in v1):

- `credentials`: `{ "api_key" => "…" }` — encrypted, write-only in the UI, registered with
  `Sessions::SecretRegistry` so it is redacted from pane output and logs.
- `settings`:
  - `base_url` — `https://…/v1`, validated against the operator allowlist on save;
  - `wire_api` — `chat_completions` (`@ai-sdk/openai-compatible`, the default) or
    `responses` (`@ai-sdk/openai`);
  - `models` — `[{ id, name, context, output }]`, filled from `GET /v1/models` (vLLM,
    llama.cpp and Ollama all serve it) and editable, because servers do not report context
    windows consistently;
  - `last_check` — the health check's result and time.
- `status`: `active` after a passing health check, `error` after a failing one.

Add `llm_endpoint` to `Integration`'s provider enum and `CONNECTABLE_PROVIDERS`. Several
endpoints per company are allowed (one per GPU box or team).

**Health check:** `GET /v1/models`, then one chat completion with a trivial tool and
`tool_choice: "required"`, capped at a few output tokens. It passes only if the response
contains a tool call. A plain "hello" passes on a server that will fail every agent session.

**`AgentCredential(agent_type: "opencode")`**: `config_data` is
`{ "integration_id" => … }`. The existing preflight still finds a row per (user, company).
The launch refuses, with a message naming the endpoint, when the integration is gone, not
`active`, or belongs to another company — a session can only use an endpoint of the company
it is billed to, as with Bedrock connections.

## 6. The adapter — `Agents::OpencodeAdapter`

The nearest precedents are `GeminiCliAdapter` (static key, no refresh) and `GrokAdapter`
(MITM usage, context file outside the repository).

| Hook | Behaviour |
| --- | --- |
| `home_dir` | `/home/opencode` |
| `config_files` | `~/.config/opencode/opencode.json`, below |
| `credential_lifecycle` | `{ expiry: :none, refresh: :none, rotation: :static, nominal_ttl: nil }.freeze` |
| `default_env_vars` | `OPENCODE_LLM_API_KEY` from the endpoint; `OPENCODE_DISABLE_AUTOUPDATE=1`; `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` so a `~/.claude/CLAUDE.md` never replaces our context |
| `conflicting_env_keys` | Every hosted provider key OpenCode reads (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, …) |
| `session_command` | `opencode --model aixle/<model id>` in the tmux pane |
| `context_file_path` | `~/.config/opencode/AGENTS.md` — the global rules file, so `/workspace` stays clean. A project `AGENTS.md` still applies alongside it: OpenCode treats project and global rules as separate categories |
| `mcp_config` / `mcp_merge_strategy` | entries under `mcp` in the same JSON: `{ type: "local", command: [cmd, *args], environment }` or `{ type: "remote", url, headers }` |
| `skills_install_path` / `skills_agent_name` | `~/.config/opencode/skills`, agent id `opencode` |
| `fetch_available_models` | the endpoint's `settings.models` — no network call at page render |
| `mitm_tracked_domains` | the endpoint's host (exact match, which works for an IP literal or an in-cluster name) |
| `collect_usage` | §7 |
| `auth_*` / `extract_credentials` | nothing to capture: there is no login |

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "share": "disabled",
  "enabled_providers": ["aixle"],
  "permission": { "*": "allow", "doom_loop": "allow", "external_directory": "allow" },
  "model": "aixle/qwen3-coder-30b",
  "small_model": "aixle/qwen3-coder-30b",
  "provider": {
    "aixle": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "GPU box 1",
      "options": {
        "baseURL": "http://10.20.0.15:8000/v1",
        "apiKey": "{env:OPENCODE_LLM_API_KEY}",
        "includeUsage": true
      },
      "models": {
        "qwen3-coder-30b": {
          "name": "Qwen3 Coder 30B",
          "limit": { "context": 65536, "output": 8192 },
          "cost": { "input": 0, "output": 0 }
        }
      }
    }
  },
  "mcp": {}
}
```

- **Permissions.** Most of OpenCode's permissions default to `allow`, but `doom_loop` and
  `external_directory` default to `ask`. Either one would leave an unattended workflow step
  waiting on a dialog nobody sees — the failure mode the Codex trust prompt caused
  (`docs/research/technical-codex-workspace-trust-prompt-2026-08-14.md`). Both are set
  explicitly.
- **`small_model`** points at the same endpoint. Otherwise OpenCode may route title
  generation to a hosted default.
- **`includeUsage`** asks the server for usage in the last streamed chunk
  (`stream_options.include_usage`). OpenCode 1.19.5 passes it through, and Splash sends no
  usage in a stream without it (§12); vLLM and llama.cpp are documented to behave the same.
  Without it §7 records no tokens.
- **Error detection.** Add `opencode` to `AuthErrorDetector`'s CLI pattern. A rejected key
  (401 from the endpoint) and a refused connection are reported as an endpoint problem the
  admin fixes, not a login the user renews. No `QuotaErrorDetector` provider is needed.

**BMAD:** BMAD lists an `opencode` tool id; map `opencode => "opencode"` in
`BmadMethodInjector` once `bmad-method@<pinned> install --list-tools` confirms it, and add
its install directory to `BMAD_HIDDEN_PATHS`.

## 7. Usage and cost

**Source: the session's MITM log, at cleanup** — the path `GrokAdapter` uses.

- The agent's traffic already goes through the in-container proxy: `start-mitm.sh` exports
  `HTTP_PROXY` and `HTTPS_PROXY`, and `NO_PROXY` covers only loopback, so plain-HTTP traffic
  to a LAN or cluster host is proxied too.
- `mitm_logger.py` matches a tracked domain exactly or by subdomain, so tracking the
  endpoint's host works for an IP literal.
- The response bodies are OpenAI-shaped: Chat Completions' `prompt_tokens` /
  `completion_tokens` (+ `prompt_tokens_details.cached_tokens` where the server reports
  it), or the Responses API's `input_tokens` / `output_tokens` for `wire_api: responses`.
  The Grok parser already reads both shapes from a streamed or truncated body. Extract it
  into a shared parser rather than copying it.
- `prompt_tokens` includes `prompt_tokens_details.cached_tokens`, and `completion_tokens`
  includes `completion_tokens_details.reasoning_tokens`: record uncached input as
  prompt − cached so cached tokens are not counted twice. Measured in §12, where these totals
  matched OpenCode's own export exactly.
- Every request is counted, including OpenCode's title-generation call to `small_model`,
  which its own export leaves out.
- Credential headers are already redacted by the logger; prompt bodies for the tracked host
  land in the session's MITM log as they do for every other runtime.

The alternative, `opencode export <session>` (per-message tokens and OpenCode's own cost),
is independent of the wire format, but it reads OpenCode's session store, now a database
(`OPENCODE_DB`), whose layout changes between releases — the kind of coupling the Kiro
adapter pays for. Use it in the spike to cross-check the MITM numbers, not as the source.

**Cost:** `cost_cents: 0` whenever at least one usage record was parsed; `null` when none
was. The `cost: 0` in the generated config makes OpenCode's own display agree.

What $0 does not cover, stated in the runtimes guide: worker-hour billing
(`company_usage_hours`) still applies to the session, and the hardware's own cost is not
counted anywhere.

## 8. The image — `docker/opencode/Dockerfile`

- `FROM` `aixle/agent-base-core`; agent user `opencode` created with
  `useradd -m -d /home/opencode -G ${AGENT_BROWSERS_GROUP}`.
- `ARG CLI_VERSION` with no default; `npm install -g opencode-ai@${CLI_VERSION}` in one
  layer with the cache cleaned. The `postinstall` copies the selected platform binary
  (`opencode-linux-x64-baseline` on this base) to `bin/opencode.exe` and leaves the 205 MB
  original in `node_modules/`; delete it in the same layer.
- The AI SDK providers are bundled in the binary — nothing is fetched for them. What
  OpenCode does install at runtime is `@opencode-ai/plugin@<cli version>`, into
  `~/.config/opencode/node_modules`, in the background (§12). Pre-install it there at build
  time, as the agent user, so sessions make no npm requests. The adapter writes its files
  into the same directory and must not clear it.
- `models.opencode.ai/api.json` is still fetched at startup. It does not block (startup
  completes without network), so v1 leaves it alone; an air-gapped install would ship the
  catalogue file instead.
- No recursive `chown` after the install (`docs/research/technical-agent-image-size-audit-2026-08-04.md`).
- Build-time boundary check, as `docker/grok/Dockerfile` does for its rules path: write a
  marker `AGENTS.md` and a one-model `opencode.json` with an unreachable `baseURL`, then
  fail the build unless OpenCode reports that rules file and that provider/model. A
  release that moves the global config or rules path, or switches the config schema (the
  v2 docs nest MCP servers under `mcp.servers`), breaks the build instead of silently
  dropping every session's instructions.
- Registry entry: `"id": "opencode"`, `"image": "opencode"`, `"cli_version": "1.19.5"`
  (current at writing — re-check at implementation),
  `"cli_latest": { "npm": "opencode-ai" }`,
  `"cli_releases": { "github": "anomalyco/opencode", "tag_prefix": "v" }`.

## 9. Touch points

The registry removes most hand-kept lists; these are what still name a runtime, found by
listing every file naming `kiro_cli`.

**Runtime**

- `config/agent_runtimes.json` — the entry (§8)
- `docker/opencode/Dockerfile`; `.github/dependabot.yml` Docker directories (no test checks this one)
- `config/settings.yml` — `agents.images.opencode` (`AGENT_IMAGE_OPENCODE`) and `self_hosted_llm:`
- `app/services/agents/opencode_adapter.rb`
- `app/services/agent_credentials_service.rb` — `ADAPTERS`
- `app/services/container_strategies/agent_base_strategy.rb` — `AUTH_COMMANDS` (a placeholder: there is no login) and `SESSION_COMMANDS`
- `app/services/bmad_method_injector.rb`; `app/services/auth_error_detector.rb`
- `app/dashboards/agent_credential_dashboard.rb` — collection scope

**Endpoint and network**

- `app/models/integration.rb` — `llm_endpoint` provider; its controller, policy and admin form under the company's integrations
- `app/services/safe_http.rb`, `app/models/concerns/url_safety_validator.rb` — `allowed_cidrs:`
- `app/services/container_runtime/kubernetes_runtime.rb` — the digest-named egress policy and stale-policy removal
- the agent session host config — `ExtraHosts` for `host-gateway`
- a health-check service, and the endpoint picker in Profile's "Connect OpenCode"

**Frontend**

- `app/frontend/shared/ui/types.ts` — `AgentType`, first; `tsc` then names the maps below
- `shared/ui/agentRuntimes.ts` (`MANTINE_COLORS`), `shared/theme/vendorColors.ts`,
  `shared/analytics/chartHelpers.tsx` (neutral chip — no vendor artwork ships, as with Grok and Kiro),
  `pages/Onboarding/OnboardingPage.tsx` (icon)
- regenerated `app/frontend/types/generated/*`

## 10. Tests, docs, changelog

**Tests** (`docs/testing.md` rules: no stubbing the class under test, no `any_instance`, the
container through `ContainerRuntime::FakeRuntime`):

- `test/services/agents/opencode_adapter_test.rb` — generated config (providers disabled,
  permissions, `{env:}` key, model limits and zero cost), conflicting env keys, MCP
  rendering, usage parsing of Chat Completions and Responses bodies, `cost_cents` 0 vs `null`
- `test/support/fakes/fake_runtime.rb` — the `opencode` version output and fixtures
- `test/factories/agent_credentials.rb` trait, plus an `llm_endpoint` integration factory
- `test/integration/container_workflow_integration_test.rb` — `AGENT_TYPES` and the credential-shape branch
- `agent_credentials_service_test`, `agent_session_strategy_test`, the BMAD tests
- `SafeHttp` / `UrlSafetyValidator`: allowed CIDR accepted and pinned; outside it refused;
  metadata and loopback refused even inside an allowed CIDR; a name rebinding to another
  private address refused
- Kubernetes runtime: no policy with an empty allowlist; digest-named policy created; a
  stale digest removed
- endpoint health check: passes only on a tool call; launch refused for an inactive or
  other-company endpoint
- frontend tests that count runtimes (the Grok PR had to fix these)

`credential_lifecycle_contract_test.rb` needs no edit — that it passes unchanged is the
check that D4 holds.

**Docs**, in the same change:

- `docs/user-guide/runtimes.md` and `app/frontend/pages/Docs/data/pages/runtimes.md` —
  `documentation_drift_test.rb` fails until both name `` `opencode` ``; include the usage
  row and the "$0 is tokens only" note
- a page in `docs/user-guide/` for the self-hosted model endpoint (operator settings,
  server-side key setup from §3, the tool-calling requirement), linked from
  `docs/user-guide/integrations.md` and the portal copy
- `docs/reference/configuration.md` — the three new variables
- "seven runtimes" → eight: `docs/architecture/agent-runtime-registry.md`,
  `docs/product/changelog-product-areas.md`, `docs/project/context.md`,
  `docs/design/agent-credential-lifecycle.md`, `docs/user-guide/agents.md`,
  `docs/reference/cli.md`, `references/aixle-system-reference.md`, the portal's
  `agents.md`, `cli-ref.md` and `searchIndex.ts`
- correct `agent-runtime-registry.md`'s "Nothing else enumerates runtimes" — the dashboard,
  `AuthErrorDetector`, `FakeRuntime` and four frontend maps still do — and step 3 of
  `context.md`'s runtime checklist, which names adapter methods that no longer match
  `BaseAdapter`
- a security note in the style of `cloud-connection-security.md`: where prompts go, what is
  stored where, what the key grants, what the operator allowlist exposes
- `docs/index.md` for every new page

**Changelog**, under `### Added`:

- `- **Integrations**: Connect a self-hosted, OpenAI-compatible model server …`
- `- **Profile**: Connect OpenCode to one of your company's model endpoints …`
- an operator line for `SELF_HOSTED_LLM_ALLOWED_CIDRS` / `_NAMESPACES`

**Process:** branch from `develop`; Conventional Commits (`feat(agents): add OpenCode for
self-hosted models`, with the network and `SafeHttp` changes as their own `feat`
commits); `docker compose exec -T web make check_all` green before pushing.

## 11. Phases

**Phase 0 — spike. Done 2026-10-28 against Splash (§12).** A TUI session in a tmux pane
and an `opencode run` both completed tool-using tasks and an MCP call, and the MITM log
reconciled with `opencode export`. vLLM, llama.cpp and Ollama still need the same two
checks (streamed usage, forced tool call) before they are documented as supported.

**Phase 1 — the runtime.** Everything in §§4–10, company-level endpoints, interactive and
workflow-step sessions.

**Phase 2 — hardening, on demand.**

- Per-session keys: a gateway (LiteLLM) key minted at session start with a TTL and a
  budget, deleted at cleanup, so a key read out of one container is useless after it. The
  admin stores the gateway's admin key instead of an inference key.
- Project-scoped endpoints (`project_id` set): a project restricted to one model server.
- Notional per-token pricing for chargeback, set per endpoint model, defaulting to 0.
- Hosted providers through OpenCode, if wanted, as a separate decision with its own terms
  review.

## 12. Phase 0 spike — results

Run 2026-10-28: OpenCode 1.19.5 in a spike image on `aixle/agent-base-core` (Docker
runtime), the in-container MITM proxy started as sessions start it, against
`mlx-community/Qwen3.8-27B-4bit` served by Splash (MLX) on a Mac at `192.168.1.11:8000`
with a Bearer key.

| Item | Result |
| --- | --- |
| Config schema at 1.19.5 | The §6 `opencode.json` loads unchanged (`opencode debug config`): v1 `mcp.<name>` with `type`/`command[]`/`enabled`. Unknown keys are a hard `ConfigInvalidError` at startup, so a bad generated config fails loudly. |
| Hosted providers | `enabled_providers: ["aixle"]` leaves only the endpoint's model in `opencode models` and the TUI. A model id containing `/` (`aixle/mlx-community/…`) works. |
| Rules file | `~/.config/opencode/AGENTS.md` is in the system prompt of every agent request (seen in the MITM log), not of the title-generation request. A 27B model followed a rule in it in 4 of 5 runs — loading is reliable, adherence is the model's. |
| Skills | `~/.config/opencode/skills/<name>/SKILL.md` is discovered (`opencode debug skill`). |
| Local MCP | A stdio server's tool is exposed as `<server>_<tool>` and called successfully. |
| Remote MCP | **Not tested** — check against `aixle-tools` in Phase 1. |
| Permissions | TUI and `opencode run` wrote outside `/workspace` and ran shell commands with no prompt: the pre-answered `external_directory` and `doom_loop` work. |
| TUI first run | A fresh home starts straight at the prompt: no onboarding, no dialog. Sidebar shows `$0.00 spent` and context use against `limit.context`. |
| Proxy | OpenCode (Bun) honours `HTTP_PROXY`: plain-HTTP requests to the LAN IP appear in the MITM log, `Authorization` redacted. Requests carry `x-opencode-session-id`. |
| `includeUsage` | OpenCode sends `stream_options.include_usage: true`. Splash returns usage in the final chunk with it and **none without it** — the option is required. |
| Usage accounting | MITM per-request usage reconciles exactly with `opencode export` once two things are allowed for: `prompt_tokens` **includes** `cached_tokens` (uncached = prompt − cached), `completion_tokens` includes reasoning tokens, and the export omits the title-generation call that the MITM log counts. The MITM log is the more complete source. |
| Cost | `cost: 0` in the model config gives `cost: 0` per message in the export and `$0.00` in the TUI. |
| Outbound hosts | Only three: the endpoint, `models.opencode.ai/api.json` (model catalogue; with `--network none` startup still completes in ~2 s), and `registry.npmjs.org`. |
| Runtime npm install | OpenCode installs `@opencode-ai/plugin@<cli version>` into `~/.config/opencode/node_modules` in the **background** (~17–72 registry requests). It does not block the session. `OPENCODE_DISABLE_DEFAULT_PLUGINS=1` does not stop it reliably. With the package already present there are **zero** npm requests — so the image pre-installs it (§8). |
| Health check | `tool_choice: "required"` with one trivial tool returns a proper `tool_calls` response from Splash. |
| Model list | Splash's `/v1/models` reports `context_length` / `max_model_len`, so the endpoint form can prefill context windows. |
| Image | `postinstall` picks the `linux-x64-baseline` binary, copies it to `bin/opencode.exe`, and keeps the 205 MB original in `node_modules/opencode-linux-x64-baseline`; the final image deletes the copy. Spike image: 2.23 GB. |

**Still open:**

- remote MCP (`aixle-tools`) — Phase 1;
- vLLM, llama.cpp and Ollama: the same `include_usage` and tool-call checks, on hardware that can run them;
- BMAD `opencode` tool id — `bmad-method@<pinned> install --list-tools`;
- skills.sh `-a opencode` install target, in the real image;
- Kubernetes: the egress policy against a private endpoint, on a cluster.

## Sources

- OpenCode docs: [CLI](https://opencode.ai/docs/cli), [config](https://opencode.ai/docs/config),
  [providers](https://opencode.ai/docs/providers), [rules](https://opencode.ai/docs/rules),
  [skills](https://opencode.ai/docs/skills), [permissions](https://opencode.ai/docs/permissions),
  [MCP servers](https://opencode.ai/docs/en/mcp-servers) — fetched 2026-10-27/28
- [`opencode-ai` on npm](https://registry.npmjs.org/opencode-ai/latest) — 1.19.5, MIT, `postinstall` binary selection
- Offline behaviour: [anomalyco/opencode#18492](https://github.com/anomalyco/opencode/issues/18492),
  [particula.tech write-up](https://particula.tech/blog/opencode-offline-mode-air-gapped) — secondary, to be confirmed in the spike
- Anthropic's third-party-harness terms (why D1 excludes hosted providers):
  [Gigazine, 2026-02-20](https://gigazine.net/gsc_news/en/20260220-anthropic-third-party-block)
- BMAD tool ids: [docs.bmad-method.org install guide](https://docs.bmad-method.org/start/install-bmad/);
  skills CLI: [vercel-labs/skills README](https://cdn.jsdelivr.net/gh/vercel-labs/skills@main/README.md)
- Repository: `config/agent_runtimes.json`, `app/services/agents/{base,gemini_cli,grok}_adapter.rb`,
  `app/services/safe_http.rb`, `app/models/concerns/url_safety_validator.rb`,
  `app/services/container_runtime/kubernetes_runtime.rb`, `app/models/integration.rb`,
  `docker/base/logger/{start-mitm.sh,mitm_logger.py}`,
  `test/services/agents/credential_lifecycle_contract_test.rb`
