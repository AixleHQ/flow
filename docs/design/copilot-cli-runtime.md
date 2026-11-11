# GitHub Copilot CLI runtime — technical design

**Status:** Phase 1 built and verified live, 2026-11-10, on Copilot CLI
**1.0.108** with a Copilot Business seat: device-code login through the profile,
interactive and automatic sessions, MCP, model catalogue, reasoning effort and
per-session cost. §0.1 records what the spike measured and where the build
departs from the proposal below; the proposal is kept as written, so read §0.1
first. Phases 2 and 3 and Microsoft Entra sign-in are not built.

**Runtime id:** `copilot_cli`, the eighth built-in runtime, after
`claude_code`, `cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`
and `kiro_cli`.

## 0. Summary

**What.** Run GitHub's official Copilot CLI (npm `@github/copilot`, binary
`copilot`) as an agent runtime. Each user connects their own GitHub account
that has Copilot. Sessions, workflow steps, MCP tools, skills, cost tracking
and the live terminal behave as they do for the seven existing runtimes.

**Why.** A team that already pays for Copilot Business or Enterprise can run
Aixle workflows on seats it owns, with no second AI vendor contract. One
Copilot plan gives access to several model families (Anthropic, OpenAI, xAI
and others, depending on the plan). GitHub is also the only vendor among ours
that documents a SaaS-on-behalf-of-the-user path (§8). The org-billed token
path (Phase 3) fits the GitHub App that Aixle already installs into customer
organisations.

**How hard.** Medium. That is easier than Kiro and about the same as Grok.
Several things that made earlier runtimes expensive are absent here:

- The credential is a plain GitHub token string. There is no SQLite database
  and no encrypted blob.
- Login tokens (`gho_`) have no server-side refresh to reverse-engineer.
- The CLI documents its headless flags, folder trust, a config-home override
  and an auto-update switch.
- It exports OpenTelemetry with a **per-session AI-credit figure** on the root
  span.

The one piece of platform work that no other runtime needed is accepting
**OTLP traces**. Today only metrics and logs are ingested. §6.8 covers it.

**Estimate.**

- Phase 1 (device-flow login + PAT, TUI sessions, OTLP cost): **6–8
  engineer-days**, plus the 1-day spike.
- Phase 2 (our own GitHub App issues the user token): 2–3 days.
- Phase 3 (org-billed installation tokens): 3–5 days, plus a GitHub App
  permission rollout to every installation.

§11 breaks these down.

**What is needed to start.** A GitHub Copilot seat for development and the
spike. The recommendation in §12.3 is one **Copilot Business seat ($19/month,
1,900 AI credits)** in a company-owned test organisation. It exercises the
organisation policies that Business and Enterprise customers will hit. A
personal Copilot Pro+ plan is the fallback.

## 0.1 As built and measured (2026-11-10)

Everything below was run in the `aixle/copilot-cli` image or through the app
against a real Copilot Business seat, unless it says otherwise.

| # | Question | Result |
| --- | --- | --- |
| S1 | Where `copilot login --device-code` stores the token with no keychain | `settings.json` `storeTokenPlaintext: true` answers the plaintext question up front (the key exists; it is in `copilot help config`). The token lands in `config.json` under `authTokens["https://github.com:<login>"]` (and a second key ending `:github`, same token), with `loggedInUsers` / `lastLoggedInUser`. `config.json` starts with `//` comment lines, so it is not plain JSON. While the code is on screen the file has no `authTokens`; the watcher waits on `__contains__:"authTokens"`. |
| S2 | What the CLI prints on a dead or wrong token | TUI and `-p`: `Authentication token found but could not be validated.` A classic PAT: `Classic Personal Access Tokens (ghp_) are not supported by Copilot.` Both are in `AuthErrorDetector`. Credit and rate limits were not hit; the `QuotaErrorDetector` patterns are the CLI's own strings, read from its bundle. |
| S3 | Token portability and rotation | The `gho_` token works in a fresh container through `COPILOT_GITHUB_TOKEN` alone. Nothing rotates during a session. |
| S4 | MCP over plain HTTP on `web:4002` | No loopback rule. The server was dropped for another reason: the CLI speaks the 2026-07-28 protocol (`server/discover`, `subscriptions/listen`), and our per-request stateless MCP server answered `subscriptions/listen` with a stream that ended at once while advertising `listChanged`. The CLI's Rust client treats that as a dead transport (`sse response ended before an event ID was received; cannot resume`) and lists no tools. Fixed for both MCP endpoints with `serve_subscriptions_listen: false` (`Tools::MCPRequestHandler`, `Tools::PersonalMCPRequestHandler`). An automatic session then called `finish_session` on its own. |
| S5 | TUI dialogs with `-i`, `--allow-all`, `--no-ask-user` | Folder trust is asked for any directory missing from `trustedFolders`, `--allow-all` notwithstanding; with `/workspace` in `config.json` nothing is asked. A model rate limit offers "Switch to …?" unless `continueOnAutoMode: true` (set). Both have `InteractivePromptDetector` signatures. `--autopilot` was not needed. |
| S6 | Model catalogue and effort | No CLI command lists models, and `--model bogus` names none. The ACP server does: `session/new` returns the catalogue, `session/set_config_option` returns each model's `reasoning_effort` levels, with no prompt sent. `docker/copilot-cli/aixle-copilot-models.mjs` reads it at auth and session cleanup into the credential's metadata (22–23 models on the seat; default `claude-sonnet-5.5`). Effort flag: `--reasoning-effort`. The registry rules come from this read. |
| S7 | OTLP | `OTEL_RESOURCE_ATTRIBUTES` is honoured, so batches carry `terminal_session_token` and the session key. Traces and metrics only, `http/json`. Each model call is a `chat` span with tokens and `github.copilot.nano_aiu`; the turn's `invoke_agent` span repeats the total. The adapter counts `chat` spans only. `otlp-ingest` and `UsageStatisticsService` now take traces. |
| S8 | AIU vs credit | `--usage-output-file` and the CLI's own exit summary print `totalNanoAiu` 2 120 500 000 as "AI Credits 2.12": one AIU is one credit. Not compared against GitHub's billing page. |
| S9 | Context file | `copilot instruction list` reports `$COPILOT_HOME/copilot-instructions.md`; the image build fails if it stops. |
| S10 | Phase 2 `ghu_` | Not tested. |

**Where the build departs from the proposal**

- **Login is `copilot login --device-code` only (decided 2026-11-10).** The
  fine-grained PAT route (Phase 1B) and the *.ghe.com host are not offered in
  the auth terminal. The adapter still reads a PAT or a `proxima` (GHE.com)
  login correctly if `config.json` ever holds one; a token field in the profile
  is the route if PATs are wanted later.
- **Cost from `chat` spans, not the root span (D6).** Every billed call has its
  own span with its own model, so a session that switches model is split
  correctly, and the cached-token breakdown is only on `chat` spans.
- **The image unpacks the CLI at build time.** The native package expands ~250 MB
  of JavaScript into `~/.cache/copilot` on first run; doing it per container
  would write that into every session's layer.
- **The CLI runs as root with `HOME=/home/copilot`**, like the Grok and Kiro
  images (no `USER` in the Dockerfile).
- **Model-cache invalidation.** A picker opened before the catalogue was read
  cached the one-entry fallback for an hour; `persist_credential_metadata` now
  clears the model cache whenever it stores new metadata (all runtimes).
- **Turn ends are reminded, as for Kiro.** `TurnEndDetector` knows Copilot's idle
  screen: the `← open sidebar · Interactive` hint (`Interactive` and the model on
  a narrow pane) four lines under `Session: … AIC used`; while working the hint
  reads `● Working`, and with a draft it lists `@ files/sessions`. Measured at
  30x20 to 220x50 and in the platform's web terminal, whose prompt box is drawn
  differently. The reminder itself only submits with a pause before its `Enter`:
  Copilot takes a reminder-length burst of text for a paste and drops an `Enter`
  right behind it, so `Sessions::PaneInput` now waits 0.2 s (all runtimes). Live
  check: a workflow step whose agent ended its turn without `finish_session` was
  reminded once and finished. An idle Copilot TUI writes nothing to the pane (0
  bytes in 30 s), so the no-output watchdog works on its log as for other runtimes.

- **Found on staging (2026-11-11).** Three things the local stack did not show:
  the CLI defers MCP tools behind a tool search once a project has enough of them,
  and a session that found `aixle-tools-finish_session` that way still called
  `finish_session` and never finished — `toolSearch` and `dynamicRetrieval.mcp`
  are now off; the catalogue listed `auto` twice, which crashed every page with a
  model picker (Mantine refuses repeated values) — models are now de-duplicated
  for every runtime; and the hosted deployment builds agent images into its own
  registry, which needed a `copilot-cli` repository there. After those, an
  automatic staging session wrote its file, called `finish_session` on its own
  and was priced from OTLP traces (4¢, 43k tokens, Claude Haiku 4.5).

**Measured cost.** A one-file task with `finish_session`: 2.3–7.3 AI credits
($0.02–$0.07) on Claude Haiku 4.5 or Sonnet 5.5, 3.5 credits on GPT-5.3-Codex
at low effort. Most of it is the ~17k-token system prompt written to the cache
on the first call.

### Microsoft Entra sign-in (not built)

`copilot` on macOS offers a third account at `/login`, "Your organization
(Microsoft Entra)": a Copilot sign-in with a Microsoft work account rather than a
GitHub one (the CLI's account kinds `entra`, `entraEmu`, and `loki` for
Microsoft 365). It is not offered in the container, and nothing on our side
turns it on:

- The decision is in the CLI's native runtime (`entra_auth_is_enabled`, plus a
  platform check: "Selected Entra account is unsupported on this platform"). It
  stays hidden on Linux with `DISPLAY`/`BROWSER` set, signed in or not, and with
  `--experimental`. `copilot_cli_entra_access_disabled` is GitHub's server-side
  kill switch, not an enabler.
- The sign-in itself runs through an OS broker (OneAuth, on macOS and Windows)
  or a browser whose redirect lands on the CLI's `127.0.0.1` port — on the
  container's loopback, which the user's browser cannot reach.
- The only override in the binary is `COPILOT_DEBUG_ENTRA_BROKER_URL`, a debug
  hook for an external broker. Building on it would tie sessions to an
  undocumented interface that changes with ~3 releases a week.

What supporting it would take: the CLI offering Entra on Linux (ideally by
device code, which Entra supports — worth an issue on github/copilot-cli); a
relay that takes the browser's redirect URL from the user and replays it inside
the auth container; capturing the Entra token cache and its refresh (1-hour
access tokens); and an Entra-backed Copilot account to test against. A GitHub
account whose organisation signs in through Entra SAML SSO or Enterprise
Managed Users on github.com already works with the device-code login: the
Entra step happens in the user's browser.

## 1. Background: how a runtime plugs in today

A runtime is a containerised vendor CLI, driven through tmux, with a
captured login. Adding one touches these places, per
`docs/architecture/agent-runtime-registry.md` ("Adding a runtime"):

| Concern | Where | What Copilot needs |
| --- | --- | --- |
| Identity, image, pin, canary | `config/agent_runtimes.json` | One entry (§6.1) |
| Image | `docker/copilot-cli/Dockerfile` on `aixle/agent-base-core` (Node 26) | npm install of the pinned CLI (§6.1) |
| Login and launch commands | `ContainerStrategies::AgentBaseStrategy::AUTH_COMMANDS` / `SESSION_COMMANDS` | `copilot login --device-code` / `copilot --allow-all …` |
| Behaviour | `Agents::CopilotCliAdapter < Agents::BaseAdapter` | Credentials, config files, MCP, context, skills, env, usage (§6.2–6.9) |
| Usage ingest | `docker/otlp-ingest`, `UsageStatisticsService`, `#ingest_usage` | **New:** a `/v1/traces` path end to end (§6.8) |
| Failure signalling | `QuotaErrorDetector`, `InteractivePromptDetector` | Copilot patterns (§6.9) |
| BMAD | `BmadMethodInjector::AGENT_TYPE_TO_BMAD_TOOL` | A platform mapping (§6.5) |
| Frontend | `AgentType` in `app/frontend/shared/ui/types.ts`, brand colour, logo | `tsc` lists the rest |
| Settings and docs | `AGENT_IMAGE_COPILOT_CLI`, `docs/reference/configuration.md`, user guide and docs portal pages | §6.11 |

The playbook in Appendix A of
`docs/planning-artifacts/research/technical-kiro-cli-as-a-platform-agent-runtime-research-2026-08-28.md`
still applies. Its four qualifying questions are answered in §4.

## 2. Scope

**In scope (Phase 1)**

- Interactive and automatic sessions in the TUI, and workflow steps.
- Login by device code, and by a pasted fine-grained PAT.
- The `aixle-tools` MCP server, plus the project's MCP servers.
- Session context, skills and BMAD.
- Model pin and reasoning effort.
- Per-session cost in AI credits, quota-error detection, and blocking-dialog
  detection.

**Later phases**

- Phase 2: a user token minted by Aixle's own GitHub App (`ghu_`).
- Phase 3: an organisation-billed installation token (`ghs_`), with no
  per-user Copilot login.

**Non-goals**

- Proxying or calling the Copilot model API directly (§7.3).
- BYOK provider mode as a product feature. It is used only for test fixtures
  (§10).
- The Copilot cloud agent and Agent HQ. They work in the opposite direction:
  GitHub hosts the agent.
- Copilot code completions in an IDE.

## 3. Product facts (CLI 1.0.108)

Confidence: **V** means verified in GitHub's documentation on 2026-11-10.
**R** means reported by release notes, an issue or a third party. **M** means
it must be measured in the spike, because a doc statement was missing or has
proven wrong for other runtimes before.

| Area | Fact | Conf. |
| --- | --- | --- |
| Package | `@github/copilot` on npm (Node 22 or later). The install script `gh.io/copilot-install` and standalone `copilot-linux-{x64,arm64}` tarballs with `SHA256SUMS.txt` are also published. | V / R |
| Cadence | About three stable releases a week (19 between 2026-09-28 and 2026-11-09), plus prereleases | R |
| Self-update | On by default. `--no-auto-update` or `COPILOT_AUTO_UPDATE=false` turns it off ("the CLI and first-party plugins") | V |
| Config home | `~/.copilot/`, moved by `COPILOT_HOME`. `--config-dir` is deprecated. | V |
| Auth precedence | `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN` > OAuth token from the system keychain > `gh auth token` | V |
| Token types | Accepted: `gho_` (OAuth login), `github_pat_` (fine-grained PAT, owned by a personal account, with the "Copilot Requests" account permission), `ghu_` (GitHub App user-to-server). Classic `ghp_` is **not supported**. | V |
| No keychain | The CLI asks whether to store the token in plaintext in `~/.copilot/config.json`. Our images have no libsecret, so this is the path we hit. A settings key to pre-answer it is reported (`storeTokenPlaintext`) but is not in the docs. | V / R |
| Device login | `copilot login`. Device code is the default in SSH and containers, and `--device-code` forces it. The CLI prints `https://github.com/login/device` and an 8-character code. | V |
| Token lifetime | "Depends on how the token was created". Refresh is not mentioned. GitHub OAuth-app tokens (`gho_`) normally do not expire, but are revoked after a year unused. | V / R |
| Folder trust | Asked at session start, with the choices "this session" or "this and future sessions". Pre-trusted through the `trustedFolders` array in `config.json`. `--trust-folder` covers one run and is not saved. | V |
| Headless | `-p PROMPT` runs once and exits. `-i PROMPT` / `--interactive=PROMPT` starts the TUI and runs the prompt. `--allow-all` (alias `--yolo`, env `COPILOT_ALLOW_ALL`) covers tools, paths and URLs. `--no-ask-user` removes the `ask_user` tool. `--output-format json` gives JSONL. | V |
| Model | `--model=MODEL` or `COPILOT_MODEL`. `auto` lets Copilot choose. Free and Student plans get `auto` only. | V |
| Reasoning effort | `--effort=LEVEL` / `--reasoning-effort=LEVEL`, with levels `low`, `medium`, `high`, `xhigh`, `max`. Which levels each model honours is not documented. | V / M |
| Credit cap | `--max-ai-credits=N`: a soft maximum of AI credits for each response | V |
| MCP | `~/.copilot/mcp-config.json` `{"mcpServers": {…}}` with `type` `local`, `http` or `sse`. `--additional-mcp-config` applies to one run. Built-in servers (`github-mcp-server`, `WorkIQ`, `browser-use`) are disabled by `--disable-builtin-mcps`. | V |
| MCP over plain HTTP, non-loopback | No restriction is documented. Kiro had one in its binary that was not in its docs. | M |
| Org MCP policy | An org MCP allowlist or registry can filter servers. A failed registry fetch has been reported to silently drop every non-default server (github/copilot-cli#4378). | R |
| Env redaction | `--secret-env-vars NAME` redacts a variable from shell and MCP server environments. Defaults that cover `GITHUB_TOKEN` / `COPILOT_GITHUB_TOKEN` are reported. | V / R |
| Instructions | Reads `AGENTS.md` and `CLAUDE.md` (and `.claude/CLAUDE.md`) from the standard locations, plus `$COPILOT_HOME/copilot-instructions.md` at user level. `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` adds directories. | V |
| Skills | Project `.github/skills`, `.claude/skills`, `.agents/skills`. Personal `~/.copilot/skills`, `~/.agents/skills`. | R |
| OpenTelemetry | Traces and metrics only, no log records. Enabled by `COPILOT_OTEL_ENABLED=true` or by setting `OTEL_EXPORTER_OTLP_ENDPOINT`. Exporter type is `otlp-http` or `file` (`COPILOT_OTEL_FILE_EXPORTER_PATH`, JSON lines). | V |
| Trace shape | An `invoke_agent` root span with `chat` and `execute_tool` children. `github.copilot.nano_aiu` = "AI units consumed, in nano AI units (1 AIU = 1,000,000,000 nano AIU)". `github.copilot.cost` is a model multiplier, not money. Token usage sits on the `chat` and `invoke_agent` spans. | V |
| Metrics | `gen_ai.client.token.usage`, `gen_ai.invoke_agent.duration`, `github.copilot.agent.turn.count`, `github.copilot.tool.call.{count,duration}` | V |
| Resource attributes | Whether the exporter honours `OTEL_RESOURCE_ATTRIBUTES`, which carries our `terminal_session_token` and session key. Grok's exporter ignores it. | M |
| Billing | Usage-based since 2026-06-01. AI credits replaced premium requests and are priced per input, output and cached token at each model's API rate. There is no fallback model once credits run out. | V |
| Plans | Every plan includes the CLI. Free and Student: an unstated allowance, `auto` only. Pro $10: 1,500 credits. Pro+ $39: 7,000. Max $100: 20,000. Business $19 per seat: 1,900. Enterprise $39 per seat: 3,900. The Business and Enterprise prices imply 1 credit = $0.01. | V |
| AIU vs credit | Whether 1 AIU on the span equals 1 billed AI credit | M |
| Org path | Since 2026-10-27 (public preview), a GitHub App with the **organisation** permission "Copilot Requests" can mint installation tokens (`ghs_`) whose usage is billed to the organisation. This is documented for the SDK. | R |
| SDK | The Copilot SDK (GA 2026-06) drives the same CLI runtime over JSON-RPC and supports a per-session `gitHubToken` for multi-user servers | R |

## 4. Qualification

These are the four questions from the Kiro playbook. A "no" to (a) would stop
the work.

| Question | Answer |
| --- | --- |
| (a) Do the terms allow a hosted platform to run the CLI on a user's behalf? | **Yes, with conditions**: no explicit prohibition, and GitHub documents the SaaS-on-behalf-of-user pattern. Details and conditions are in §8. |
| (b) Is there a non-interactive mode? | **Yes.** `-p`, `-i`, `--allow-all`, `--no-ask-user`, `--output-format json`. |
| (c) Can a credential be supplied without a browser on the container host? | **Yes**: device code, a fine-grained PAT through an environment variable, or a GitHub App token. |
| (d) Does it emit usage telemetry, and in what unit? | **Yes.** OTLP traces carry tokens and AI units per session. The unit is AI credits, not dollars or tokens. |

## 5. Decisions at a glance

| # | Decision | Section |
| --- | --- | --- |
| D1 | Runtime id `copilot_cli`, image `copilot-cli`, npm install pinned in the registry, self-update off | §6.1 |
| D2 | Phase 1 credential: the device-flow `gho_` token taken from `config.json` (as built; the pasted `github_pat_` route was dropped, §0.1). Stored as a flat token and **delivered as `COPILOT_GITHUB_TOKEN`** from a 0600 file, never as a container environment variable. | §6.2 |
| D3 | Automatic sessions run the **TUI** with `-i "<prompt>"`, not `-p`, so the live terminal shows work (the Kiro #575 precedent) | §6.4 |
| D4 | Session context goes in `$COPILOT_HOME/copilot-instructions.md` | §6.5 |
| D5 | Built-in GitHub MCP is off by default. Git and `gh` already go through Aixle's GitHub App wrapper. | §6.6 |
| D6 | Cost comes from `github.copilot.nano_aiu` over a new OTLP traces path: the root `invoke_agent` span in this proposal, each `chat` span as built (§0.1). | §6.8 |
| D7 | Credit to USD conversion is configurable through `COPILOT_AI_CREDIT_USD`, default `0.01` | §6.8 |
| D8 | No server-side refresh in Phase 1. `credential_lifecycle` is static. A refused token goes through the existing login pause. | §6.2 |

## 6. Design

### 6.1 Registry entry and image

```json
{
  "id": "copilot_cli",
  "label": "Copilot CLI",
  "product_name": "GitHub Copilot CLI",
  "vendor": "GitHub",
  "description": "GitHub's Copilot agent in the terminal, signed in with your GitHub account",
  "image": "copilot-cli",
  "dockerfile": "docker/copilot-cli/Dockerfile",
  "cli_version": "1.0.108",
  "cli_latest": { "npm": "@github/copilot" },
  "cli_releases": { "github": "github/copilot-cli", "tag_prefix": "v" },
  "reasoning_effort": {
    "levels": ["low", "medium", "high", "xhigh", "max"],
    "models": [{ "match": "^auto$", "levels": [] }]
  }
}
```

The per-model `reasoning_effort` rules are filled in during the spike (§12).
The CLI accepts all five levels, but not every model honours every level. The
registry convention is to list what the CLI accepts and let the CLI lower or
ignore the rest, as it does for Claude Code and Grok. The release `tag_prefix`
is checked when the entry is added.

**Install route: npm.** It is the same route as Codex, Gemini CLI and Grok,
so the canary's `{ "npm": … }` lookup works unchanged. Pinning by package
version gives a reproducible layer. The standalone tarball with
`SHA256SUMS.txt` is the alternative if the npm wrapper fetches its platform
payload at runtime. That is to be checked when building, because Grok's
package layout changed under us at 1.0.34.

`docker/copilot-cli/Dockerfile` follows `docker/grok/Dockerfile`:

- `useradd -m -d /home/copilot -G ${AGENT_BROWSERS_GROUP} copilot`, with no
  recursive `chown` after the install.
- `ARG CLI_VERSION` with no default. One layer runs `npm install -g
  "@github/copilot@${CLI_VERSION}"`, `su - copilot -c "copilot --version"`
  and `npm cache clean --force`.
- `ENV COPILOT_AUTO_UPDATE=false`. The launch commands also pass
  `--no-auto-update`, because Antigravity once replaced its own binary within
  a second of starting.
- `/etc/aixle-cli-version` is written from `copilot --version`.
- A build-time check, as `grok inspect` does for Grok, that the CLI reports
  the adapter's instructions file as loaded, if the CLI has a
  non-interactive way to list instructions (spike item S9).
- No libsecret or gnome-keyring. The CLI then falls back to `config.json`,
  which is the file we capture.

Image size is not known yet. Tarballs are about 141 MB compressed, so
expect the agent layer to be somewhere around 300–450 MB on top of the base.
It is measured at build time.

### 6.2 Credentials

#### Phase 1A — device-flow login (primary)

- **Auth command:** `copilot login --device-code`.
- **Before login** (`#auth_setup_files`): write `~/.copilot/config.json`
  containing `{"trustedFolders": ["/workspace"]}` plus the plaintext-storage
  pre-answer if the spike confirms the key exists.

  Otherwise the user answers the CLI's "store in plaintext?" question with
  `y` in the auth terminal. `#auth_banner_pattern` and the login help text
  then have to say so, because answering `N` completes the login with nothing
  to capture.
- **Watch path:** `~/.copilot/config.json`.
- **Completion signal:** `__present__` is wrong here. We write the file before
  login, exactly the trap Kiro hit with its device-registration row.

  Use `__contains__:<marker>`, where the marker is text that appears only once
  a token is stored. A first candidate is the token prefix `gho_`. The real
  key name is measured in the spike (S1) across the three states the playbook
  requires: fresh, code shown but not approved, and approved.
- **`#auth_complete?`:** `config.json` parses, and some value matching
  `/\Agh[ou]_[A-Za-z0-9_]{20,}\z/` or `/\Agithub_pat_/` is present under the
  token key found in S1.
- **`#extract_credentials`:** returns a flat hash
  `{ "token" => "gho_…", "login" => "<github login>", "host" => "github.com", "source" => "device_flow" }`.
  The rest of `config.json` is not stored. Trust, MCP and model settings are
  regenerated for every session, so a CLI-side schema change in `config.json`
  cannot corrupt a stored credential.
- **`#credential_identity`:** the GitHub login, with `host`, for "who is
  connected" in the profile and for `#same_credential_identity?`.

#### Phase 1B — fine-grained PAT (alternative)

For users whose organisation forbids the device-code OAuth app, or who
prefer a scoped and expiring token. The profile form takes a `github_pat_`
with the "Copilot Requests" account permission, the same shape as Gemini's
`required_env_fields` / API-key path.

`#validate_metadata` rejects `ghp_` with a clear message: "Copilot CLI does
not accept classic personal access tokens". The stored hash is the same, with
`"source" => "pat"`.

#### Delivery (both)

The token reaches the CLI as **`COPILOT_GITHUB_TOKEN`**:

1. It has the highest precedence. A `GH_TOKEN` or `GITHUB_TOKEN` that a
   project config item, a custom tool or a user's own setup puts into the
   session environment cannot silently replace the user's Copilot login.

   Dropping those variables instead (`#conflicting_env_keys`) would break the
   user's own tooling, which legitimately uses them. Grok solves a similar
   conflict by dropping the variable, but there the variable has no other
   legitimate use.
2. It does not depend on the undocumented layout of `config.json`.
3. It skips the `gh auth token` fallback. In our images that goes through
   `docker/base/git/gh-aixle`, which yields the GitHub App's installation
   token. Copilot would either refuse that token or bill the wrong party.

It is **not** a container environment variable. Pod specs and
`docker inspect` would show it. The adapter writes it to
`~/.copilot/aixle-token` (listed in `#private_file_paths`, mode 0600), and
the session command exports it in the shell:
`COPILOT_GITHUB_TOKEN="$(cat ~/.copilot/aixle-token)" copilot …`.
`BmadMethodInjector` already uses this pattern for `GITHUB_TOKEN`.

The CLI then redacts the variable from the shells and MCP servers it spawns:
`--secret-env-vars COPILOT_GITHUB_TOKEN` is passed explicitly rather than
relying on a reported default.

#### Lifecycle

```ruby
def credential_lifecycle
  { expiry: :none, refresh: :none, rotation: :static, nominal_ttl: nil }.freeze
end
```

- `gho_`: no expiry to read and nothing to refresh. Revocation (by the user,
  by an org policy, or a year unused) shows up as a refused login. It goes
  through the existing login pause (`#refused_login?` / `#auth_resume_prompt`,
  `docs/design/agent-credential-lifecycle.md`) once the CLI's refusal text is
  captured in S2.
- `github_pat_`: the expiry is known when the token is created. Phase 1 does
  not surface it, following the rule that `expires_at` never ships without a
  matching `refresh`. Phase 2 can declare `expiry: :token, refresh:
  :reauth_only, reauth_required_on_expiry: true` (the Grok shape) if expiring
  PATs turn out to be common.
- No `#persist_refreshed_credentials` write-back is needed. The CLI
  exchanges the GitHub token for a short-lived Copilot token in memory and
  never rotates the GitHub token (spike S3 confirms that `config.json` is
  unchanged after a session).

#### Phase 2 — Aixle GitHub App user token (`ghu_`)

The Copilot SDK documents "SaaS products" that make requests "on behalf of
each authenticated user, using their Copilot subscription" through the
product's **own** OAuth app or GitHub App. That is the cleanest compliance
story: the token is issued to Aixle, not lifted from GitHub's CLI OAuth app.

Aixle already runs a GitHub App with user-to-server OAuth
(`Github::InstallationOwnership`). Phase 2 adds a "Connect Copilot with
GitHub" button that runs the app's OAuth flow and stores `ghu_` plus its
refresh token. That turns refresh on (`refresh: :server`, 8 h access token,
rotating refresh token), so the shared refresh broker covers it.

Unknown: whether a `ghu_` token from a third-party App needs an extra
permission to call Copilot. It is not documented (spike S10).

#### Phase 3 — organisation-billed installation token (`ghs_`)

Since 2026-10-27 (public preview), a GitHub App holding the organisation
permission "Copilot Requests" can mint installation tokens whose Copilot
usage is billed to the organisation. For a company that connected its GitHub
organisation to Aixle, this would mean **no per-user Copilot login at all**.
The step uses an org-billed token minted per session from the installation
Aixle already holds (`Github::TokenService`).

Costs:

- The App needs a new permission, so **every installation owner has to
  approve the change**. The feature is off until they do.
- It is a preview, documented for the SDK. Whether the CLI accepts such a
  token outside GitHub Actions is unverified.
- The org admin has to enable "Copilot requests from GitHub App
  installations" and the CLI billing policy.
- Spend is shared across the organisation, which raises its own governance
  questions: budgets and who started what.

This is a separate design once Phase 1 is in use.

### 6.3 Files written into the container per session

| Path (with `COPILOT_HOME=/home/copilot/.copilot`) | Content | Strategy |
| --- | --- | --- |
| `~/.copilot/config.json` | `trustedFolders: ["/workspace", <every mounted repository path>]`, plus model and plaintext-storage keys if they exist. **No token.** | `:fresh` |
| `~/.copilot/aixle-token` | The token (0600, private file) | `:fresh` |
| `~/.copilot/mcp-config.json` | `{"mcpServers": {…}}` (§6.6) | `:fresh` |
| `~/.copilot/copilot-instructions.md` | Aixle session context (§6.5) | via `#context_file_path` |
| `~/.copilot/skills/<name>/SKILL.md` | Installed skills | via `#skills_install_path` |

`COPILOT_HOME` is set explicitly even though it matches the default. The
paths are then a contract in our code, not an inherited default.

### 6.4 Launch

**Auth container:** `copilot login --device-code`.

**Interactive session** (`#session_command(mode:, model:, effort:)`):

```sh
COPILOT_GITHUB_TOKEN="$(cat ~/.copilot/aixle-token)" \
  copilot --allow-all --no-auto-update --disable-builtin-mcps \
          --secret-env-vars COPILOT_GITHUB_TOKEN \
          [--model <id>] [--effort <level>]
```

**Automatic session / workflow step:** the same command plus `--no-ask-user
-i`. `AgentSessionStrategy#launch_agent_in_tmux` appends
`"$(cat /tmp/…prompt)"`, which becomes the value of `-i`.

Why each flag:

- `--allow-all`: the container is the sandbox. This matches `codex --yolo`,
  `grok --yolo` and Claude's skip-permissions.
- `--no-ask-user`: removes the `ask_user` tool, so an automatic session
  cannot block on a question. Kiro's unremovable "Question" dialog is the
  failure this prevents.
- `-i` rather than `-p`: `-p` prints only the final answer and exits. The
  live terminal would show nothing while the agent works, which was rejected
  for Kiro in #575, and the session would end before the agent calls
  `finish_session`. `-p --output-format json` stays the fallback if the TUI
  proves unworkable.
- `--disable-builtin-mcps`: see §6.6.
- `--autopilot`, which keeps the agent going without user turns: evaluated in
  S5. It may reduce stalls when the agent ends a turn without calling
  `finish_session`.

The base strategy's `SESSION_COMMANDS["copilot_cli"]` stays a fallback
(`copilot --allow-all`), as Kiro's does. The adapter's command is the one
that runs.

Known shared limitation: the prompt sits in argv, so `pkill -f` can match the
agent process. This is tracked separately for every runtime and is not made
worse here.

### 6.5 Context, instructions, skills, BMAD

- **`#context_file_path`** is `~/.copilot/copilot-instructions.md`. That is
  the documented user-level instructions file, read in every directory
  whether or not it is a repository. `/workspace` stays clean, as with Grok
  and Kiro. `/workspace/AGENTS.md`, which Codex uses, is the fallback if S9
  shows the user-level file is not loaded in a TUI session.
- **Interaction with repository files.** Copilot also reads the repository's
  `AGENTS.md`, `CLAUDE.md` and `.claude/CLAUDE.md`. That is desirable: the
  agent follows the project's own rules, and Claude Code does the same with
  `CLAUDE.md`.
- **Skills:** `#skills_install_path` is `~/.copilot/skills`.
  `#skills_agent_name` is the skills.sh agent id for Copilot, checked against
  `skills add --list-agents` when building (expected `github-copilot`).
- **BMAD:** map `copilot_cli` to BMAD's GitHub Copilot platform if
  `bmad-method install --list-tools` lists one. Otherwise map it to
  `claude-code`, because Copilot reads `.claude/skills` and `CLAUDE.md` (the
  Grok precedent). If the chosen platform writes a new dot-directory, add it
  to `BMAD_HIDDEN_PATHS`.

### 6.6 MCP

`#mcp_config(servers)` writes `~/.copilot/mcp-config.json`:

```json
{
  "mcpServers": {
    "aixle-tools": { "type": "http", "url": "http://mcp…:4002/…", "headers": { "Authorization": "Bearer …" }, "tools": ["*"] },
    "playwright":  { "type": "local", "command": "…", "args": ["…"], "env": { "PLAYWRIGHT_BROWSERS_PATH": "/opt/playwright-browsers" }, "tools": ["*"] }
  }
}
```

- Keys come from `MCPServer.config_key_for`, as for every runtime, so tool
  namespaces are identical across runtimes. STDIO servers get
  `#mcp_stdio_env` and `#mcp_stdio_args`. `tools: ["*"]` exposes every tool.
- **Plain HTTP on an internal host** (`http://web:4002` locally,
  `http://mcp.<ns>.svc.cluster.local:4002` in clusters) must be shown to work
  in S4. Kiro's binary refused non-loopback HTTP silently. The symptom was "no
  tools", and therefore no `finish_session`. If Copilot does the same, reuse
  Kiro's watcher loopback forward (`MCP_FORWARD_PORT` /
  `MCP_FORWARD_TARGET`).
- **Built-in GitHub MCP off.** Aixle's git and `gh` access goes through the
  GitHub App installation token and the `gh-aixle` wrapper, scoped to the
  project's repositories. The built-in `github-mcp-server` would act as the
  user's own `gho_` across everything the user can reach. That widens the
  agent's reach and duplicates tools the agent already has. It can become a
  per-project option later.
- **Organisation MCP policy.** For Business and Enterprise users whose org
  sets an MCP allowlist or registry, our servers may be filtered out, and a
  failing registry fetch has been reported to drop every non-default server
  silently (#4378). The session would run with no `aixle-tools` and never
  finish.

  Mitigation: at session start the adapter checks the CLI's MCP status (log
  line or `/mcp` state, S4). If `aixle-tools` is missing, the session fails
  with "Your organisation's Copilot MCP policy blocks Aixle's tools" instead
  of hanging. The docs tell admins which server URL to allow.

### 6.7 Models and reasoning effort

- **Catalogue.** There is no documented REST endpoint that lists the models a
  user's plan offers. The Copilot SDK has `models.list`, which also returns
  `billing.tokenPrices`. The CLI has `/model`, and maybe a non-interactive
  listing (S6).

  The adapter's `#fetch_available_models` reads the catalogue in the
  container after login through the existing
  `BaseAdapter#collect_credential_metadata` hook (the Kiro precedent). It
  falls back to a minimal static list, `auto` plus the documented default
  model. The internal `api.githubcopilot.com/models` endpoint is not used
  directly (§7.3).
- **Free and Student** plans get `auto` only. The picker shows what the
  catalogue returns, so these accounts see only `auto`, with a hint.
- **Reasoning effort:** passed as `--effort <level>`. Per-model rules are
  added to the registry after S6. `auto` gets no levels, because which model
  runs is not known in advance.

### 6.8 Usage and cost

**Source: OTLP traces.** Per session, the CLI's root `invoke_agent` span
carries:

- `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`,
  `gen_ai.usage.cache_read.input_tokens` and
  `gen_ai.usage.cache_creation.input_tokens`;
- `github.copilot.nano_aiu`, the AI units consumed, which is what the user is
  billed in;
- `gen_ai.request.model` / `gen_ai.response.model`.

Only the root span is counted: `chat` children repeat the usage, so summing
every span double-counts.

**Platform change, the only new plumbing in this design:**

1. `docker/otlp-ingest/main.go`: add `/v1/traces`. It mirrors
   `handleMetrics`: JSON or protobuf in, `protojson` out, posted to the same
   web endpoint. That is about 40 lines, with a Go test.
2. `UsageStatisticsService`: read `resourceSpans` in
   `#extract_terminal_session_tokens` and `#attribute_sets`, so span batches
   are routed to sessions and authenticated by
   `UsageStatistics::SessionKey` exactly as metric and log batches are.
3. `CopilotCliAdapter#ingest_usage`: select root spans
   (`gen_ai.operation.name = invoke_agent`, no `parentSpanId`), de-duplicate
   by span id (exporters retry), and record tokens and credits per model.
4. Deployment: confirm that the ingest route in clusters forwards
   `/v1/traces`. The ingress may list paths. This needs a change in the
   deployment repository if so.

Session env for this path: `OTEL_EXPORTER_OTLP_ENDPOINT` (our ingest),
`OTEL_EXPORTER_OTLP_PROTOCOL=http/json`, and
`OTEL_RESOURCE_ATTRIBUTES = UsageStatistics::SessionKey.resource_attributes(session)`,
which is the same helper Gemini CLI uses.

**Gate (S7).** If the exporter ignores `OTEL_RESOURCE_ATTRIBUTES`, as Grok's
does, traces cannot be tied to a session. The fallback is then
`COPILOT_OTEL_EXPORTER_TYPE=file` with `COPILOT_OTEL_FILE_EXPORTER_PATH`
inside the container, parsed at cleanup by `#collect_usage`. That is not
real-time, but it is exact and needs no ingest change, so step 1 would then
be dropped.

The file exporter is also the backstop for sessions whose network export
failed. The local `session-store.db` and `session-state/*/events.jsonl` are
a third source. They are undocumented, and a reported bug shows the end-of-run
banner undercounting compared with them (#4351), so they are not the primary
source.

**Pricing.** `cost_cents = nano_aiu / 1e9 × COPILOT_AI_CREDIT_USD × 100`,
with `COPILOT_AI_CREDIT_USD` defaulting to `0.01`. The variable mirrors
`KIRO_CREDIT_USD` and gets a row in `docs/reference/configuration.md`.

Spike S8 checks that one AIU on the span equals one credit on the GitHub
billing page. If it does not, the conversion factor absorbs the difference.

The cost shown is what the session consumed from the user's credit pool at
GitHub's price. Plan credits are pre-paid, so for a user under their
allowance this is an allocation, not new spend. The runtime docs say so.

**OTLP contract fixture.** `bin/capture-agent-otlp copilot_cli` can run the
CLI against `test/otlp_capture/mock.py` in BYOK mode (`COPILOT_OFFLINE=true`,
`COPILOT_PROVIDER_BASE_URL` pointing at the mock). That gives span names and
token attributes with no account.

`nano_aiu` is probably absent under BYOK. The contract test therefore pins
token attributes from the BYOK fixture, plus a second fixture captured once
from a real session during the spike for `nano_aiu`. Re-capturing the real
fixture on a pin raise needs the subscription again. That is an operational
cost of keeping the seat.

**Subscription usage card** (`#fetch_subscription_usage`): GitHub exposes
`GET /users/{username}/settings/billing/ai_credit/usage` for personal plans
only, and the token type it needs is not documented. Not in Phase 1. The
card shows "not available" for Copilot until a token type is confirmed.

### 6.9 Failure signalling

- **`QuotaErrorDetector`:** a new `github_copilot` provider, with
  `AGENT_PROVIDERS["copilot_cli"] = :github_copilot`. The patterns are the
  CLI's rendered messages for exhausted credits, a budget cap, rate limits,
  Copilot disabled by policy, and no Copilot subscription. They are captured
  live in S2. Only Copilot-specific phrasings are added, so no existing
  provider's matching changes.
- **`InteractivePromptDetector`:** an entry for each dialog that can wedge a
  TUI session even after pre-answering. That covers folder trust (in case a
  path is not in `trustedFolders`), the plaintext-storage question in a
  session container, and the login screen (a dead token). Each entry fails
  the session with a message naming the cause.
- **Refused login:** `#refused_login?` matches the CLI's "token invalid /
  revoked / not authorised for Copilot" output (S2), which feeds the existing
  login pause and resume.
- **Runaway spend:** `--max-ai-credits` is per response, not per session, so
  it is a guard against single runaway turns, not a budget. Session-level
  budgets stay the platform's existing session limits and the org's GitHub
  budget. A per-step credit cap is a possible follow-up, not Phase 1.

### 6.10 Security

- **Token scope.** A `gho_` from `copilot login` is the user's GitHub OAuth
  token for GitHub's CLI OAuth app. Its reach is whatever that app's scopes
  grant on the user's account, which may be wider than Copilot alone. That
  is why:
  - it is stored encrypted, like every agent credential;
  - it is delivered only through a 0600 file and an exported variable;
  - it is redacted from tool and MCP environments (`--secret-env-vars`);
  - the built-in GitHub MCP is disabled;
  - Phase 1B, a fine-grained PAT limited to "Copilot Requests", is offered
    to security-conscious users and recommended in the docs for
    organisations.
- **The agent can still read the token** from `/proc/self/environ` or the
  file. That is true of every runtime's credential and is accepted: the
  container belongs to that user's session.
- **Session log redaction:** add `gho_`, `ghu_`, `ghs_` and `github_pat_`
  patterns to the existing secret masking if they are not already covered.
- **Network:** `api.githubcopilot.com` and `api.github.com` (token exchange)
  are reached through the existing egress. No MITM tracking is needed,
  because cost comes from OTLP.

### 6.11 Frontend, docs, changelog

- **Frontend:** add `copilot_cli` to `AgentType` (`shared/ui/types.ts`),
  then let `tsc` list every map: badge colour, analytics colour, and logo
  fallback (no vendor artwork ships, as for Grok).
- **Profile connect copy:** device-code instructions, the `y` to plaintext
  storage if still needed, and the PAT alternative with the exact permission
  name.
- **Docs:**
  - `docs/user-guide/runtimes.md`: tables, credential row, the cost row
    ("AI credits from the CLI's OpenTelemetry traces"), and "seven" changed
    to "eight".
  - Docs portal pages `runtimes.md`, `agents.md`, `what-is-aixle.md`,
    `cli-ref.md`, `config-schema.md` and `searchIndex.ts`.
  - `docs/reference/configuration.md` (`AGENT_IMAGE_COPILOT_CLI`,
    `COPILOT_AI_CREDIT_USD`).
  - `references/aixle-system-reference.md`.
  - An admin note on the organisation policies to enable: Copilot CLI, MCP
    allowlist, and paid usage.
- **`CHANGELOG.md`:** an `### Added` entry under **Profile**, the area that
  owns connecting a runtime account. For example: "**Profile**: connect
  GitHub Copilot CLI with your GitHub account or a fine-grained token, and run
  sessions and workflow steps on your Copilot plan".
  `docs/product/changelog-product-areas.md` also lists the supported runtimes
  in its introduction, so add Copilot CLI there.

## 7. Alternatives considered

### 7.1 Copilot SDK or headless server (`ghcr.io/github/copilot-cli`), or ACP

The SDK (GA 2026-06) and the CLI's `--acp` mode drive the same runtime over
JSON-RPC. They support a per-session `gitHubToken` and emit `assistant.usage`
events with `totalNanoAiu`.

**Rejected for Phase 1.** Aixle's session model is a CLI in a tmux pane:
live terminal, interactive takeover and terminal logs. An RPC-driven agent
would need a new session strategy and a new UI path. It would be the first
runtime not driven through the terminal.

It is worth revisiting if Aixle grows a non-terminal ("API") runtime class.
The SDK's documented multi-user server mode is also the strongest compliance
story (§8).

### 7.2 BYOK only

The CLI can use the customer's own OpenAI, Azure or Anthropic key with no
GitHub login (`COPILOT_PROVIDER_*`). That gives Copilot's agent loop on
another vendor's bill. It is rejected as a product feature: the point of this
runtime is the customer's Copilot plan, and those models already have
first-party runtimes. BYOK is used only for the OTLP test fixture (§6.8).

### 7.3 Calling the Copilot model API directly or proxying it

This is what community `copilot-api` proxies do, through the internal token
exchange and `api.githubcopilot.com`. **Rejected.** It is reverse-engineered
and undocumented. Users report account warnings and suspensions for
"automated requests". It also does not match Aixle's model of a runtime as
the vendor's own CLI. The same reasoning excludes using
`api.githubcopilot.com/models` for the catalogue.

### 7.4 Copilot cloud agent / Agent HQ

GitHub runs the agent on its own infrastructure. Aixle would only trigger it
and read the result. That is out of scope: no Aixle container, no MCP tools,
no live terminal. It is a possible integration, but a different product.

## 8. Terms of use and compliance

**What supports running the official CLI on the user's own credential:**

- The CLI ships documented non-interactive and automation modes (`-p`,
  `--allow-all`, `--no-ask-user`, JSON output).
- GitHub documents running it in GitHub Actions "for automations".
- GitHub officially supports third-party agents on Copilot plans (OpenCode,
  since 2026-01).
- The Copilot SDK documentation explicitly describes "SaaS products" making
  Copilot requests "on behalf of each authenticated user, using their Copilot
  subscription" — through the product's **own** OAuth app or GitHub App.

**Constraints Aixle must respect:**

1. **One login per person** (GitHub Terms of Service, B.3). A Copilot
   credential is per user and is never shared at company level. That is
   already Aixle's model: a step runs on the credential of the user who
   started it.
2. **No token sharing to exceed rate limits** (ToS H), and **no "excessive
   automated bulk activity"** (Acceptable Use Policies). Concurrency stays
   bounded by the existing per-user admission limits.
3. **Organisation policy is the customer's.** If an organisation disables the
   CLI or third-party MCP, Aixle reports that clearly (§6.9) and never works
   around it.

**Grey area.** Phase 1A captures the token that GitHub's own CLI OAuth app
issued and re-delivers it to later containers. This is how every Aixle
runtime works, Claude Code, Codex and Kiro included, and nothing in GitHub's
terms addresses it. Phase 2 (§6.2) removes the question by issuing the token
from Aixle's own GitHub App, which is the path GitHub documents. For
customers who ask, recommend Phase 1B (PAT) or Phase 2.

**Data handling.** Business and Enterprise plans are governed by GitHub's
Generative AI Services terms. Individual plans follow the user's own Copilot
data settings. Aixle adds no data flow beyond what the CLI itself does,
because OTLP export goes to Aixle's own collector.

## 9. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The exporter ignores `OTEL_RESOURCE_ATTRIBUTES`, so traces cannot be attributed | Medium (Grok did this) | No real-time cost | File exporter collected at cleanup (§6.8). Decided in S7 before building step 1. |
| Plain-HTTP non-loopback MCP is refused silently | Low–medium (Kiro did this) | Automatic sessions never finish | Loopback forward already exists (Kiro). Tested in S4. |
| An organisation MCP allowlist drops `aixle-tools` | Medium for Enterprise | Sessions hang | Detect at start and fail clearly. Document the URL for admins. |
| The plaintext-storage question has no pre-answer key | Medium | Users answering `N` finish login with nothing captured | Login banner tells the user to answer `y`. The watcher times out with a specific message. |
| Release cadence of about 3 a week | High | Canary noise, frequent pin raises | Weekly canary already batches releases. Raise pins on green canary only. |
| A CLI update changes a default that blocks the TUI | Medium | Wedged sessions | `InteractivePromptDetector` entries. Old-vs-new launch check on every pin raise (registry doc). |
| AIU ≠ billed credit | Low | Wrong cost | Configurable `COPILOT_AI_CREDIT_USD`. Compared against GitHub's billing page in S8. |
| GitHub tightens terms on third-party automation | Low | Runtime must be withdrawn | Phase 2 (own App token) is the documented path. The runtime is isolated behind its adapter. |
| Free-plan users get `auto` only and a small allowance | High | Poor first impression | The picker shows only `auto`. Profile copy names the plan requirement for model choice. |
| `gho_` reach is wider than Copilot | Certain | Larger blast radius if the container leaks | Redaction, built-in GitHub MCP off, PAT path recommended for organisations (§6.10). |

## 10. Testing

Per `docs/testing.md`: adapter tests are pure input and output, with no
stubbing of the class under test and no vendor-gem mocks. The container layer
is driven through `test/support/fakes/fake_runtime.rb`.

- `test/services/agents/copilot_cli_adapter_test.rb`:
  - `#auth_complete?` across the three measured `config.json` states (as
    fixtures from S1);
  - `#extract_credentials` for `gho_`, `github_pat_`, and rejected `ghp_`;
  - config files, including trusted folders and the absence of the token in
    `config.json`;
  - the 0600 token file;
  - session commands per mode, model and effort;
  - MCP JSON for http, sse and stdio, including header escaping;
  - `#ingest_usage` on root versus child spans, de-duplication, and
    credit-to-cents conversion.
- `test/services/agents/otlp_contract_test.rb`: the BYOK fixture (span names,
  token attributes) and the one-off real-session fixture (`nano_aiu`).
- `docker/otlp-ingest`: a Go test for `/v1/traces`, JSON and protobuf.
- `UsageStatisticsService`: span batches are routed and authenticated, and an
  unkeyed span batch is dropped.
- `QuotaErrorDetector` / `InteractivePromptDetector`: cases taken from the
  spike's captured screens.
- Registry test: the existing suite (`agent_runtimes_registry_test.rb`)
  covers the Dockerfile `ARG CLI_VERSION`, image overrides and command maps.
- Runtime-enumerating fixtures: `container_workflow_integration_test.rb`,
  `bmad_e2e_all_runtimes_test.rb`, factories, seeds, and the frontend test
  fixtures.
- Live: one interactive and one automatic session on staging with a real
  seat, verified in the browser (live terminal, `finish_session`, cost on the
  session page). Then `docker compose exec -T web make check_all`.

## 11. Delivery plan and estimate

Engineer-days, with the codebase's existing patterns and AI assistance:

| Phase | Work | Days |
| --- | --- | --- |
| 0 | Spike (§12) with a real seat. Go/no-go and the answers that fix D2–D6. | 1–1.5 |
| 1 | Registry entry, Dockerfile, settings, canary picks it up | 0.5 |
| 1 | Adapter: credentials (device flow + PAT), config files, launch, MCP, context, skills, BMAD, env, lifecycle | 1.5–2 |
| 1 | OTLP traces path: Go handler, `UsageStatisticsService`, `#ingest_usage`, fixtures, deployment route check (or the file-exporter fallback) | 1–1.5 |
| 1 | Models and effort, quota and prompt detectors, refused-login hook | 0.5–1 |
| 1 | Frontend type, colour and copy; docs; changelog | 0.5 |
| 1 | Tests, `check_all`, staging browser verification | 1–1.5 |
| **1 total** | | **6–8** (plus spike) |
| 2 | Aixle GitHub App user token (`ghu_`) with server refresh | 2–3 |
| 3 | Org-billed installation token (`ghs_`): separate design, App permission rollout, org governance | 3–5 + rollout |

Phase 1 ships behind nothing extra. A runtime with no credential is
invisible to a user until they connect it. If a staged rollout is wanted,
gate the profile's "Connect" button with a platform feature flag
(`docs/architecture/feature-flags.md`).

## 12. Spike plan and subscription

### 12.1 Spike checklist (one day, one seat, local stack)

Build `docker/copilot-cli` locally. Each item ends in a recorded result that
updates this document.

| # | Question | Pass criterion |
| --- | --- | --- |
| S1 | Where and how does `copilot login --device-code` store the token without a keychain? Capture `config.json` in three states: fresh, code shown, approved. | A marker present only in the approved state. The key name for `#auth_complete?`. Whether a plaintext pre-answer key exists. |
| S2 | Capture the CLI's screens for: revoked token, `ghp_` token, no Copilot access, credits exhausted or budget hit, CLI disabled by policy. | Strings for `QuotaErrorDetector` and `#refused_login?` |
| S3 | Is the token portable across containers, with `config.json` unchanged after a session? | The same token works in a second container. No rotation. |
| S4 | `aixle-tools` over `http://web:4002`: are tools listed, and is `finish_session` called? How is MCP status visible? | An automatic session finishes by itself |
| S5 | TUI with `-i`, `--allow-all`, `--no-ask-user` and trusted folders pre-set: does any dialog appear? Is `--autopilot` useful? | No dialog. The prompt runs. The live pane shows work. |
| S6 | Model catalogue without the TUI. Which effort levels does each model honour? | Source for `#fetch_available_models`. Registry `reasoning_effort` rules. |
| S7 | Does the OTLP exporter honour `OTEL_RESOURCE_ATTRIBUTES`? Do root spans carry `nano_aiu`? Which content type is used? | Decides OTLP traces versus the file exporter |
| S8 | `nano_aiu` for a session compared with the change on GitHub's billing usage page | The `COPILOT_AI_CREDIT_USD` default holds |
| S9 | Is `~/.copilot/copilot-instructions.md` loaded in a TUI session started in `/workspace`? Is there a non-interactive way to list instructions for the build check? | The context path is confirmed |
| S10 | (Phase 2 input) Does a `ghu_` token from a test GitHub App work with the CLI, and with which permission? | Go or no-go for Phase 2 |

### 12.2 What the plan has to cover

- **Copilot Free** includes the CLI with `auto` only and a small allowance.
  It is enough for S1, S3, S4, S5, S7 and S9 at no cost, but not for S6
  (model choice and effort), S8 (billing comparison), or anything involving
  organisation policies.
- **A paid plan** is needed for S2 (the budget and exhaustion screens are
  easier to hit on an org budget), S6 and S8, and for ongoing work: staging
  verification and re-capturing the real-session OTLP fixture on pin raises.

### 12.3 Recommendation

**One Copilot Business seat** in a GitHub organisation owned by the company:
**$19/month, 1,900 AI credits pooled.** Set an organisation budget cap, for
example $0 paid usage, so spend cannot exceed the seat. It is the cheapest
paid option, and it is the only one that also tests what Business and
Enterprise customers will hit:

- the "Copilot CLI" policy;
- MCP allowlist and registry behaviour (§6.6);
- org budgets and the exhaustion screens;
- later, the org-billed GitHub App path (Phase 3).

If the company already has Copilot Business for its developers, this is a
seat assignment in a test organisation, not a new purchase.

The fallback is a personal **Copilot Pro+ ($39/month, 7,000 credits)**. It
has more credits and premium models, but no organisation policies.
**Copilot Pro ($10, 1,500 credits)** works for Phase 1 development, but
lacks some premium models and the org paths.

## 13. Open questions

1. Does a plaintext-storage pre-answer key exist (S1), or does the login copy
   have to ask the user to type `y`?
2. Is 1 AIU equal to 1 billed AI credit (S8)?
3. Does the CLI accept a third-party GitHub App's `ghu_` token, and with
   which permission (S10)?
4. Does the cluster ingress forward `/v1/traces` to the OTLP ingest (§6.8,
   step 4)?
5. Should the built-in GitHub MCP become a per-project option (§6.6)?
6. Should the profile show a PAT's expiry (Phase 2 lifecycle)?
7. Org-billed tokens (Phase 3): who in a company may run sessions billed to
   the organisation, and how is that surfaced?

## 14. Sources

Vendor documentation and announcements, read 2026-11-10:

- Install: https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli
- Authenticate (precedence, token types, device code, no keychain): https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli
- Troubleshoot auth (classic PAT rejected): https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/troubleshoot-copilot-cli-auth
- Configure (`config.json`, `trustedFolders`, `COPILOT_HOME`, client telemetry): https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/configure-copilot-cli
- Command reference (flags, environment variables, OpenTelemetry attributes and metrics): https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference
- Custom instructions: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions
- MCP servers: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers
- Skills: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills
- BYOK: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models
- ACP server: https://docs.github.com/en/copilot/reference/acp-server
- Plans: https://docs.github.com/en/copilot/get-started/plans
- Usage-based billing (2026-06-01): https://github.blog/changelog/2026/04/27/github-copilot-is-moving-to-usage-based-billing/
- AI credit session limits: https://github.blog/changelog/2026-07-01-set-ai-credit-session-limits-in-copilot-cli-and-sdk/
- CLI in Actions without a PAT: https://github.blog/changelog/2026-07-02-copilot-cli-no-longer-needs-a-personal-access-token-in-github-actions/
- SDK on behalf of users (SaaS): https://docs.github.com/en/copilot/how-tos/copilot-sdk/set-up-copilot-sdk/github-oauth
- SDK server-to-server (org-billed `ghs_`): https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/server-to-server-tokens
- OpenCode supported (2026-01-16): https://github.blog/changelog/2026-01-16-github-copilot-now-supports-opencode/
- Billing usage REST: https://docs.github.com/en/rest/billing/usage
- GitHub Terms of Service: https://docs.github.com/en/site-policy/github-terms/github-terms-of-service
- Acceptable Use Policies: https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies
- Issues: github/copilot-cli#4378 (MCP registry fetch failure drops servers), #4351 (exit banner undercounts)
- Releases: https://github.com/github/copilot-cli/releases

In-repo precedents:

- `docs/architecture/agent-runtime-registry.md`
- `docs/design/grok-runtime-integration.md`
- `docs/planning-artifacts/research/technical-kiro-cli-as-a-platform-agent-runtime-research-2026-08-28.md`
- `docs/design/agent-credential-lifecycle.md`
- `app/services/agents/base_adapter.rb`
- `app/services/container_strategies/agent_base_strategy.rb`
- `app/services/usage_statistics_service.rb`
- `docker/otlp-ingest/main.go`
