---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - docs/planning-artifacts/research/technical-aws-bedrock-agentic-cli-integration-research-2026-07-24.md
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Kiro CLI as a platform agent runtime'
research_goals: 'Determine whether and how Kiro CLI can join the platform agent-runtime list (today claude_code, cursor_cli, codex, gemini_cli): verify its current ToS/embedding posture, headless capability, and auth/billing surfaces against live sources; compare the four candidate credential models (BYO subscription login, KIRO_API_KEY headless, BYO-Bedrock, platform-brokered) and recommend one; produce a concrete implementation plan across every codebase touch point, generalized into a reusable "add any new agent runtime" playbook.'
user_name: 'Artem_petrov'
date: '2026-08-28'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-08-28
**Author:** Artem_petrov
**Research Type:** technical

---

## Research Overview

This research answers an engineering question with a legal gate in front of it: can Kiro CLI become the platform's fifth agent runtime alongside `claude_code`, `cursor_cli`, `codex` and `gemini_cli`, and if so, what exactly has to be built? It was conducted on 2026-08-28 through the six-step BMAD technical-research workflow, using live primary sources (kiro.dev docs, changelog, pricing and billing FAQ; the `kirodotdev/Kiro` issue tracker; AWS and press coverage) plus a direct audit of this repository's runtime-registration surface.

The headline finding reverses the conclusion of the previous Bedrock research from 2026-07-24. Kiro's permitted-use wording has since been widened and now names, verbatim, "Kiro IDE, Kiro CLI, Kiro on the web, Kiro Crew, ACP compatible IDEs, and automation in software development (ex: reviews during CI/CD)" as sanctioned surfaces, while prohibiting only "third-party automation harnesses (such as OpenClaw) that route requests outside of Kiro's native interfaces". The platform's architecture — run the vendor's own unmodified CLI inside a per-user container, with the user's own credentials — sits on the permitted side of that line, and Kiro CLI 2.0 (2026-04-13) shipped exactly the headless surface such automation needs (`--no-interactive`, `KIRO_API_KEY`, `--output-format stream-json`). What has *not* changed is BYO-Bedrock: still absent, still an open feature request.

Two hard engineering findings shape the build. First, Kiro CLI stores its login in a **SQLite database** (`~/.local/share/kiro-cli/data.sqlite3`), not a JSON config file — which is incompatible with the JSON-shaped `Agents::BaseAdapter` contract and the container watcher's key-presence check, and makes the API-key model the only cheap path in. Second, credits — not tokens or dollars — are Kiro's unit of account, so `cost_cents` needs an explicit decision rather than a parser. The full executive summary, the recommended two-phase plan, the complete touch-point checklist and the generalized "add a new runtime" playbook are in the **Research Synthesis** section at the end of this document.

---

## Technical Research Scope Confirmation

**Research Topic:** Kiro CLI as a platform agent runtime
**Research Goals:** Verify whether Kiro CLI may legally and technically be embedded as a platform runtime; compare the four candidate credential models and recommend one; produce a concrete implementation plan across every codebase touch point; generalize the result into a reusable playbook for adding any new agent runtime.

**Technical Research Scope:**

- Architecture Analysis — where a fifth runtime attaches to `AgentBaseStrategy`, `Agents::BaseAdapter`, `AgentCredential`, and the container/auth lifecycle
- Implementation Approaches — adapter shape, image build, credential capture, context and MCP injection, usage accounting
- Technology Stack — Kiro CLI versions, install surface, command/flag inventory, auth methods, storage layout, credit model
- Integration Patterns — headless vs interactive drive modes, ACP, MCP config schema, stream-json event surface, device-flow login
- Performance Considerations — image size, container start cost, session concurrency, credit exhaustion behaviour
- Commercial/legal posture — permitted-use terms, per-seat licensing, API-key gating, the third-party-harness prohibition

**Research Methodology:**

- Current web data with rigorous source verification against vendor primary sources
- Multi-source validation for every critical claim; conflicts surfaced explicitly rather than resolved silently
- Confidence levels (High/Medium/Low) attached to every non-trivial claim; training-data-only claims flagged as such
- Direct inspection of this repository as the second evidence stream for all implementation claims

**Explicitly out of scope:** writing the code, building the image, and obtaining legal sign-off. This document produces the decision and the plan.

**Scope Confirmed:** 2026-08-28

---

## Technology Stack Analysis

### Product Identity and Source Posture

Kiro CLI is the rebranded Amazon Q Developer CLI. The agent **harness is closed-source**, and stayed closed even through AWS's August 2026 open-source push: on 2026-08-04 AWS released **Kiro Crew** — the multi-agent orchestration layer (scheduling, memory, coordination, security) — under Apache 2.0, while "the proprietary Kiro CLI agent harness remains closed-source and metered by usage credits."
_Practical consequence: we integrate by driving a binary we cannot read, patch, or vendor. Every behavioural claim below is documentation- or observation-based, never source-based._
_Sources: <https://www.forbes.com/sites/janakirammsv/2026/08/06/aws-open-sources-kiro-crew-but-keeps-the-agent-harness-closed/>, <https://kiro.dev/blog/one-agent/>_ (Confidence: High)

### Release Timeline and Version Surface

| Version | Date | What it changed (integration-relevant) |
| --- | --- | --- |
| 1.28.0 | 2026-03-20 | Experimental terminal UI behind `--tui` |
| **2.0** | **2026-04-13** | **Headless mode**, Windows support, TUI graduated to default |
| 2.5 | 2026-05 | Visible thinking, subagent review loops |
| 2.8 | 2026-06-17 | **CLI V3 early access** (`kiro-cli --v3`), runs alongside 2.x |
| 2.11 | 2026-07 | MCP authentication management |
| 2.13 | 2026-07 | Built-in `introspect` subagent, global hooks |
| 2.14 | 2026-07 | `/upgrade-agent` — migrate V2 agent configs to V3 format |
| 2.15.0 | 2026-07-27 | Guided `/spec new`, Plan mode auto-executes approved plans |
| 2.16 | 2026-07 (late) | `/tangent` side-conversations |

_Two engines coexist: **V3 is opt-in and not the default** — "your current setup remains unchanged until you explicitly opt in." V3 breaks the V2 session format, replaces trust flags with a capability `permissions.yaml`, moves hooks to standalone files, and removes `aws_tool`._
_Integration consequence: **pin the CLI version in the image**, and treat "which engine" as an explicit runtime decision, because `--trust-all-tools` (V2) and `permissions.yaml` (V3) are different permission models._
_Sources: <https://kiro.dev/changelog/cli/>, <https://kiro.dev/changelog/cli/2-0/>, <https://kiro.dev/changelog/cli/2-8/>, <https://kiro.dev/docs/cli/v3/>_ (Confidence: High)

### Install Surface and Runtime Prerequisites

- Install: `curl -fsSL https://cli.kiro.dev/install | bash`. Binary name: **`kiro-cli`**. Platforms: macOS, Linux, Windows 11.
- Container-proven: the install script runs fine in a Dockerfile as a **non-root user**, provided the state directories exist and are `chown`ed before the install step. A DevContainer walkthrough persists exactly two paths as named volumes to keep a login across rebuilds:

```json
"mounts": [
  { "source": "kiro-config",   "target": "/home/node/.kiro",                 "type": "volume" },
  { "source": "kiro-cli-data", "target": "/home/node/.local/share/kiro-cli", "type": "volume" }
]
```

_This maps cleanly onto our per-agent-user image pattern (`useradd -m -d /home/<agent>`, then install as that user)._
_Sources: <https://kiro.dev/docs/cli/>, <https://dev.classmethod.jp/en/articles/kiro-cli-in-devcontainer/>, <https://learn.arm.com/install-guides/kiro-cli/>_ (Confidence: High)

### Command and Flag Inventory

Global flags on every command: `--agent <name>`, `--verbose/-v`, `--version/-V`, `--help/-h`, `--help-all`.

| Command | Integration-relevant flags |
| --- | --- |
| `kiro-cli chat` | `--no-interactive`, `--trust-all-tools`, `--trust-tools <list>`, `--output-format stream-json`, `--effort low\|medium\|high\|xhigh\|max`, `--resume`, `--resume-id <ID>`, `--list-sessions`, `--wrap` |
| `kiro-cli login` | `--social google\|github`, `--identity-provider <URL>`, `--region <REGION>`, `--license pro\|free`, **`--use-device-flow`** |
| `kiro-cli logout` | Clears credentials |
| `kiro-cli whoami` | `--format plain\|json\|json-pretty` — cheap liveness/identity probe |
| `kiro-cli mcp` | `add`, `remove`, `list`, `import`, `status` |
| `kiro-cli agent` | `list`, `create`, `edit`, `validate`, `migrate`, `set-default` |
| `kiro-cli acp` | Starts an ACP agent over stdio (`--agent my-agent` to pick a config) |
| `kiro-cli doctor` / `diagnostic` | `--format`, `--strict` — usable as an image smoke test |
| `kiro-cli update` | `--non-interactive/-y` |

_Source: <https://kiro.dev/docs/reference/cli-commands/>_ (Confidence: High)

### Authentication Methods

| Method | Available to CLI | Browser needed | Fits our auth container? |
| --- | --- | --- | --- |
| Social (Google, GitHub) | Yes | Yes, or device flow | Yes — device flow |
| AWS Builder ID | Yes | Yes, or device flow | Yes — device flow |
| IAM Identity Center (SSO) | Yes (`--identity-provider <start-url> --region`) | Yes, or device flow | Yes — device flow |
| External IdP (work email → org IdP) | Yes | Yes | Partially — org-dependent |
| **API key (`KIRO_API_KEY`)** | Yes | **No** | Not needed — paste-a-key form |

Device flow "displays a URL and a one-time code that you enter in any browser — no port forwarding required," which is precisely the shape our ttyd auth container already renders for `claude_code`. **Credential precedence: active browser session → `KIRO_API_KEY` env var → prompt to sign in.**

API-key format is `ksk_…`:

```bash
export KIRO_API_KEY=ksk_xxxxxxxx
kiro-cli chat --no-interactive "your prompt here"
```

_Sources: <https://kiro.dev/docs/getting-started/authentication/>, <https://kiro.dev/docs/cli/headless/>_ (Confidence: High)

### API-Key Availability Gate (two gates, not one)

1. **Tier gate:** API keys are "only available for Kiro Pro, Pro+, Pro Max, and Power subscribers" — the Free tier cannot produce one.
2. **Org gate:** in Kiro Enterprise, API-key generation is **disabled by default**; an administrator must switch on "Enable users to generate API keys" in the Kiro console (Settings → Kiro settings). Once enabled, users self-serve keys from the Kiro portal, expressly for "executing automation scripts with Kiro CLI in their local machine or remote environment like CI/CD pipelines."

_The docs do **not** state key scope, expiry, or rotation policy. Treat expiry as unknown; do not assume non-expiring._ (Confidence: High on the gates, Low on scope/expiry — undocumented)
_Sources: <https://kiro.dev/docs/cli/headless/>, <https://kiro.dev/docs/enterprise/governance/api-keys/>_

### Billing Model — Credits, Per Seat

| Tier | Price | Monthly credits | Add-on credits |
| --- | --- | --- | --- |
| Free | $0 | 50 | — |
| Pro | $20 / user / month | 1,000 | $0.04 each |
| Pro+ | $40 / user / month | 2,000 | $0.04 each |
| Pro Max | $100 / user / month | 5,000 | $0.04 each |
| Power | $200 / user / month | 10,000 | $0.04 each |

Credits do not roll over month to month (purchased add-on credits expire 12 months from purchase). All paid tiers are priced "per user / month," and the FAQ states plainly that for team usage "each developer needs their own subscription" — **seat sharing is not permitted**.

_Two consequences: (a) our existing per-(user, company) `AgentCredential` model is the right shape and a pooled platform-owned Kiro account is not an option; (b) the platform's minimum entry cost for a Kiro user is a $20/month Pro seat, because the free tier cannot mint an API key._
_Source: <https://kiro.dev/pricing/>_ (Confidence: High)

### Cloud/Model Backend — BYO-Bedrock Still Absent

Kiro CLI runs against a fixed Kiro-hosted model catalog priced in credits. Bring-your-own-key / bring-your-own-Bedrock remains an **open, unshipped feature request** across at least three tracked issues: #1067 ("Use own API Key and choose own hosted models (ex, Opus 4 on AWS Bedrock)"), #695 ("Anthropic API Key (Bring Your Own API KEY)"), and #9367 ("Support Bring Your Own API Key (BYOK) and Local Models via OpenAI-Compatible Endpoints").

_This is unchanged from the 2026-07-24 finding: choosing Kiro CLI routes zero attributable consumption into a customer's Bedrock account. Kiro is a **product** integration, never a Bedrock-consumption play._
_Sources: <https://github.com/kirodotdev/Kiro/issues/1067>, <https://github.com/kirodotdev/Kiro/issues/695>, <https://github.com/kirodotdev/Kiro/issues/9367>_ (Confidence: High)

### Where Kiro CLI Sits Against Our Four Incumbents

| Runtime | Credential model in our platform | Vendor billing unit | Refreshable token |
| --- | --- | --- | --- |
| `claude_code` | OAuth login captured from `~/.claude/.credentials.json` (+ API key / Bedrock) | Tokens → cents | Yes |
| `codex` | OAuth login captured from `~/.codex/auth.json` | Tokens → cents | Yes |
| `cursor_cli` | Login capture | Tokens | Yes |
| `gemini_cli` | API key, encrypted blob at `~/.gemini/gemini-credentials.json` | Tokens | No |
| **`kiro_cli` (proposed)** | **API key (`ksk_…`) via env**, or login in a SQLite DB | **Credits** | **Unknown / no refresh endpoint** |

_Closest existing precedent: **`gemini_cli`** — an API-key runtime whose on-disk credential is an opaque non-JSON blob, already handled by our `__present__` watcher sentinel._ (Confidence: High — repository inspection, `app/services/agents/gemini_cli_adapter.rb`)

---

## Integration Patterns Analysis

### The Permitted-Use Boundary (the gate that decides everything)

Kiro's billing FAQ states both halves verbatim:

> "Kiro subscriptions can be used with Kiro IDE, Kiro CLI, Kiro on the web, Kiro Crew, ACP compatible IDEs, and automation in software development (ex: reviews during CI/CD)."

> "Use through third-party automation harnesses (such as OpenClaw) that route requests outside of Kiro's native interfaces is not permitted."

The operative test is **"route requests outside of Kiro's native interfaces."** Two integration shapes fall on opposite sides:

| Shape | Example | Verdict |
| --- | --- | --- |
| Run the vendor's own `kiro-cli` binary, unmodified, with the user's own credential, as development automation | Our container model; CI review jobs | **Permitted** — reads directly onto "Kiro CLI" + "automation in software development" |
| Extract the stored credential and replay it against Kiro's backend from a foreign agent loop | `kiro-gateway`, `kirocc` (relay Anthropic-Messages-compatible requests to the Kiro backend using Kiro CLI credentials) | **Prohibited** — the named failure mode |

_This is the substantive change since 2026-07-24, when the prohibition was read as disqualifying. The prohibition is unchanged; the **permitted list** is now explicit and includes both the CLI and development automation. Our platform launches the real CLI in a TTY and never speaks Kiro's wire protocol itself._
_Caveat (Confidence: Medium): the docs do not address a **hosted multi-tenant platform** running the CLI on a user's behalf. The seat rules are individual; our per-(user, company) credential keeps one seat to one human, but this reading should be confirmed in writing with Kiro/AWS before launch — see Open Verification Items._
_Sources: <https://kiro.dev/docs/billing/related-questions/>, <https://github.com/jwadow/kiro-gateway>, <https://github.com/d-kuro/kirocc>_ (Confidence: High on the quotes)

### Credential Storage — The Central Engineering Mismatch

Kiro CLI does **not** keep its login in a JSON file. It keeps it in a SQLite database:

- `~/.local/share/kiro-cli/data.sqlite3` — table `auth_kv`, keys `kirocli:odic:token` / `codewhisperer:odic:token`, holding access token, refresh token, expiry and device-registration data
- `~/.aws/sso/cache/device-sso-lsp-token.json` — additionally present for AWS SSO-based logins
- `~/.kiro/` — configuration shared with the IDE (MCP, agents, steering), **not** auth

Our `Agents::BaseAdapter` contract is JSON- and string-shaped throughout: `config_path`, `auth_complete?(config_content)`, `extract_credentials(config_content)`, `generate_config(...).to_json`, and `AgentCredentialsService#extract_from_container` reads a single file's text. The in-container watcher (`docker/base/watcher/index.js`) polls `AUTH_WATCH_PATH` and looks for `AUTH_REQUIRED_KEYS` inside the file's contents.

**Consequences, in order of severity:**

1. A binary SQLite file cannot be key-inspected by the watcher. The existing `__present__` sentinel (added for `gemini_cli`'s encrypted blob) degrades the check to "file exists and is non-empty" — which for SQLite is true the moment the CLI initialises, *before* login completes. **The sentinel is not sufficient here.**
2. Round-tripping a login would mean storing the whole `.sqlite3` as a base64 blob and writing it back — opaque, version-fragile across CLI upgrades, and unverifiable server-side.
3. There is no documented refresh endpoint, so `AgentCredential::REFRESHABLE_AGENT_TYPES` cannot include it and `expires_at` cannot be derived.

_The API-key model sidesteps all three: nothing to scrape, nothing to write back, no expiry parsing._
_Sources: <https://github.com/jwadow/kiro-gateway>, <https://gist.github.com/abdallah/386d37ba0b0beb40f1772777765e4736>, repository: `app/services/agents/base_adapter.rb`, `docker/base/watcher/index.js`_ (Confidence: High on our contract; Medium-High on Kiro's storage — sourced from third-party tooling that reads it, not vendor docs)

### Drive Modes — Interactive vs Headless vs ACP

| Mode | Command | Fits our `agent_session` container? |
| --- | --- | --- |
| Interactive TUI | `kiro-cli` | **Yes** — this is exactly what `SESSION_COMMANDS` + tmux + ttyd do today |
| Headless | `kiro-cli chat --no-interactive --trust-all-tools "<prompt>"` | Yes — but one-shot; no mid-session input, no slash commands, no TUI |
| Structured headless | `… --output-format stream-json` | Yes — JSON Lines on stdout; **V2/V3 engines only** |
| ACP | `kiro-cli acp` | Alternative surface: JSON-RPC 2.0 over stdio, session load/manage, streaming, tool calls, model switching, plus `_kiro.dev/*` extensions for slash commands, MCP and compaction |

_Design note: our workflow-step runs are conceptually one-shot and would suit headless; our interactive sessions need the TUI. The two can share one adapter through `session_command(mode:, prompt:, model:)`, which already receives a `mode`._
_ACP is strategically interesting — it is a documented, vendor-blessed programmatic surface and Kiro's own permitted-use list names "ACP compatible IDEs" — but it would be a **new integration mode for our platform**, which today drives every runtime through a terminal. Out of scope for a first landing; recorded as a future option._
_Sources: <https://kiro.dev/docs/cli/headless/>, <https://kiro.dev/docs/cli/acp/>, <https://dev.to/aws-builders/integrate-kiro-cli-into-your-ai-agent-via-acp-10jn>_ (Confidence: High)

### Persona and Context Injection

Kiro custom agents are JSON or Markdown files, global at `~/.kiro/agents/<name>.json` or workspace-scoped at `.kiro/agents/<name>.json`; workspace wins on a name clash; nested dirs allowed (`~/.kiro/agents/team/planner.md` → agent `team/planner`).

```json
{
  "name": "my-agent",
  "description": "A custom agent for my workflow",
  "tools": ["read", "write", "shell"],
  "excludedTools": ["knowledge"],
  "includeMcpJson": true,
  "includePowers": false,
  "resources": ["file://./ARCHITECTURE.md", "skill://backend-patterns"],
  "permissions": { "rules": [{ "capability": "shell", "match": ["npm *", "git *"], "effect": "allow" }] },
  "prompt": "You are a helpful coding assistant",
  "model": "claude-sonnet-5",
  "welcomeMessage": "Ready to help. What are you working on?"
}
```

_This is a **better** persona surface than the file-convention approach we use elsewhere (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`): `Agent#to_system_prompt` maps straight onto `prompt`, our selected model onto `model`, and our assembled context files onto `resources` (`file://…`). Selection at launch is the global `--agent <name>` flag. `permissions.rules` additionally gives a real allow-list, which is the V3 replacement for `--trust-all-tools`._
_Sources: <https://kiro.dev/docs/custom-agents/>, <https://kiro.dev/docs/reference/cli-commands/>, <https://kiro.dev/docs/cli/v3/>_ (Confidence: High on schema/paths, Medium on exact `--agent` semantics in `chat` subcommand — documented as a global flag, not re-documented per subcommand)

### MCP Wiring

Config paths: user-global `~/.kiro/settings/mcp.json`, workspace `.kiro/settings/mcp.json` (workspace wins). Both hot-reload on save; a watcher also monitors `.kiro/agents`.

Schema — richer than the minimal `mcpServers` shape, and a superset of what our `mcp_config` currently emits for any runtime:

| stdio server | Remote HTTP/SSE server |
| --- | --- |
| `command` (required) | `url` (required; HTTPS, or HTTP for localhost) |
| `args` | `headers` — sent on connect, supports `${VAR}` interpolation |
| `env` | `oauth` (object), `oauthScopes` (array) |
| `disabled` | `disabled` |
| `autoApprove` — tools auto-approved | `autoApprove` |
| `disabledTools` — tools hidden from the agent | `disabledTools` |

```json
{
  "mcpServers": {
    "api-server": {
      "url": "https://api.example.com/mcp",
      "headers": { "Authorization": "Bearer ${API_TOKEN}", "X-Custom-Header": "value" }
    }
  }
}
```

Management surface: `kiro-cli mcp add|remove|list|import|status`; `--require-mcp-startup` turns a failed server into exit code 3.

_Assessment: **full parity with what our platform needs, plus headroom.** Our internal `aixle-tools` server is a bearer-token HTTP server → the `headers` field covers it directly, and `${VAR}` interpolation means the token can arrive as an env var instead of being baked into the config file. `autoApprove`/`disabledTools` are per-server tool gating we do not currently emit for any runtime but could. Merge strategy for the adapter should be `:merge_json` (same as `gemini_cli`), since `mcp.json` is a shared IDE/CLI file that may already exist._
_Conflict to flag: changelog 2.11 advertises "MCP authentication management" and the config schema documents `oauth`/`oauthScopes`, yet issue #7525 reports "Kiro CLI does not support MCP server OAuth authentication flow." Either the issue predates the feature or the schema field is IDE-only. Not on our critical path (bearer tokens work), but verify before promising remote-OAuth MCP parity on this runtime._
_Sources: <https://kiro.dev/docs/mcp/configuration/>, <https://kiro.dev/docs/mcp/>, <https://github.com/kirodotdev/Kiro/issues/7525>, <https://kiro.dev/changelog/cli/>_ (Confidence: High on paths/schema, Low on remote-OAuth status — sources conflict)

### Skills

Kiro implements the **open Agent Skills standard** (agentskills.io) — the same `SKILL.md`-with-YAML-frontmatter format our skills catalog already produces, with `name` (lowercase/hyphens, ≤64 chars, must match the folder) and `description` required.

- Install paths: global `~/.kiro/skills/`, workspace `.kiro/skills/`; workspace wins on a name clash.
- Activation: automatic (Kiro matches the request against skill descriptions) **and** as explicit `/`-slash commands.
- Capability matrix lists skill activation as supported in IDE, CLI, Web and Mobile; workspace + global skills in IDE and CLI.
- skills.sh lists Kiro CLI as a supported target agent and publishes a per-agent page for it.

_Assessment: **full parity, and the cheapest integration of the whole feature set.** Our `skills_install_path` becomes `~/.kiro/skills`; hand-written private skills are written there directly (which is what we already do everywhere, deliberately, to avoid `skills add` reporting a private skill's files as telemetry). The `skills_agent_name` value for `npx skills add -a <name>` is **not confirmed** — skills.sh has a `kiro-cli` agent page but does not publish the flag value or install paths on it. Verify in the spike; if the CLI has no Kiro target, writing files directly still works._
_Sources: <https://kiro.dev/docs/skills/>, <https://www.skills.sh/agent/kiro-cli>, <https://github.com/vercel-labs/skills>, repository: `app/services/agents/base_adapter.rb:150-180`, `app/services/session_context_service.rb:212-280`_ (Confidence: High on Kiro's side, Medium on the skills-CLI agent id)

### Steering, AGENTS.md, and Powers

Beyond the custom-agent `prompt` field, Kiro has a second persistent-context mechanism:

- **Steering files** — markdown in `.kiro/steering/` (workspace) or `~/.kiro/steering/` (global). Frontmatter supports `inclusion: always | fileMatch | manual | auto`, **but "On Kiro CLI, inclusion modes are not currently supported. All steering files in the `.kiro/steering/` directory are loaded automatically."** For the CLI, steering is effectively "always on."
- **`AGENTS.md`** — supported at the workspace root and discovered in subdirectories, on all platforms. **`CLAUDE.md` is not mentioned as supported.**
- **Powers** — Kiro's own bundling of MCP tools + steering + hooks with context-aware lazy loading. **IDE-only today**; the docs say CLI support is planned. Irrelevant to our integration either way.

_Assessment: our existing `/workspace/AGENTS.md` context-file convention works unchanged, so `context_file_path` needs no special casing. The always-loaded steering directory is an additional injection point if per-project standards ever need to be separated from the session context._
_Sources: <https://kiro.dev/docs/steering/>, <https://kiro.dev/powers/>_ (Confidence: High)

### Model Selection

Kiro serves a **fixed, Kiro-hosted catalog** priced in credit multipliers (roughly 0.05x–2.4x against the Auto baseline): GPT-5.6 Sol / Terra / Luna, Claude Opus 5 and Sonnet 5, plus an `Auto` router. Selection is a dropdown in IDE/CLI/Web/Mobile, and the custom-agent config carries a `"model"` field.

**Correction from the installed binary (kiro-cli 2.20.1, read from `chat --help`).** Two things the documentation pages do not state, and which this research initially got wrong:

- **`kiro-cli chat --model <MODEL>` exists.** A session's model does *not* have to be pinned through a custom agent definition — the flag takes it directly, exactly like every other runtime here. This removed the only reason the adapter needed to write an agent JSON at all.
- **`kiro-cli chat --list-models --format json` exists.** A programmatic model list is therefore available — but *in the container, through the CLI, against the user's login*, not as a server-side HTTP call. Our `fetch_available_models` runs server-side from the Rails process against a vendor API, and Kiro publishes no such API. So the parity gap is narrower than "no list exists": the data is reachable, just not through the seam our profile model-picker uses.

_Source: <https://kiro.dev/docs/models/>, plus `kiro-cli chat --help` from the built `aixle/kiro-cli` image_ (Confidence: High — read off the shipped binary)

### BMAD Injection

BMAD-METHOD's installer lists **Kiro CLI** among its supported tools (alongside Claude Code, Cursor, Gemini CLI, Codex and ~40 others), so `BmadMethodInjector::AGENT_TYPE_TO_BMAD_TOOL` can get a real entry rather than an opt-out. The exact tool id is printed by `npx bmad-method install --tool list` and must be read from there, not guessed; `BMAD_HIDDEN_PATHS` will likely need `.kiro/skills` added alongside the existing `.claude/skills` / `.gemini/skills` entries.
_Sources: <https://deepwiki.com/bmad-code-org/BMAD-METHOD/10-ide-integration>, <https://github.com/bmad-code-org/BMAD-METHOD/blob/main/docs/how-to/install-bmad.md>, repository: `app/services/bmad_method_injector.rb:9-22`_ (Confidence: Medium — support is listed, the id is unverified)

### Usage and Cost Telemetry

- In headless `stream-json`, run events arrive as JSON Lines; `kiro.dev/metadata` events carry **real-time credits and context usage**.
- No documented OTLP exporter, and no documented per-request token counts in the shape `claude_code`/`codex`/`gemini_cli` emit.
- The billing unit is **credits**, not tokens and not cents.

_Consequences for `UsageStatistic`: (a) in interactive TUI mode there is no stream-json stream at all, so first-landing usage capture is either MITM-derived or absent; (b) even with stream-json, mapping credits → `cost_cents` needs a policy decision (credit list price is $0.04 for add-ons, but bundled credits have a different effective rate per tier), so the honest first move is to record credits in `events_data` and leave `cost_cents` null rather than invent a conversion. Our own docs already state the contract for this case: "If `cost_cents` is `null` on a finished session, the runtime didn't emit usage events."_
_Sources: <https://kiro.dev/docs/cli/headless/>, <https://kiro.dev/pricing/>, repository: `app/frontend/pages/Docs/data/pages/runtimes.md`_ (Confidence: High on the credits unit, Medium on the stream-json event catalogue — the vendor blog does not enumerate event types; the schema detail comes from secondary coverage)

### Failure Signalling

| Exit code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | General failure — **auth error, invalid args, operation failed** |
| 3 | MCP server failed to start (only with `--require-mcp-startup`) |

Hook exit codes are separate: 0 success, 2 blocks tool execution (PreToolUse only), anything else = hook failure.

_Note the coarseness: credit exhaustion is not distinguishable from a bad flag — both are exit 1. Our quota-error scanning (`scan_quota_errors_activity`) will need a stderr/stdout text match for this runtime, not an exit-code branch._
_Source: <https://kiro.dev/docs/reference/exit-codes/>_ (Confidence: High)

### Security Posture of the Integration

- **Credential secrecy:** an API key is a bearer secret with no documented scope limiting. It lands in `AgentCredential.encrypted_config_data` (already encrypted at rest via `Encryptable`) and is injected only at container start as `KIRO_API_KEY` — never baked into an image. That matches the existing `gemini_cli` handling.
- **Blast radius:** because scope/expiry are undocumented, assume a leaked key is a full-account key until proven otherwise. Ship with the ability to revoke-and-replace from the profile page (already the generic behaviour of `AgentCredential.from_artifacts`).
- **Trust flags:** `--trust-all-tools` is exactly as dangerous as `codex --yolo` and `gemini --yolo`, which we already run in isolated per-session containers. On V3 the safer `permissions.rules` allow-list becomes available and should be preferred once V3 is default.
- **Telemetry:** Kiro's privacy/security docs are the reference for what the CLI transmits; verify before enabling on customer repositories.
_Sources: <https://kiro.dev/docs/cli/privacy-and-security/>, repository: `app/models/agent_credential.rb`, `app/services/agents/gemini_cli_adapter.rb`_ (Confidence: High on our side, Medium on Kiro's telemetry specifics)

### Platform Feature Parity Matrix

Every capability our platform expects from a runtime, against what Kiro CLI provides. This is the answer to "does it support everything we have?"

| Platform capability | Kiro CLI | Verdict | Adapter surface |
| --- | --- | --- | --- |
| **MCP — stdio servers** | `mcpServers` with `command`/`args`/`env`/`disabled`, plus `autoApprove`, `disabledTools` | ✅ Parity+ | `mcp_config`, `mcp_merge_strategy = :merge_json` |
| **MCP — remote HTTP/SSE + bearer** | `url` + `headers` with `${VAR}` interpolation; `oauth`/`oauthScopes` documented | ✅ Parity+ | same |
| **MCP — internal `aixle-tools`** | Bearer-token HTTP server → covered by `headers` | ✅ | same |
| **MCP — remote OAuth dance** | Schema documents it; issue #7525 disputes it | ⚠️ Unverified | n/a for v1 |
| **MCP startup failure detection** | `--require-mcp-startup` → exit 3 | ✅ Better than most | `session_command` |
| **Skills — catalog install** | Agent Skills standard; `~/.kiro/skills/`, `.kiro/skills/` | ✅ Parity | `skills_install_path` |
| **Skills — private hand-written** | Same dirs, written directly | ✅ Parity | `skills_install_path` |
| **Skills — `npx skills add -a <id>`** | skills.sh lists a Kiro CLI agent; flag value unpublished | ⚠️ Verify id | `skills_agent_name` |
| **Skills — slash-command invocation** | Yes, `/`-commands + description auto-match | ✅ Parity+ | — |
| **Persona / system prompt** | Custom agent JSON `prompt` + `model` + `resources` | ✅ Parity+ (first-class, not a filename convention) | `config_files` |
| **Context file** | `AGENTS.md` at workspace root and subdirs | ✅ Parity | `context_file_path` |
| **Project standards injection** | `.kiro/steering/*.md`, always loaded on CLI (inclusion modes IDE-only) | ✅ Extra surface | optional |
| **Auth — API key** | `KIRO_API_KEY` (`ksk_…`), Pro+ tiers, org toggle | ✅ | `default_env_vars` |
| **Auth — interactive login capture** | Device flow + social/Builder ID/IdC exist, but the credential is **SQLite** | ⚠️ Possible, expensive | Phase 3 |
| **Auth — token refresh sweep** | No documented refresh endpoint | ❌ Gap | keep out of `REFRESHABLE_AGENT_TYPES` |
| **Auth — BYO cloud (Bedrock/Vertex)** | Absent; 3 open feature requests | ❌ Gap | — |
| **Model — selection** | Fixed catalog + `Auto`; **`chat --model <M>`** | ✅ Parity | `session_command` |
| **Model — programmatic list** | `chat --list-models --format json`, but only in-container | ⚠️ Wrong seam for `fetch_available_models` | — |
| **Usage — tokens** | Not emitted; credits only | ❌ Gap | `ingest_usage` |
| **Usage — cost in cents** | Credits, no published bundled-rate | ❌ Gap → `cost_cents` null in v1 | `collect_usage` |
| **Usage — structured run events** | `stream-json` JSON Lines with `kiro.dev/metadata` (credits, context) — **headless only** | ⚠️ Headless only | Phase 2 |
| **Usage — OTLP export** | Not documented | ❌ Gap | — |
| **Quota / credit-exhaustion detection** | Exit 1, indistinguishable from other failures | ⚠️ Text match needed | quota scan |
| **BMAD injection** | Kiro CLI listed among BMAD's supported tools | ✅ Likely, id unverified | `AGENT_TYPE_TO_BMAD_TOOL` |
| **Interactive TUI in tmux/ttyd** | Default experience since 2.0 | ✅ Parity | `SESSION_COMMANDS` |
| **Headless one-shot for workflow steps** | `chat --no-interactive --trust-all-tools` | ✅ Required — the TUI ignores the prompt (Appendix C) | `session_command` |
| **Session resume** | `--resume`, `--resume-id`, `--list-sessions` | ✅ Extra | — |
| **Container / non-root install** | Documented, DevContainer-proven | ✅ | Dockerfile |
| **Hooks** | Global hooks (2.13), standalone JSON in V3 | ➖ Unused by us | — |
| **Powers** | IDE-only; CLI "planned" | ➖ Irrelevant | — |
| **ACP programmatic drive mode** | `kiro-cli acp`, JSON-RPC 2.0 over stdio | ➕ Extra surface we don't use | Phase 4 |

**Reading of the matrix.** Everything on the *context and tooling* side — MCP, skills, persona, context files, BMAD — is at parity or better; Kiro's custom-agent JSON and its MCP schema are richer than what we emit for any current runtime. Every gap is on the *accounting and credential* side: no token/cost telemetry, no model-list API, no refresh endpoint, no BYO cloud. That shape is what makes the API-key model the right v1: the gaps that remain are ones we can document rather than engineer around.

---

## Architectural Patterns and Design

### The Platform's Runtime Extension Points (as-built)

A runtime in this codebase is not one object; it is a name that must be registered in five layers. Audited on `fix/board-activity-workflow-cancelled`, 2026-08-28:

| Layer | Artifact | What it holds |
| --- | --- | --- |
| **Identity** | `CompanyMembership::AVAILABLE_AGENTS` (`app/models/company_membership.rb:15`) | The canonical `%w[claude_code cursor_cli codex gemini_cli]` list; `AgentCredential` validates inclusion against it |
| | `TerminalSession` `enumerize :agent_type` (`app/models/terminal_session.rb:48`) | Session-level validation |
| | `AgentCredential::REFRESHABLE_AGENT_TYPES` (`app/models/agent_credential.rb:42`) | Which runtimes the Temporal refresh sweep touches |
| **Behaviour** | `Agents::BaseAdapter` subclass in `app/services/agents/` | Config paths, auth completion, credential extraction, config generation, session command, MCP config, context file, usage ingest |
| | `AgentCredentialsService::ADAPTERS` (`app/services/agent_credentials_service.rb:6-11`) | Name → adapter class registry |
| **Container** | `ContainerStrategies::AgentBaseStrategy` (`app/services/container_strategies/agent_base_strategy.rb:12-33`) | `VALID_AGENT_TYPES`, `DEFAULT_AGENT_IMAGES`, `AUTH_COMMANDS`, `SESSION_COMMANDS` |
| | `config/settings.yml:205-210` (+ `production.yml`, `staging.yml`) | Per-environment image references via `AGENT_IMAGE_*` env vars |
| | `docker/<runtime>/Dockerfile`, `Makefile: build-agents`, `.github/workflows/images.yml` | The image itself and its build/publish path |
| **Integrations** | `BmadMethodInjector::AGENT_TYPE_TO_BMAD_TOOL` (`app/services/bmad_method_injector.rb:9-14`) + `BMAD_HIDDEN_PATHS` | BMAD install flag per runtime |
| | Adapter `skills_install_path` / `skills_agent_name` | Skills catalog install target |
| **Presentation** | `app/frontend/shared/ui/types.ts:1` — the `AgentType` union | The FE type gate; everything else keys off it |
| | ~20 label/colour/logo maps across pages (see checklist) | Human-facing naming |
| | `AGENT_BRAND_COLORS` (`app/frontend/shared/theme/vendorColors.ts:17-22`), `shared/ui/agent-logos/` | Brand identity assets |
| | `app/frontend/pages/Docs/data/pages/{runtimes,agents,cli-ref,what-is-aixle}.md`, `searchIndex.ts` | In-product docs |

_Design observation: there is **no single registry object**. The runtime list is duplicated in at least eight backend constants and one frontend union, plus ~20 presentational maps. That duplication is the real cost of adding a runtime, and it is what the playbook at the end of this document targets._ (Confidence: High — direct inspection)

### Candidate Architectures, Compared

**Option A — API-key runtime (`KIRO_API_KEY`).**
The user pastes a `ksk_…` key on their profile; it is stored per (user, company) and injected as an env var at container start. No auth container, no credential scraping, no refresh.
_Precedent in-tree: `gemini_cli`. Effort: low. Coupling to Kiro internals: none._
_Cost: requires the user to hold a paid Pro-or-better seat and, on Enterprise, an admin who has enabled key generation._

**Option B — Device-flow login capture.**
An auth container runs `kiro-cli login --use-device-flow`; the user reads the URL + code from the ttyd terminal; on completion we scrape credentials and store them.
_Precedent in-tree: `claude_code`. Effort: high — the credential is a SQLite database, so completion detection and blob round-tripping both need new machinery (see Integration Patterns). Coupling to Kiro internals: high and undocumented — a schema change in `data.sqlite3` silently breaks it._
_Upside: works on the free tier and on any org that refuses to enable API keys._

**Option C — BYO-Bedrock.**
Not available. Three open feature requests, nothing shipped.
_Verdict: excluded on fact, not on preference._

**Option D — Platform-brokered / pooled account.**
A platform-owned Kiro subscription serving many users.
_Verdict: excluded — "each developer needs their own subscription," and pooling would also collide with our own per-company billing invariant on `AgentCredential`._

**Recommendation: Option A first, Option B only on demonstrated demand.** A delivers a working runtime against a documented, vendor-sanctioned automation surface with the lowest coupling to undocumented internals. B doubles the work and stakes it on an undocumented SQLite schema.

### Recommended Target Design

```
TerminalSession(agent_type: "kiro_cli")
  → ContainerStrategies::AgentSessionStrategy
      image:   Settings.agents.images.kiro_cli  → aixle/kiro-cli:latest
      env:     KIRO_API_KEY (from AgentCredential.config_data["api_key"])
      cmd:     kiro-cli  (interactive)  |  kiro-cli chat --no-interactive … (workflow step)
  → Agents::KiroCliAdapter
      config_files:  ~/.kiro/agents/aixle.json      ← persona (prompt/model/resources)
                     ~/.kiro/settings/mcp.json      ← MCP servers incl. aixle-tools
      context_file:  /workspace/AGENTS.md           ← referenced via resources[]
      usage:         credits from stream-json (headless) / none (interactive, v1)
```

Key design decisions and their rationale:

1. **No auth container for v1.** `AUTH_COMMANDS["kiro_cli"]` is still required by `AgentBaseStrategy`'s `fetch`, so register a value, but the profile flow is the API-key form, mirroring `gemini_cli`.
2. **Not refreshable.** Keep `kiro_cli` out of `REFRESHABLE_AGENT_TYPES`; leave `expires_at` nil. The Temporal sweep then ignores it, which is correct because there is no refresh endpoint.
3. **Persona through `~/.kiro/agents/aixle.json`, not a magic Markdown filename.** It is the vendor's own first-class mechanism, it carries the model choice, and it lets `resources` point at our assembled context files.
4. **Pin the CLI version and the engine in the image.** `--v3` changes the permission model and the session format; an unpinned `curl | bash` would silently move both.
5. **`cost_cents` stays null in v1.** Record credits in `events_data`; do not invent a credits→cents rate. Revisit once the credit metadata is observed end to end.

### Scalability and Performance

- The runtime inherits the existing per-session container model: no new orchestration, no new scaling axis. Sizing is governed by the existing agent pod requests (2Gi / 500m).
- Image weight is the one real risk: our base image already carries ttyd, OpenVSCode Server, Node 22, uv/pipx and the MITM logger, and the image-slimming work brought `claude-code` from 5.35 GB to 2.09 GB. `kiro-cli` adds a single static-ish binary via the install script — cheap relative to an npm global install — **provided** the install runs as the agent user in one layer and no recursive `chown` follows it (the documented cause of ~1 GB of layer duplication in the earlier audit).
- Concurrency is bounded by the user's credit balance, not by us. Credit exhaustion surfaces as exit 1 with no distinct code, so a session can fail late and opaquely.

_Sources: repository `docker/base/Dockerfile`, `docs/research/technical-agent-image-size-audit-2026-08-04.md`, memory of agent pod sizing_ (Confidence: High)

### Deployment and Operations

- Image build joins `Makefile: build-agents` and the matrix in `.github/workflows/images.yml` (`image_suffix: kiro-cli`, `dockerfile: ./docker/kiro-cli/Dockerfile`), publishing `ghcr.io/aixle/aixle-app-kiro-cli`.
- `config/settings.yml`, `production.yml`, `staging.yml` each need a `kiro_cli:` image entry with an `AGENT_IMAGE_KIRO_CLI` override.
- Prod rollout follows the existing two-push rule: `main` for web, `main-images` for agent images.
- Smoke test in the image build: `kiro-cli --version` and `kiro-cli doctor --strict`.

---

## Implementation Approaches and Technology Adoption

### Technology Adoption Strategy

Land it the way `gemini_cli` was landed — as an additive runtime behind the existing abstractions, with no migration and no change to the other four. Phased, so the legal gate and the telemetry unknowns can each stop the line without wasting the rest:

**Phase 0 — Clear the gate (blocking, days).**
Obtain written confirmation from Kiro/AWS that a hosted platform running unmodified `kiro-cli` in a per-user container with that user's own API key counts as permitted "automation in software development" and not a "third-party automation harness." Everything below is conditional on this.

**Phase 1 — Runtime lands (API-key model).**
Image, adapter, registry entries, profile credential form, FE type + labels + logo, docs. Definition of done: a user with a Pro seat can paste a key, start an interactive session, and drive `kiro-cli` in the terminal, with MCP tools connected.

**Phase 2 — Workflow steps and telemetry.**
Headless `--no-interactive --output-format stream-json` for workflow-step runs; parse `kiro.dev/metadata` for credits; decide the credits→`cost_cents` policy with real data in hand; wire quota-error text matching.

**Phase 3 (optional, demand-gated) — Device-flow login.**
Only if free-tier or API-key-disabled orgs turn out to matter. Requires solving SQLite completion-detection and blob round-tripping.

**Phase 4 (optional) — ACP drive mode.** A new, vendor-blessed programmatic surface for the whole platform, not a Kiro-specific feature.

### Complete Touch-Point Checklist

Every location that hard-codes the runtime list today. Verified by `grep -rln "cursor_cli\|gemini_cli"` on 2026-08-28.

**Backend — identity and validation**

- [ ] `app/models/company_membership.rb:15` — add to `AVAILABLE_AGENTS`
- [ ] `app/models/terminal_session.rb:48` — add to `enumerize :agent_type`
- [ ] `app/models/agent_credential.rb:42` — **do not** add to `REFRESHABLE_AGENT_TYPES`
- [ ] `app/dashboards/agent_credential_dashboard.rb:11,53` — admin filter collection + scope

**Backend — behaviour**

- [ ] `app/services/agents/kiro_cli_adapter.rb` — new adapter (see shape below)
- [ ] `app/services/agent_credentials_service.rb:6-11` — register in `ADAPTERS`
- [ ] `app/services/container_strategies/agent_base_strategy.rb:12-33` — `VALID_AGENT_TYPES`, `DEFAULT_AGENT_IMAGES`, `AUTH_COMMANDS`, `SESSION_COMMANDS`
- [ ] `app/services/bmad_method_injector.rb:9-14` — BMAD tool mapping (or an explicit "BMAD unsupported on this runtime" decision) + `BMAD_HIDDEN_PATHS` if it writes a dot-dir

**Config and images**

- [ ] `config/settings.yml:205-210`, `config/settings/production.yml`, `config/settings/staging.yml` — `kiro_cli:` image entry
- [ ] `docker/kiro-cli/Dockerfile` — new image on `aixle/agent-base-core`
- [ ] `Makefile: build-agents` — build line
- [ ] `.github/workflows/images.yml:184-191` — matrix entry (`image_suffix: kiro-cli`)

**Frontend — type gate and presentation**

- [ ] `app/frontend/shared/ui/types.ts:1` — extend the `AgentType` union
- [ ] `app/frontend/shared/theme/vendorColors.ts:17-22` — `AGENT_BRAND_COLORS.kiro_cli`
- [ ] `app/frontend/shared/ui/agent-logos/kiro.png` — logo asset
- [ ] `app/frontend/shared/components/SessionNewForm.tsx:66,73` — option + colour
- [ ] `app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx:38,45` — label + colour
- [ ] `app/frontend/pages/Projects/Sessions/SessionsPage.tsx:55,130`
- [ ] `app/frontend/pages/Projects/Workflows/SessionEditorPanel.tsx:339`
- [ ] `app/frontend/pages/Projects/AixleBuilder/{LandingPage,SessionPage}.tsx`
- [ ] `app/frontend/pages/Projects/Analytics/AnalyticsPage.tsx:168,184,201,209` — chart colour, logo, chip sizing
- [ ] `app/frontend/pages/Company/Analytics/AnalyticsPage.tsx:116,127,144,152`
- [ ] `app/frontend/pages/Company/Sessions/Index.tsx:55,101`
- [ ] `app/frontend/pages/Profile/Show.tsx:90-93`, `app/frontend/pages/Profile/Usage.tsx:121`
- [ ] `app/frontend/pages/Onboarding/OnboardingPage.tsx:90`
- [ ] Regenerate `app/frontend/types/generated/*` (Typelizer) after the resource change

**Docs (repo rule: `docs/index.md` updated in the same change)**

- [ ] `app/frontend/pages/Docs/data/pages/runtimes.md` — table rows, credentials row, cost-tracking caveat ("four" → "five" throughout)
- [ ] `app/frontend/pages/Docs/data/pages/agents.md:29`, `what-is-aixle.md:38`, `cli-ref.md:46`
- [ ] `app/frontend/pages/Docs/data/searchIndex.ts:31`
- [ ] `docs/user-guide/{runtimes,agents}.md`, `docs/reference/cli.md`, `docs/project/context.md`, `references/aixle-system-reference.md`
- [ ] `docs/index.md` — index this research document

**Tests (per `docs/testing.md`)**

- [ ] `test/services/agents/kiro_cli_adapter_test.rb` — new, mirroring `gemini_cli_adapter_test.rb`
- [ ] `test/services/agent_credentials_service_test.rb` — registry resolution
- [ ] `test/models/company_membership_test.rb`, `test/models/agent_credential_test.rb` — inclusion validation
- [ ] `test/integration/container_workflow_integration_test.rb:24,205` — `AGENT_TYPES` + the credential-shape assertion branch
- [ ] `test/services/container_strategies/agent_{auth,session}_strategy_test.rb` — image/command resolution
- [ ] `test/services/bmad_e2e_all_runtimes_test.rb` — the "all runtimes" sweep
- [ ] `test/factories/agent_credentials.rb`, `db/seeds.rb:123`
- [ ] FE: `SessionNewForm.test.tsx`, `Analytics*.test.tsx`, `Profile/*.test.tsx`, `Sessions/*.test.tsx` — the fixtures that enumerate runtimes

### Adapter Shape (the only genuinely new code)

```ruby
module Agents
  class KiroCliAdapter < BaseAdapter
    def home_dir = "/home/kiro"

    # API-key model: no scraped config file. The credential is a pasted ksk_ key.
    def config_path      = "#{home_dir}/.kiro/settings/mcp.json"
    def auth_required_keys = %w[__present__]

    def extract_credentials(_content) = {}

    def config_files(credentials, workflow_config = {})
      {
        "#{home_dir}/.kiro/agents/aixle.json"   => agent_config(credentials, workflow_config).to_json,
        "#{home_dir}/.kiro/settings/mcp.json"   => { mcpServers: {} }.to_json
      }
    end

    # Interactive TUI for sessions; one-shot headless for workflow steps.
    def session_command(mode:, prompt: nil, model: nil)
      return "kiro-cli" unless mode.to_s == "workflow_step"

      %(kiro-cli chat --no-interactive --trust-all-tools --agent aixle --output-format stream-json)
    end

    def context_file_path = "/workspace/AGENTS.md"   # referenced from agent resources[]
    def mcp_config(servers) = { "#{home_dir}/.kiro/settings/mcp.json" => … }
    def default_env_vars(session) = { "KIRO_API_KEY" => …, "OTEL_RESOURCE_ATTRIBUTES" => … }
  end
end
```

_Sketch, not final code — the point is that every method maps onto an existing `BaseAdapter` hook, so the abstraction holds without modification._

### Testing and Quality Assurance

Follow `docs/testing.md` doctrine: never stub the class under test, no `any_instance`, and no vendor-gem mocking — test the adapter directly and drive the container layer through `test/support/fakes/fake_runtime.rb`. The adapter tests are pure input/output over config generation and command building, which is where nearly all the new logic lives. The image itself is verified by a build-time smoke test (`kiro-cli --version`, `kiro-cli doctor --strict`), not by the Rails suite.

Before any push: `docker compose exec -T web make check_all` (never two backend suites at once; in a worktree, symlink `node_modules` to the repo root first).

### Cost and Resource Management

- **Platform cost:** one more image in GHCR and in every node's image cache; no new services.
- **User cost:** a paid Kiro seat ($20/month minimum) is a hard prerequisite, because the free tier cannot mint an API key. This must be stated in the runtime docs and in the profile form's help text, or support tickets are guaranteed.
- **Runaway protection:** credit exhaustion is invisible to exit codes. Add a text matcher to the quota-error scan and surface "out of Kiro credits" as a distinct session-failure reason.

### Risk Assessment and Mitigation

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Kiro/AWS reads a hosted multi-tenant platform as a prohibited harness | Medium | **Fatal to the runtime** | Phase 0 written confirmation before any code lands |
| API-key generation disabled by the customer's Kiro admin | Medium | User cannot onboard | Document the admin toggle; show a precise error, not "invalid key" |
| Free-tier users cannot use the runtime at all | High | Support noise | State the Pro prerequisite in-product |
| CLI upgrade changes storage/flags (V2 → V3 permission model) | High over 12 months | Sessions break | Pin the version in the image; treat engine choice as explicit; watch the changelog |
| `cost_cents` never populated → analytics gaps | High in v1 | Reporting inconsistency | Documented contract already covers null cost; record credits in `events_data` |
| Credit exhaustion surfaces as opaque exit 1 | High | Confusing failures | Text-match in quota scan |
| Remote-OAuth MCP unsupported | Medium | Some catalog servers unusable on this runtime | Bearer-token servers (incl. `aixle-tools`) are unaffected; verify before promising parity |

---

## Technical Research Recommendations

### Implementation Roadmap

1. **Phase 0 (blocking):** written permitted-use confirmation from Kiro/AWS.
2. **Phase 1 (~1 sprint):** `aixle/kiro-cli` image; `Agents::KiroCliAdapter`; the eight backend registry edits; the FE type + presentation set; profile API-key form; docs. Ship interactive sessions only.
3. **Phase 2:** headless workflow steps with `stream-json`; credits telemetry; quota-error matching; `cost_cents` policy decision informed by observed data.
4. **Phase 3 (demand-gated):** device-flow login capture, only if free-tier/no-API-key orgs prove to matter.
5. **Cross-cutting:** extract the duplicated runtime list into one registry (see playbook) — ideally during Phase 1, while the cost of the duplication is fresh.

### Technology Stack Recommendations

- **Credential model:** API key (`KIRO_API_KEY`). Do not attempt SQLite login capture in v1.
- **Engine:** pin V2 for launch (headless + `stream-json` are documented against it); plan a V3 migration once V3 becomes default, budgeting for `permissions.yaml` replacing `--trust-all-tools`.
- **Persona:** `~/.kiro/agents/aixle.json` with `prompt`, `model`, `resources` — not a Markdown filename convention.
- **Drive mode:** interactive TUI for sessions, headless one-shot for workflow steps, ACP deferred.

### Skill Development Requirements

None exotic. The work is Rails service objects, a Dockerfile, and TypeScript presentational plumbing — all patterns already in-tree. The one specialist need is whoever owns the vendor-terms conversation in Phase 0.

### Success Metrics and KPIs

- Phase 0: written vendor confirmation on file (binary).
- Phase 1: a Pro-seat user completes credential setup → interactive session → MCP tool call, with zero code changes outside the checklist.
- Phase 2: ≥95% of finished `kiro_cli` workflow-step runs carry a credits figure in `events_data`.
- Regression guard: `make check_all` green, and the "all runtimes" sweep (`bmad_e2e_all_runtimes_test.rb`) passes with five runtimes.
- Playbook validation: the *next* runtime after Kiro lands with a materially shorter checklist.

---

## Research Synthesis

### Executive Summary

Kiro CLI can now plausibly become the platform's fifth agent runtime — a reversal of this repository's own July 2026 conclusion, driven by two changes on Kiro's side rather than a re-reading of the same facts. First, Kiro's permitted-use terms were widened and now name, verbatim, "Kiro IDE, Kiro CLI, Kiro on the web, Kiro Crew, ACP compatible IDEs, and automation in software development (ex: reviews during CI/CD)" as sanctioned surfaces; the prohibition is narrower than it was read to be, targeting harnesses "that route requests outside of Kiro's native interfaces" — the `kiro-gateway`/`kirocc` pattern of replaying stolen credentials against Kiro's backend, not the pattern of launching the vendor's own binary. Second, Kiro CLI 2.0 (2026-04-13) shipped the headless surface such automation requires: `--no-interactive`, `KIRO_API_KEY`, `--trust-tools`, `--output-format stream-json`, documented exit codes, and an enterprise governance switch whose stated purpose is "executing automation scripts with Kiro CLI in their local machine or remote environment like CI/CD pipelines."

What has not changed is the commercial shape. There is still no BYO-Bedrock (three open, unshipped feature requests), so this is a product integration and not a Bedrock-consumption play; the billing unit is credits, not tokens; seats are per-individual and explicitly non-shareable, which rules out any pooled platform account but fits our per-(user, company) `AgentCredential` model exactly; and API keys exist only for Pro and above, gated a second time by an org-level admin toggle that is off by default. The practical entry price for a Kiro user on our platform is a $20/month seat.

Engineering-wise the integration is ordinary except for two facts. Kiro CLI keeps its login in a **SQLite database** (`~/.local/share/kiro-cli/data.sqlite3`), not a JSON file — which is incompatible with our JSON-shaped adapter contract and with the container watcher's key-presence check, and which makes the API-key model not merely easier but the only low-risk path. And Kiro reports **credits**, not tokens or cents, so `cost_cents` needs a policy decision rather than a parser; the honest v1 behaviour is to record credits and leave cost null, which our own docs already define as a legitimate state. Everything else — image, adapter, persona injection via `~/.kiro/agents/*.json`, MCP via `~/.kiro/settings/mcp.json`, interactive TUI in tmux/ttyd — maps onto existing abstractions without modifying them.

**Key Technical Findings:**

- Permitted-use terms now explicitly cover Kiro CLI plus software-development automation; the prohibition targets credential-replaying gateways, which is not our architecture. Legal confirmation is still the sensible gate (Confidence: High on the quotes, Medium on how a vendor would read a hosted multi-tenant platform).
- Headless mode is production-shaped: `KIRO_API_KEY`, `--no-interactive`, `stream-json` with `kiro.dev/metadata` credits events, exit codes 0/1/3.
- Credentials live in SQLite, not JSON — the single biggest architectural constraint, and the reason to choose the API-key model.
- No BYO-Bedrock; credits are the unit of account; seats are per-individual and non-shareable.
- Kiro's custom-agent JSON (`prompt`, `model`, `resources`, `permissions`) is a *better* persona surface than the Markdown-filename convention we use for the other runtimes.
- **Feature parity splits cleanly along one line** (see the Parity Matrix): everything context- and tooling-shaped is at parity or better — MCP (`headers` with `${VAR}`, `oauth`, `autoApprove`, `disabledTools`), Agent-Skills-standard skills in `~/.kiro/skills/`, `AGENTS.md`, always-loaded `.kiro/steering/`, BMAD support, slash-command skill invocation, session resume — while every gap is accounting- or credential-shaped: no token/cost telemetry, no programmatic model list, no refresh endpoint, no BYO cloud.
- Our platform has no runtime registry — the list is duplicated across eight backend constants, one FE union, and ~20 presentational maps. That duplication, not Kiro, is the bulk of the work.

**Technical Recommendations:**

1. Gate on a written permitted-use confirmation from Kiro/AWS before writing code.
2. Implement the **API-key model** (`KIRO_API_KEY`); do not attempt SQLite login capture in v1.
3. Pin the CLI version and engine (V2) in `docker/kiro-cli/Dockerfile`; plan explicitly for the V3 permission-model migration.
4. Inject persona via `~/.kiro/agents/aixle.json`; keep `kiro_cli` out of `REFRESHABLE_AGENT_TYPES`; leave `cost_cents` null in v1 and record credits in `events_data`.
5. Collapse the duplicated runtime list into a single registry while adding the fifth entry — the marginal cost is small now and compounds later.

### Table of Contents

1. Technical Research Introduction and Methodology
2. Technical Landscape and Architecture Analysis — *Technology Stack Analysis* above
3. Implementation Approaches and Best Practices — *Implementation Approaches* above
4. Technology Stack Evolution and Current Trends — *Release Timeline*, *Billing Model*
5. Integration and Interoperability Patterns — *Integration Patterns Analysis* above
6. Performance and Scalability Analysis — *Scalability and Performance*
7. Security and Compliance Considerations — *Security Posture*, *Permitted-Use Boundary*
8. Strategic Technical Recommendations — *Technical Research Recommendations*
9. Implementation Roadmap and Risk Assessment — *Roadmap*, *Risk Assessment*
10. Future Technical Outlook — *below*
11. Research Methodology and Source Verification — *below*
12. Appendices: the Add-a-Runtime Playbook, open verification items, sources — *below*

### Future Technical Outlook

**Near term (0–6 months).** V3 becomes the default engine, which breaks the trust-flag model and the session format; any Kiro integration must budget for that migration rather than treat it as maintenance. Kiro Crew's Apache-2.0 orchestration layer is a live competitive question — it does, in the open, some of what our workflow engine does, while keeping the agent proprietary.

**Medium term (6–18 months).** BYO-key/BYO-Bedrock is the single change that would move Kiro from "another product runtime" to "a Bedrock-consumption vehicle," and it has visible demand across three issues. If it ships, the July 2026 Bedrock research should be re-opened, not this document. ACP maturing across editors makes a protocol-level drive mode more attractive than terminal-driving for every runtime — a platform-wide architectural option, not a Kiro feature.

**Long term.** The strategic question is whether per-vendor runtimes remain the unit of integration at all, or whether ACP (agent side) plus MCP (tool side) reduce a "runtime" to a config entry. Our own duplication problem is an argument for preparing that future now.

### Research Methodology and Source Verification

**Methodology.** Six-step BMAD technical-research workflow (scope → stack → integration → architecture → implementation → synthesis), executed 2026-08-28 against live vendor documentation and this repository. Every non-trivial claim carries a confidence level; conflicts are surfaced rather than resolved (notably MCP-OAuth support, where changelog 2.11 and issue #7525 disagree). Claims about Kiro's on-disk credential storage come from third-party tooling that reads it, not vendor docs, and are marked Medium-High accordingly.

**Primary sources (fetched live 2026-08-28):** kiro.dev — `/docs/cli/`, `/docs/cli/headless/`, `/docs/cli/acp/`, `/docs/cli/v3/`, `/docs/getting-started/authentication/`, `/docs/custom-agents/`, `/docs/mcp/`, `/docs/mcp/configuration/`, `/docs/reference/cli-commands/`, `/docs/reference/exit-codes/`, `/docs/enterprise/governance/api-keys/`, `/docs/billing/related-questions/`, `/pricing/`, `/changelog/cli/`, `/blog/introducing-headless-mode/`, `/blog/one-agent/`.
**Secondary sources:** `kirodotdev/Kiro` issues #695, #1067, #7525, #9367; `jwadow/kiro-gateway`; `d-kuro/kirocc`; Forbes (2026-08-06) on Kiro Crew; DevelopersIO DevContainer and headless write-ups; Arm install guide.
**Repository evidence:** `app/models/{agent_credential,company_membership,terminal_session}.rb`, `app/services/agents/*`, `app/services/agent_credentials_service.rb`, `app/services/container_strategies/agent_{base,auth}_strategy.rb`, `app/services/bmad_method_injector.rb`, `config/settings*.yml`, `docker/{base,gemini-cli}/Dockerfile`, `Makefile`, `.github/workflows/images.yml`, `app/frontend/shared/{ui/types.ts,theme/vendorColors.ts}`, `app/frontend/pages/Docs/data/pages/runtimes.md`.
**Prior art superseded in part:** `docs/planning-artifacts/research/technical-aws-bedrock-agentic-cli-integration-research-2026-07-24.md` — its Kiro disqualification stands for *Bedrock consumption* but no longer for *product integration*.

**Limitations.** The harness is closed-source, so no claim here rests on reading Kiro's code. API-key scope, expiry and rotation are undocumented. The `stream-json` event catalogue is not enumerated by the vendor; the credits-metadata detail comes from secondary coverage and must be verified by observation. No `kiro-cli` binary was executed during this research — every runtime behaviour is documentation-derived and needs a spike to confirm.

### Appendix A — Playbook: Adding Any New Agent Runtime

Generic, runtime-agnostic. Kiro is the worked example; the sequence holds for the next one.

**1. Qualify before building.**
Answer four questions in writing: (a) do the vendor's terms permit a hosted platform running the CLI on a user's behalf? (b) is there a non-interactive/headless mode? (c) can a credential be supplied without an interactive browser login — API key or device flow? (d) does it emit usage telemetry, and in what unit? A "no" on (a) stops the work; a "no" on (d) means `cost_cents` stays null and the docs must say so.

**2. Choose the credential model.** API key (cheapest — `gemini_cli` precedent) → device-flow login capture (`claude_code` precedent) → nothing else. If the credential is not a readable JSON file, the login-capture path costs several times more; prefer the key.

**3. Register the identity** — `CompanyMembership::AVAILABLE_AGENTS`, `TerminalSession` enumerize, `AgentCredential::REFRESHABLE_AGENT_TYPES` (only if a real refresh endpoint exists), `agent_credential_dashboard`.

**4. Write the adapter** — subclass `Agents::BaseAdapter`, implement `home_dir`, `config_path`, `auth_required_keys`/`auth_complete?`, `config_files`, `session_command`, `context_file_path`, `mcp_config`, `default_env_vars`; register in `AgentCredentialsService::ADAPTERS`.

_Picking the auth-completion signal (step 4's one real decision)._ The watcher offers three modes, in order of preference: a **JSON dotted key** (`oauthAccount.accountUuid`) when the credential is a document; **`__contains__:<text>`** when it is not, and some literal text appears in its bytes only after a successful login; **`__present__`** (file exists and is non-empty) only when the file itself is created by the login and by nothing else. Before choosing, measure the file in all **three** states — never logged in, mid-flow with the code on screen, and logged in — because the dangerous one is the middle: a runtime that writes a device registration as soon as it shows the code will trip `__present__` and close the auth terminal while the user is still approving in their browser. And prefer a marker from the token's own payload (`access_token`) over the name of whatever record holds it: record names tend to be derived from the login method the user picked, and gating on one silently discards logins made another way.

**5. Build the image** — `docker/<runtime>/Dockerfile` on `aixle/agent-base-core`; agent user via `useradd -m -d /home/<runtime> -G ${AGENT_BROWSERS_GROUP}`; install the CLI in **one** layer with its cache clean; **no recursive `chown` after a large install**; pin the version; add `Makefile: build-agents` and the `.github/workflows/images.yml` matrix entry; add image settings to `settings.yml` + `production.yml` + `staging.yml`.

**6. Wire the container strategy** — `VALID_AGENT_TYPES`, `DEFAULT_AGENT_IMAGES`, `AUTH_COMMANDS`, `SESSION_COMMANDS`.

**7. Extend the FE type gate first** — `AgentType` in `shared/ui/types.ts`; then let `tsc` enumerate every map that must be updated. This is the cheapest exhaustive-search tool available; do not hand-hunt the presentational maps.

**8. Add brand assets** — `AGENT_BRAND_COLORS`, `shared/ui/agent-logos/<vendor>.png`, analytics chart colour and chip sizing.

**9. Update docs in the same change** — `Docs/data/pages/{runtimes,agents,cli-ref,what-is-aixle}.md`, `searchIndex.ts`, `docs/user-guide/*`, `docs/reference/cli.md`, and `docs/index.md`.

**10. Tests** — a new adapter test mirroring the nearest precedent, plus the fixtures that enumerate runtimes (`container_workflow_integration_test.rb`, `bmad_e2e_all_runtimes_test.rb`, factories, seeds, FE test fixtures). Finish with `docker compose exec -T web make check_all`.

**11. The structural fix.** Steps 3, 6 and 7 exist only because the runtime list is duplicated. A single registry — one Ruby object exposing name, image, commands, adapter and brand metadata, serialized once to the frontend — would collapse them into one edit. Every additional runtime pays for this omission; the fifth is a reasonable moment to fix it.

### Appendix D — The Model Catalogue and Usage API (measured)

Read off the shipping binary and probed directly, 2026-08-28. Kiro publishes **no
public models endpoint**: what exists is a private AWS-SDK service inherited from
CodeWhisperer, `codewhisperer.<region>.amazonaws.com`, spoken as
`application/x-amz-json-1.0` with `X-Amz-Target` and `httpBearerAuth` (client crate
`amzn-codewhisperer-client`). Probed without credentials it answers:

    {"__type":"com.amazon.aws.codewhisperer#ValidationException",
     "message":"Missing bearer token in the authorization header."}

Operations present in the binary: `ListAvailableModels`, `GetUsageLimits`,
`GenerateAssistantResponse`, `SendMessage`, `ConverseStream`, `ListAvailableProfiles`,
`CreateSubscriptionToken`, `SendTelemetryEvent`.

`GetUsageLimits` is where cost lives, in both currencies: `current_usage`,
`total_usage_limit`, **`percent_used`**, `next_date_reset`, `usage_breakdown` (by
`AgenticRequest` / `CodeCompletions` / `Transform`), `subscription_info`,
`overage_configuration`. Per-request telemetry carries `creditsUsed`,
`overageCreditsUsed` and `modelId`; subscription tiers enumerate as
`PRO / PRO_MAX / POWER / POOLING` with `overageEnabled` and `overageCap`.

**The catalogue is per account and the docs are wrong about it.** A live Pro account
returned `auto` (1.0x), `claude-sonnet-4.5` (1.3x), `claude-sonnet-4` (1.3x),
`claude-haiku-4.5` (0.4x), `glm-5` (0.5x), `deepseek-3.2` (0.25x), `minimax-m2.5`
(0.25x), `minimax-m2.1` (0.15x), `qwen3-coder-next` (0.05x) — all `rate_unit: "Credit"`.
None of the models kiro.dev/docs/models lists (GPT-5.6 Sol/Terra/Luna, Claude Opus 5,
Sonnet 5) were present. A hard-coded catalogue in the adapter would therefore be wrong
for real users.

**Design consequence (revised 2026-09-11).** The first reading of the permitted-use
terms put calling this service from the Rails process on the wrong side of "route
requests outside of Kiro's native interfaces" — the `kiro-gateway`/`kirocc` pattern —
and the design fell back to `kiro-cli chat --list-models --format json` inside the
container. That constraint was lifted, so `#credit_usage` calls `GetUsageLimits`
server-side with the bearer read out of the stored credential: one read-only operation,
no request routing, real numbers per account.

**But the catalogue half of this does not survive v3, and the container route wins after
all.** On a live v3 account (`KIRO POWER`), `GetUsageLimits` answers 200 while
`ListAvailableModels` answers **403 `AccessDeniedException: "Your subscription does not
support this application"`** — for every `origin` value tried (`KIRO_CLI`, `CHAT`,
`AI_EDITOR`, `IDE`, `CLI`, `KIRO`, `CONSOLE`, `UNKNOWN`), so it is the operation, not the
header. The same credential in a container runs `kiro-cli --v3 chat --list-models
--format json` fine and returns a **larger** catalogue than the v2 API ever did — Opus 5,
Sonnet 5, Opus 4.8/4.7/4.6, the GPT-5.6 previews. The binary's own strings show why:
alongside CodeWhisperer it carries `management.<region>.kiro.dev`, so v3 gets its
catalogue from a different service. Chasing that endpoint would mean re-chasing it at
every engine change. `Agents::BaseAdapter#collect_credential_metadata` asks the CLI
instead, on the cleanup path of both the auth and the session strategy, and stores the
answer on the credential; the API call stays as the fallback for a credential captured
before that existed.

**Two tables, not one.** The bearer lives in `auth_kv`, but the `profileArn` every call
must carry is a row in the `state` table under `api.codewhisperer.profile`
(`{"arn":"arn:aws:codewhisperer:us-east-1:…:profile/XXXX","profile_name":…}`). Reading
only the token yields a record the API rejects. Its region is also not the identity
region: one account had `auth.idc.region = us-west-2` and a profile in `us-east-1`, and
the profile's is the one that answers.

Both calls send `{"origin":"KIRO_CLI","profileArn":…}` and the bearer from the
credential's `auth_kv` row. Measured token lifetime is **~1 hour**, which is shorter
than a long session — so the reading happens at cleanup, and
`AgentSessionStrategy#before_cleanup` now refreshes the credential *before* collecting
usage (an agent that rotates its token mid-session otherwise leaves a stale one behind,
and usage collection needs a live token to call the vendor). A reading taken at
container start would be made with an hour-old token and simply 403, so there is only
ever one reading per session, at cleanup: a session's cost is the movement of the
counter since the *previous* session's reading (`kiro_last_credits` on the credential).
The counter is per account, so anything else spending credits in between — a concurrent
session, or the user in the Kiro IDE — lands in the same figure. That is the known limit
of the measurement, and the reason the MITM log is still collected: `SendTelemetryEvent`
carries a per-request `creditsUsed` that can replace the delta once its shape has been
read off real traffic.

### Appendix C — As-Built Notes (implementation, same day)

The runtime was implemented on `feat/kiro-cli-runtime` after this research. What the
build measured or corrected:

- **Version and payload.** `kiro-cli 2.20.1`. The installer downloads a ~1.1 GB archive
  and unpacks three binaries: `kiro-cli` (100 MB), `kiro-cli-chat` (926 MB) and
  `kiro-cli-term` (77 MB). This is several times any other runtime's payload.
- **Image size.** A naive image came out at **4.04 GB** — the payload once, plus a second
  copy created by `chown -R … /home/kiro` (the exact layer-duplication failure the
  agent-image size audit documented). Dropping `/home/kiro` from the chown, removing
  `kiro-cli-term` (unused; the CLI runs without it) and stripping the remaining binaries
  brought it to **2.65 GB**. Grok, the next largest, is ~2.0 GB.
- **Device flow verified in a container.** `kiro-cli login --use-device-flow` prints
  `Code: XXXX-XXXX` and `https://view.awsapps.com/start/#/device?user_code=…` with no
  browser present — the shape our ttyd auth terminal already renders for other runtimes.
- **The SQLite hazard is real and observed.** `~/.local/share/kiro-cli/data.sqlite3` is
  created the moment the CLI starts, *before* any login. A file-presence watcher on it
  would close the auth container while the user was still entering the code. The login
  command therefore ends with `whoami` writing a marker via a temp file + rename.
- **`whoami` signed out returns valid JSON.** `{"account":null}` with exit code 1 — so
  the completion check must test for a named account, not for parseable JSON, and the
  marker must be renamed on success rather than written by a redirect.
- **BMAD supports Kiro first-class.** `bmad-method@6.11.0 install --list-tools` reports
  tool id `kiro` → `.kiro/skills`, which is the workspace skills directory Kiro CLI
  already reads. No Claude-compatibility detour is needed (unlike Grok).
- **Model flags.** `chat --model` and `chat --list-models --format json` both exist —
  see the Model Selection correction above.

_Source: the built `aixle/kiro-cli` image and container runs, 2026-08-28._ (Confidence: High — measured)

#### Corrections from the second implementation pass (2026-09-11)

Three of the notes above were wrong once the runtime met a real account. What replaced
them:

- **The `whoami` marker is gone; login is one command again.** The auth command was
  `kiro-cli login --use-device-flow && kiro-cli whoami --format json > …/aixle-auth.json`,
  so that the watcher had a JSON file with a named account to detect. Two things broke
  it. The marker file made the launch command a four-part shell compound the user had to
  read in the auth terminal, and — worse — the credential was gated on a byte marker
  (`kirocli:odic:token`) taken from third-party code and never verified. The real key
  name varies by login method (`kirocli:social:token` for a social login), so the gate
  never matched: the credential saved with only the identity file, the runtime *looked*
  configured, and every session started signed out. The auth command is now plain
  `kiro-cli login --use-device-flow` and `auth_file_paths` is `[state_path]`.
- **Completion IS detectable — from the token payload, not the row key.** The first
  implementation of the above concluded this runtime had no automatic signal at all and
  left `auth_required_keys` empty, which made the user close the auth terminal by hand.
  Measuring one container through all three states disproves that:

  | state | `kirocli:odic:device` row | `access_token` / `refresh_token` |
  | --- | --- | --- |
  | fresh container, no login | absent | absent |
  | device code on screen, not yet approved | **present** | absent |
  | login finished | present | **present** |

  The OAuth field names inside the stored token appear verbatim in the database's bytes
  and are identical whichever login method was used — unlike the row key, which is named
  after it and is what made the original gate unreliable. The watcher grew a third mode
  for this, `__contains__:<text>`; it had only `__present__` (file exists and is
  non-empty) and JSON dotted-key lookup, and both misfire on a binary file that exists
  before login. `Agents::KiroCliAdapter::AUTH_MARKERS` drives both the in-container
  check and its server-side twin in `#auth_complete?`, so the two cannot drift. Note the
  middle row: `__present__`, or any gate on the device-registration row, would close the
  auth terminal while the user was still approving in their browser.
- **Device-flow tokens are portable.** Open item 5a is closed: a login captured in one
  container's SQLite state is accepted when restored into a different container. The
  device registration is not host-bound.
- **No staging path or restore prefix is needed.** The original design copied the
  database in through a temp path with a `chmod`, on the assumption that container files
  would be root-owned and unreadable by the CLI user. Containers run entirely as root;
  the blob is written straight to `~/.local/share/kiro-cli/data.sqlite3`.

Also settled in this pass:

- **v3 engine.** `kiro-cli --v3 chat` is verified present on the shipping binary and is
  the version the platform launches. The flag is a constant (`V3_FLAG`) so the opt-in is
  one edit when it stops being an opt-in.
- **The prompt only arrives in `--no-interactive`, and that is not a preference.**
  `chat --help` documents a positional `[INPUT]` ("the first question to ask"), and every
  runtime here is driven that way — `AgentSessionStrategy` appends `"$AGENT_PROMPT"` to
  the launch command. **The interactive TUI ignores it, on both engines.** Measured in a
  real tmux pane with the trust confirmation pre-answered so nothing else could swallow
  it: the TUI comes up at an empty "ask a question or describe a task" and waits.
  Driving it externally does not work either — neither bracketed paste
  (`tmux paste-buffer -p`) nor literal keystrokes (`send-keys -l`) reach its input. A
  workflow step launched interactively therefore never receives its task and sits at
  `ready` until a watchdog closes it; with `--no-interactive` the same argument is
  consumed and answered. The cost is that an automatic session has no TUI to attach to,
  the same trade Antigravity's `--print` makes. Interactive sessions are unaffected —
  they carry no prompt.
- **V3 silently drops a plain-HTTP MCP server that is not on loopback.** This is the one
  finding that decides whether the runtime is usable at all: without MCP an automatic
  session cannot call `finish_session` and never ends. With
  `url: http://web:4002/action_mcp` the agent reported
  `{"error":"Power 'aixle-tools' is not installed"}` and listed no tools; the same server
  at `http://localhost:4002/action_mcp` produced `mcp_aixle_tools_finish_session` and
  `mcp_aixle_tools_fail_session`. The rule is in the CLI's own binary —
  `crates/agent/src/agent/mcp/mod.rs`: *"host must be 127.0.0.1 or localhost, got `web`"*
  — and matches the documented "`url`: HTTPS endpoint (or HTTP for localhost)". Nothing
  is logged when it rejects one, which is what made this take a live session to find.

  It affects every deployment, not just development: `MCP_SERVER_URL` is
  `http://web:4002/action_mcp` locally and `http://mcp.<namespace>.svc.cluster.local:4002/action_mcp`
  in staging and production — internal HTTP throughout. Rather than terminate TLS on an
  internal hop, the agent container forwards a loopback port to that address (the
  watcher's `MCP_FORWARD_PORT`/`MCP_FORWARD_TARGET`, inert for every other runtime) and
  `#mcp_config` rewrites the host it writes into `mcp.json`. An HTTPS or already-loopback
  URL passes through untouched.
- **The engine also decides how MCP is reached at all.** V3 asks Kiro's cloud for its
  tool list (`KiroRuntimeService.InvokeMCP`, `tools/list`, scoped by `profileArn`), which
  is why a rejected local server reads as "Power not installed" rather than as a
  connection error. Local servers still work — they are merged into that list — but only
  once they pass the loopback rule above. Neither a workspace-scoped
  `.kiro/settings/mcp.json`, a `powers.mcpServers` section, nor declaring the server
  inline on an agent config made any difference; the URL was the whole problem.
- **Pre-answered prompts.** Two interactive prompts blocked unattended sessions. The
  trust-all confirmation is pre-answered by seeding `~/.kiro/settings/cli.json` with
  `chat.disableTrustAllConfirmation` (confirmed by diffing the file after clicking "Yes,
  and don't ask again" in a live session); `app.disableAutoupdates` and
  `telemetry.enabled: false` are seeded alongside it. v3 additionally reads
  `~/.kiro/settings/permissions.yaml`, seeded with a single allow-all rule, matching the
  `--trust-all-tools` posture every other runtime already has in this sandbox.
- **OpenTelemetry has not shipped.** Checked against the report that it had: the request
  is issue #6319, still open and labelled `pending-maintainer-response`, with no
  changelog mention through 2.21.0. Nothing to integrate; usage stays on the credit
  delta above.
- **`sqlite3` gem added.** The adapter reads one credential format out of one file. It
  is not an application database and nothing else in the app may use it.

_Source: implementation and live-account runs on `feat/kiro-cli-runtime`, 2026-09-11._ (Confidence: High — measured)

### Appendix B — Open Verification Items

_Status as of 2026-09-11. Items closed by the implementation are marked **RESOLVED** and
kept rather than deleted, so the next reader can see what was actually settled by
measurement._

**RESOLVED:** 4b (BMAD tool id is `kiro` → `.kiro/skills`), 4c and 4d (the catalogue and
usage APIs were located and are now called directly — Appendix D), 5 (interactive-session
cost comes from the `GetUsageLimits` credit delta), 5a (device-flow tokens are portable
across containers), 6 (`auth_kv` layout read; the key name varies by login method, which
is why nothing is gated on it). Item 2 (API-key scope and rotation) no longer applies —
the runtime authenticates by device flow, not by API key. Item 1 is answered for this
deployment: use of these APIs was explicitly permitted.

Still open:

1. **Written permitted-use confirmation** for the hosted-platform case (blocking).
2. **API-key scope, expiry and rotation** — undocumented; ask, and design revocation UX to match.
3. **`stream-json` event catalogue** — confirm the `kiro.dev/metadata` shape and credits fields by observation before building a parser.
4. **Remote-OAuth MCP support** — reconcile changelog 2.11 and the documented `oauth`/`oauthScopes` fields against issue #7525; confirm `headers` + `${VAR}` injection works for bearer-token servers.
4a. **skills.sh agent id** for `npx skills add -a <id>` (the Kiro CLI agent page does not publish the flag value or install paths) — or confirm that writing directly to `~/.kiro/skills/` is sufficient, as it is elsewhere.
4b. **BMAD tool id** — read it from `npx bmad-method install --tool list`; add `.kiro/skills` to `BMAD_HIDDEN_PATHS` if the installer writes there.
4d. **Capture the CLI's own HTTP through the MITM proxy.** The adapter does not set
`MITM_TRACKED_DOMAINS` today, so no Kiro traffic is recorded. Turning it on answers two
open items at once: which endpoint the CLI calls for its model catalogue (which would let
`fetch_available_models` work server-side, the way the Codex adapter calls
`chatgpt.com/backend-api/codex/models`), and whether responses carry credit or token
counts that `cost_cents` could be derived from. Candidate hosts from what has been
observed so far: `kiro.dev`, `prod.download.cli.kiro.dev`, and the AWS identity hosts the
device flow used (`view.awsapps.com`); the log itself will give the real list.
4c. **Programmatic model list** — confirm no command/endpoint exists before hard-coding the catalogue in `fetch_available_models`; capture the credit multipliers, since those are what users need to compare.
5. **Interactive-mode telemetry** — determine whether anything usable is emitted without `stream-json`, or accept null cost for interactive sessions.
5a. **Device-flow token portability** — whether a login captured in one container's SQLite state is accepted when restored into a different container (device registration may be host-bound). This is the single assumption the as-built runtime rests on and only a real credential can settle it.
6. **SQLite schema** (only if Phase 3 is ever taken) — `auth_kv` key layout and its stability across CLI upgrades.
7. **Credits→cents policy** — bundled-credit effective rate differs per tier; decide before any cost figure is displayed.

---

## Technical Research Conclusion

### Summary of Key Technical Findings

Kiro CLI moved from "commercially disqualified" to "buildable, pending confirmation" between July and August 2026, because the vendor widened its permitted-use list to name the CLI and software-development automation explicitly, and because headless mode with API-key auth shipped in 2.0. The remaining obstacles are commercial rather than technical: no BYO-Bedrock, credits instead of tokens, per-individual non-shareable seats, and an API-key capability gated behind both a paid tier and an org admin toggle. Technically the only awkward fact is that the login lives in a SQLite database, which the API-key model routes around entirely.

### Strategic Technical Impact Assessment

Adding Kiro is a **product-breadth** move, not an economics move. It widens the runtime menu for teams already inside the AWS/Kiro ecosystem and costs one image plus one adapter, but it routes no attributable spend to a customer's Bedrock account and therefore contributes nothing to an AWS partnership motion. Judge it on user demand alone. The more durable outcome of this research is the diagnosis of our own duplication: five runtimes is where the absent registry starts to hurt.

### Next Steps Technical Recommendations

1. Open the vendor conversation for Phase 0 confirmation — everything else is downstream of it.
2. In parallel (no vendor dependency), run a one-day spike: install `kiro-cli` in a scratch image, authenticate with a Pro API key, run `chat --no-interactive --output-format stream-json`, and capture the actual event stream. That closes verification items 3 and 5 with facts.
3. Decide the registry refactor question before Phase 1 starts, not during it.
4. If Phase 0 is refused, publish that outcome as a short addendum here — the negative result is what stops this from being re-researched a third time.

---

**Technical Research Completion Date:** 2026-08-28
**Research Period:** Current comprehensive technical analysis (vendor sources fetched live 2026-08-28)
**Source Verification:** All non-trivial claims cited with confidence levels; conflicts surfaced explicitly
**Technical Confidence Level:** High on documented vendor behaviour and on repository facts; Medium on vendor interpretation of the hosted-platform case; Low on undocumented API-key scope/expiry

_This document is an authoritative technical reference for the decision to add Kiro CLI as a platform agent runtime, and a reusable playbook for adding any runtime after it._
