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

**Refreshed server-side.** An OIDC login against `auth.x.ai` stores its entry
under the scope key `https://auth.x.ai::<client id>`: `key` is the access token
(6 hours), with a `refresh_token` beside it. The adapter declares
`refresh: :server, rotation: :rotating, nominal_ttl: 6.hours`
(`#credential_lifecycle`), so the sweep selects it, and `#refresh_entry` posts
`grant_type=refresh_token` to `https://auth.x.ai/oauth2/token` as the CLI's
public client — the client id taken from the scope key, no secret. Only
entries issued by `auth.x.ai` are refreshed; a login without a refresh token
(an API key, or a pre-OIDC login) is not. Rotation is not measured, so it is
declared `:rotating`, the safe reading. The CLI can still rotate a token inside
the container, and `AgentSessionStrategy#persist_refreshed_credentials`
re-reads `auth.json` at cleanup and stores it. `#token_expires_at` reads an
`expires_at` from the scope entries when one is present (tolerating ISO8601,
epoch seconds, or epoch milliseconds) so `AgentCredential#expires_at` is
populated; when it is absent the value is `nil`.

## 3. Models

**Decision:** an API-key login's picker is populated from
`GET https://api.x.ai/v1/language-models`; a signed-in (OAuth) account's from the CLI's own
list, `GET https://cli-chat-proxy.grok.com/v1/models` with the session token and
`X-XAI-Token-Auth: xai-grok-cli` (`Grok::Api.models`), which is what `grok models` prints.

The public endpoint is the xAI catalogue and it also carries per-token prices,
which is what makes cost tracking possible (§5). It answers a session token with 403
`personal-team-blocked:spending-limit` unless the account holds API credits, so a
subscription login used to land on the fallback list and offer models its CLI does not
know (task #324, measured 2026-11-21: the account knew only `grok-4.7`). The fallback is
now the CLI's default model alone, `grok-4.7`; the live call is the source of truth, and
the fallback exists so the picker is never empty.

A model the account does not offer does not stop the CLI: it shows `Couldn't switch model:
Invalid params: "unknown model id"` and runs the default model. So a chosen model is looked
up in that list when the session is created (`SessionService#preflight_model!`), and a
missing one fails the step before any container starts, saying `Grok does not offer the
model … on this account (it offers …)`. The list also says per model whether it takes a
reasoning effort and which (`reasoning_efforts`), and the model pickers offer exactly
those.

## 4. Session behaviour

- **Session command:** `grok --yolo --minimal` (+ `--model <id>` when the session pins
  one). `--yolo` is xAI's documented alias for `--always-approve`, i.e.
  permission mode `bypassPermissions` — the direct equivalent of
  `codex --yolo` and `gemini --yolo`. The container is the sandbox.
  `--minimal` prints the conversation into the terminal scrollback. The default
  TUI draws on the alternate screen, and `--no-alt-screen` still repaints a
  single frame. Either way the live terminal and the stored log replay would
  have nothing to scroll back to (measured on 1.0.70).
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

  The CLI's own project-rules documentation lists this root as
  *"`$GROK_HOME/rules/` (default `~/.grok/rules/`) — Always scanned; applies
  to all projects"*, ahead of the per-directory `AGENTS.md` files. Verified
  against the installed CLI (`@xai-official/grok@1.0.4`) rather than against
  the docs alone:

  ```
  $ grok inspect
    Project Instructions (1)
    └ /home/grok/.grok/rules/aixle-session-context.md (global, ~7 tokens)
  ```

  A home-level `~/.grok/AGENTS.md` is discovered too, so this is a choice
  between two working paths, not a fix for a broken one. `rules/` wins
  because it is the root xAI documents as *always* scanned and because a
  dedicated file there cannot collide with an `AGENTS.md` written into the
  agent home by the user, a plugin, or a future CLI default.

  `docker/grok/Dockerfile` pins this boundary at build time: it drops a
  marker at the adapter's context path, runs `grok inspect` as the `grok`
  user, and fails the build unless the CLI reports that exact path. A CLI
  release that stops scanning home-level rules breaks the image build
  instead of silently dropping every session's task and role instructions.
- **Skills:** skills.sh knows Grok as agent id `grok` with global directory
  `~/.grok/skills`, so registry installs and hand-written skills both land
  where the CLI looks.
- **BMAD:** BMAD 6.11.0 has no `grok` platform, so `grok` maps to
  `claude-code`. This is not a stand-in for a missing platform: Grok's
  `[compat.claude]` cells are on by default and scan `.claude/skills`,
  `.claude/rules`, and `CLAUDE.md`, so the claude-code install is exactly
  what a Grok session can consume.

## 5. Usage and cost — why not OpenTelemetry

**Decision:** usage is parsed from the session's MITM log at cleanup
(`#collect_usage`), not from OTLP.

Grok CLI *can* export OTLP metrics and events, and its
`grok_code.token.usage` metric carries exactly the breakdown Aixle wants. Its
external OTEL stream builds its resource from a **fixed, audited attribute
set**, ignores `OTEL_RESOURCE_ATTRIBUTES` outright, and drops any record
carrying an out-of-schema attribute key at export, so the session cannot be
named in a resource attribute. For a session with full telemetry (a project
exported to Insights, `TerminalSession#full_telemetry?`), the adapter turns
the export on (`GROK_EXTERNAL_OTEL=1`, logs and metrics, every content
switch) and names the session in `OTEL_EXPORTER_OTLP_HEADERS` instead
(`X-Aixle-Session-Token`, `X-Aixle-Session-Key`); otlp-ingest stamps those
headers onto the resource as `terminal_session_token` / `terminal_session_key`
(`stampSession` in `docker/otlp-ingest/main.go`). That stream feeds Insights
(`docs/design/agent-telemetry.md`); Flow's own usage and cost still come from
the MITM log.

What works for usage: Grok's model traffic goes over HTTPS to a host whose
responses are OpenAI-shaped, so the MITM log captures completions whose
bodies carry a `usage` object. **Which** host depends on how the user signed
in, and both have to be tracked:

| Login | Inference host |
| --- | --- |
| Device-code / OAuth (the default, §2) | `cli-chat-proxy.grok.com` — the proxy xAI requires for a signed-in session |
| `XAI_API_KEY` | `api.x.ai` — the direct API path |

`MITM_TRACKED_DOMAINS=x.ai,grok.com` therefore covers both, and
`#extract_events_from_mitm` accepts an entry whose host is one of those
domains or a subdomain of one — the same rule
`docker/base/logger/mitm_logger.py::_should_log` filters on, rather than a
bare suffix test that would also accept a lookalike host such as
`phishx.ai`. Tracking `x.ai` alone was the original mistake: it silently
left every session on the *primary* auth path with no tokens and no cost.

The adapter extracts the counts by pattern (a streamed body's `usage`
arrives in the final SSE chunk and the logged body may be a truncated tail —
the same constraint the Codex adapter works around), matching both wire
formats the CLI can speak: Chat Completions
(`prompt_tokens`/`completion_tokens`) and the Responses API
(`input_tokens`/`output_tokens`). Both routes are covered by regression
tests, the OAuth one against an SSE-framed `cli-chat-proxy.grok.com`
response under an OAuth credential.

**Open assumption.** The proxy's exact streamed body has not been observed
against a live account — no xAI credential exists in any Aixle environment
(the same gap that leaves AC 2–5 and 7 unverified end to end). The parser is
deliberately shape-tolerant rather than tied to one framing: it scans the
raw logged text for the token fields of either wire format, so SSE framing,
chunk boundaries, and a truncated tail all still yield the counts. If a live
session shows the proxy reporting usage under names outside
`USAGE_FIELD_ALIASES`, that map is the single place to extend.

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
- **No OTLP-based usage** — usage and cost come from the MITM log; see §5.
