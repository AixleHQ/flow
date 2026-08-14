# Grok (xAI) runtime integration — decisions

Task #587. This records the choices behind `Agents::GrokAdapter` and the
`grok` agent type: which CLI drives Grok inside the container, how a user
authenticates, which models are offered, and where token/cost usage comes
from. Everything here was settled by investigation, so the reasoning is
written down rather than left in the diff.

## 1. Invocation surface: the official Grok CLI

**Decision:** the container runs the official xAI CLI, npm package
`@xai-official/grok`, binary `grok`, installed globally into a dedicated
`aixle/grok` image (`docker/grok/Dockerfile`) built on `aixle/agent-base-core`.

**Why this and not something else.** Three candidate surfaces existed:

| Candidate | Verdict |
| --- | --- |
| `@xai-official/grok` — xAI's own CLI | **Chosen.** First-party, ships an agentic TUI plus a headless mode, MCP, skills, hooks, permission modes, and an OpenTelemetry export. Its shape matches what `Agents::BaseAdapter` already expects from a runtime. |
| Community CLIs (`@vibe-kit/grok-cli`, `@stevederico/grok-cli`, forks) | Rejected. Third-party wrappers around the xAI API with no auth story we would want to depend on for a paying tenant's credential. |
| Grok over the raw xAI API from an existing runtime | Rejected. Aixle models a runtime as a containerised *CLI*; bolting a model onto another vendor's CLI would not give the user a Grok session, a Grok credential, or Grok usage. |

The CLI ships a per-platform native binary brotli-compressed inside a
sibling npm package and materialises it into `$GROK_HOME/bin` on first
launch. The image does that at **build** time as the `grok` user, so the
~160 MB decompression is not paid on every container start and a broken
install fails the build rather than a live session. The now-redundant
compressed payload is removed in the same layer.

## 2. Authentication: device-code OAuth, credential = `~/.grok/auth.json`

**Decision:** the auth container runs `grok login --device-auth`. The
credential Aixle captures and re-materialises is `~/.grok/auth.json`.

Grok CLI supports four ways in: browser OAuth (the default), device code,
an `XAI_API_KEY` environment variable, and enterprise OIDC / an external
auth-provider binary. Only the device-code flow completes inside an Aixle
auth terminal — nothing in the container can open a browser, and the
device-code flow is the one xAI documents for "SSH sessions, Docker
containers, remote VMs". It prints a URL and a code, the user finishes on
their own device, and the CLI writes `auth.json`.

`auth.json` is a map of *auth scope* → entry, where the scope is the issuer
(`https://accounts.x.ai/sign-in` for a normal login, `xai::api_key` when the
user signed in with an API key) and the entry holds the bearer token under
`key`. Consequences:

- **Watcher.** `AUTH_REQUIRED_KEYS` resolves a required key by splitting on
  `.`, and every scope key is a URL full of dots, so no scope is addressable
  that way. The adapter uses the `__present__` sentinel (as `gemini_cli`
  does for its encrypted blob) and puts the real check server-side:
  `#auth_complete?` requires valid JSON with at least one scope entry
  carrying a non-blank token.
- **One artifact, every flow.** Because all four login flows write the same
  file, capturing `auth.json` supports an API-key login too, without a
  second code path. When the captured blob carries the `xai::api_key` scope,
  the adapter lifts the key out as a flat `api_key` field and injects it as
  `XAI_API_KEY` for the session — the same per-company injection
  `gemini_cli` does, so the vendor bill lands on the company that ran the
  session.
- **A stray key is a hazard.** `XAI_API_KEY` outranks a stored session token
  in the CLI's own credential resolution, so a key left in the environment
  by any other source would silently bill a different account than the one
  the user authenticated. `#conflicting_env_keys` drops `XAI_API_KEY`
  whenever the credential is *not* an API-key login.

**Not added to `REFRESHABLE_AGENT_TYPES`.** Grok session tokens do expire,
and the CLI refreshes them itself in the container — but xAI publishes no
token endpoint or client id for `auth.x.ai`, so a server-side `#refresh!`
would be reverse-engineered guesswork against an undocumented endpoint.
Instead, rotation is picked up the way it already is for every runtime:
`AgentSessionStrategy#persist_refreshed_credentials` re-reads `auth.json` at
cleanup and stores the rotated blob. `#token_expires_at` reads an
`expires_at` from the scope entries when one is present (tolerating ISO8601,
epoch seconds, or epoch milliseconds) so `AgentCredential#expires_at` is
populated; when it is absent the value is `nil`, which is exactly the
pre-existing "no expiry known" behaviour.

## 3. Models

**Decision:** the picker is populated from `GET https://api.x.ai/v1/language-models`,
authenticated with the credential's API key or session token.

That endpoint is the xAI catalogue and it also carries per-token prices,
which is what makes cost tracking possible (§5). When it is unreachable — or
declines a session token, which the public API may — the adapter falls back
to a deliberately minimal list: `grok-4.5` (what the CLI itself reports as
its default model), `grok-4.6` (the model behind Grok Build), and
`grok-code-fast-1`. The live call is the source of truth; the fallback exists
so the picker is never empty.

## 4. Session behaviour

- **Session command:** `grok --yolo` (+ `--model <id>` when the session pins
  one). `--yolo` is xAI's documented alias for `--always-approve`, i.e.
  permission mode `bypassPermissions` — the direct equivalent of
  `codex --yolo` and `gemini --yolo`. The container is the sandbox.
- **`~/.grok/config.toml`** is generated per session and pre-decides every
  prompt the CLI could otherwise block on: always-approve permission mode,
  folder trust **off** (which un-gates repo-local MCP/LSP/hooks so no session
  stops on "Trust the authors of this folder?"), auto-update off (the image
  pins the version), telemetry off, and the pinned model. A cut-down copy is
  written *before* `grok login` runs so the login terminal behaves the same.
- **MCP:** `[mcp_servers.<name>]` tables appended to the same `config.toml`
  (`mcp_merge_strategy = :append_toml`, like Codex). STDIO servers get
  `command`/`args`/`env`; remote servers get `url`/`headers` — the CLI infers
  the transport from which is present. Values are rendered through a TOML
  string escaper so a name, header, or arg containing a quote or backslash
  cannot corrupt the file.
- **Context file:** `~/.grok/rules/aixle-session-context.md`. Grok scans
  `$GROK_HOME/rules/*.md` on every session in every directory, git repo or
  not, which keeps `/workspace` clean — unlike `AGENTS.md`, which would have
  to be written into the user's repo.
- **Skills:** skills.sh knows Grok as agent id `grok` with global directory
  `~/.grok/skills`, so registry installs and hand-written skills both land
  where the CLI looks.
- **BMAD:** BMAD 6.10.0 has no `grok` platform, so `grok` maps to
  `claude-code`. This is not a stand-in for a missing platform: Grok's
  `[compat.claude]` cells are on by default and scan `.claude/skills`,
  `.claude/rules`, and `CLAUDE.md`, so the claude-code install is exactly
  what a Grok session can consume.

## 5. Usage and cost — why not OpenTelemetry

**Decision:** usage is parsed from the session's MITM log at cleanup
(`#collect_usage`), not ingested from OTLP in real time.

Grok CLI *can* export OTLP metrics and events, and its
`grok_code.token.usage` metric carries exactly the breakdown Aixle wants.
It still cannot be used, for a specific reason: the external OTEL stream
builds its resource from a **fixed, audited attribute set**, ignores
`OTEL_RESOURCE_ATTRIBUTES` outright, and drops any record carrying an
out-of-schema attribute key at export. `terminal_session_token` — the only
thing `UsageStatisticsService` correlates on — therefore cannot reach the
collector by any supported configuration. Routing per session by URL or
header would mean changing the shared collector and ingest endpoint, which
is out of scope for adding a runtime.

What works instead: Grok's model traffic goes to `api.x.ai` over HTTPS and
the responses are OpenAI-shaped, so `MITM_TRACKED_DOMAINS=x.ai` captures
completions whose bodies carry a `usage` object. The adapter extracts the
counts by pattern (a streamed body's `usage` arrives in the final chunk and
the logged body may be a truncated tail — the same constraint the Codex
adapter works around), matching both wire formats the CLI can speak: Chat
Completions (`prompt_tokens`/`completion_tokens`) and the Responses API
(`input_tokens`/`output_tokens`).

**Cost** is priced from the same catalogue as the model list. xAI quotes
per-token prices in **cents per 10⁸ tokens**, so
`cents = tokens × price / 1e8`, with uncached input, cached input, and
output priced separately (verified against xAI's published per-million
rates: `grok-4.5` at `prompt_text_token_price` 20000 → \$2.00/M input,
`completion_text_token_price` 60000 → \$6.00/M output). When the catalogue
is unreachable the tokens are still recorded and the cost stays 0, which is
how the Codex MITM path already degrades.

**Quota errors:** `QuotaErrorDetector` gains an `xai` provider matching the
CLI's own rendered limit messages ("out of credits", "usage balance
exhausted", "You've hit the rate limit for your plan", "You hit your weekly
limit", "Purchase credits to keep using Grok"). Only Grok-distinctive
phrasings were added, so no existing provider's detection changes.

## 6. What is deliberately not included

- **No vendor artwork.** No licensed xAI mark ships in this repo, so no
  `agent-logos/grok.png` was invented. The analytics `AgentLogo` already
  falls back to a colour chip for a runtime without artwork, and the runtime
  is registered in the colour map so it renders as known rather than
  unmapped. `AGENT_BRAND_COLORS.grok` is a neutral slate: xAI's mark is
  monochrome, so there is no chromatic brand value to carry, and a literal
  `#000` swatch would vanish on a dark surface.
- **No server-side token refresh** — see §2.
- **No real-time OTLP ingest** — see §5.
