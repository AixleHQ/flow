# Agent telemetry: what each runtime sends

Status: implemented, off for every session — OpenTelemetry switches for the runtimes that
export it (§1), lifecycle hooks for the ones that do not (§3), both behind one switch
(§4).

Every agent session reports to the platform's collector, `docker/otlp-ingest`, which
accepts OTLP/HTTP logs, metrics and traces (protobuf or JSON) and forwards them as JSON
to `POST /api/v1/internal/usage_statistics`. There each batch must prove its session —
the `terminal_session_token` resource attribute plus `terminal_session_key`
(`UsageStatistics::SessionKey`) — before anything is read.

Two consumers read the stream:

- **Flow's own usage** (`UsageStatisticsService` → each adapter's `ingest_usage`), which
  reads only the records it needs and ignores the rest.
- **The Aixle Insights relay**, which forwards the whole stream of a project switched on
  for it.

So a session with **full telemetry** emits **every signal and every content switch its
runtime has**: what Flow does not read costs it a parse; what it does not emit is lost to
Insights for good. Every other session sends only what Flow's own usage reads (§4).

## 1. Switches per runtime

Versions are the pins in `config/agent_runtimes.json`. What a session with full telemetry
gets; each switch is set only when the session has a collector (a runner session has none
yet).

| Runtime | Signals | Content switches set | Flow's own usage reads |
| --- | --- | --- | --- |
| Claude Code 2.1.318 | logs, metrics, traces (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`) | `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`; `OTEL_METRICS_INCLUDE_{VERSION,ENTRYPOINT,REPOSITORY}` | metrics |
| Codex 0.166.0 | logs, metrics, traces (`[otel]` exporters) | `log_user_prompt`, `log_agent_responses`, `log_guardian_assessments`, `[otel.tool_result] max_bytes = 65536` | logs (`response.completed`) |
| Gemini CLI 0.60.0 | logs, metrics, traces (`telemetry.traces`) | `telemetry.logPrompts` | logs |
| Copilot CLI 1.0.108 | traces, metrics (it has no logs) | `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`; `OTEL_INSTRUMENTATION_GENAI_CAPTURE_CONTENT=SPAN_AND_EVENT` in case it is honoured | `chat` spans |
| Grok 1.0.70 | logs, metrics (`GROK_EXTERNAL_OTEL`) | `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT` | MITM log (no cost in OTLP) |
| Kiro CLI 3.0.0 | metrics; logs from its hooks (§3) | none exist | credit metrics, MITM fallback |
| Cursor CLI 2026.10.22 | logs from its hooks (§3) | — | Cursor usage API |
| Antigravity CLI 1.5.0 | logs from its hooks (§3) | — | stream-json result |

Notes:

- **Volume.** Claude Code's raw API bodies resend the conversation with every request, each
  cut at `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH` (60 KiB by default); they are most of a
  session's telemetry. `otlp-ingest` refuses a request over 10 MB.
- **Codex metrics** default to OpenAI's Statsig. With full telemetry they come to Flow
  instead; otherwise the default stays, and the MITM fallback of
  `CodexAdapter#collect_usage` still finds them.
- **Grok** ignores `OTEL_RESOURCE_ATTRIBUTES`, so the session is named in
  `OTEL_EXPORTER_OTLP_HEADERS` (`X-Aixle-Session-Token`, `X-Aixle-Session-Key`), and
  `otlp-ingest` copies those headers onto every resource that does not name a session
  itself. xAI can switch the CLI's external telemetry off for everyone, and it holds the
  first export for up to 30 seconds.
- **Copilot CLI** documents that an `http://` endpoint disables export; its 1.0.106 changelog
  narrows that to when TLS certificate variables are set, and 1.0.108 exports to Flow's plain
  `http://` collector.
- **Claude Code** reads these variables from the process environment only; since 2.1.282 a
  project's settings cannot set them.

## 2. Content

With every switch on, a session's telemetry carries its prompts, the model's replies, tool
arguments and tool output, and for Claude Code the raw API request and response bodies.
Flow's own usage keeps none of it. It leaves Flow only through the Insights relay, for
projects switched on there, with the session's secret config items masked.

## 3. Runtimes without OpenTelemetry: hooks

Kiro, Cursor and Antigravity export nothing a collector can take (Kiro only its credit
metrics), but each runs user-level lifecycle hooks: a command, given the event as JSON on
stdin. The adapter writes a hooks file into the container's home directory — next to any
hooks the repository brings, never in it — whose every command is
`docker/base/logger/otlp_hook.py` (`/opt/mitm/otlp_hook.py` in every agent image):

```
python3 -I /opt/mitm/otlp_hook.py <service.name> <event> [reply] || true
```

It posts one OTLP/HTTP JSON log record to `$AIXLE_OTLP_ENDPOINT/v1/logs`:

| Field | Value |
| --- | --- |
| resource `service.name` | `kiro-cli`, `cursor-agent`, `antigravity-cli` |
| resource `terminal_session_token`, `terminal_session_key` | from `AIXLE_OTLP_RESOURCE_ATTRIBUTES` |
| scope | `aixle_flow.hooks` |
| `event.name` | the CLI's own name for the event (`PreToolUse`, `stop`, …) |
| body | the event JSON exactly as the CLI wrote it (cut at 8 MiB, marked `aixle_flow.hook.truncated_from_bytes`) |

The collector and the session come from the environment — `AIXLE_OTLP_ENDPOINT` and
`AIXLE_OTLP_RESOURCE_ATTRIBUTES`, set by `default_env_vars`, inherited by the hook from the
CLI — so the hooks file itself is the same for every session. Two reasons, both measured:
Cursor strips `//` comments from `hooks.json` before parsing it, so an `http://` in a command
silently drops every hook in the file; and `OTEL_RESOURCE_ATTRIBUTES` is not used because
Antigravity's own telemetry goes to Google, and an SDK that read it would carry the session
key there.

A hook runs inside the agent's turn, and the CLIs act on what it does:

| | Kiro 3.0.0 | Cursor 2026.10.22 | Antigravity 1.5.0 |
| --- | --- | --- | --- |
| File | `~/.kiro/hooks/aixle-telemetry.json` | `~/.cursor/hooks.json` | `~/.gemini/config/hooks.json` |
| Non-zero exit | blocks the tool / prompt | ignored; exit 2 blocks | blocks the tool (PreToolUse) |
| Stdout | added to the model's context | parsed as JSON; not an object denies the tool | protojson; `{}` denies the tool |
| Waits for | the process | every pipe to close (5 s fallback) | the process, then 1 s for pipes |

So the script prints only its `reply` (`{}` for Cursor, nothing for the others), always
exits 0 (`|| true` covers a missing script or interpreter), reads stdin for at most two
seconds, and posts from a child that has closed every descriptor and left the CLI's process
group — the agent never waits on the collector, and a collector that is down loses the
record, nothing else. Each hook has a timeout (5 s Kiro, 10 s the others) as a backstop.

What each runtime's hooks carry:

| Runtime | Events | Carries | Not there |
| --- | --- | --- | --- |
| Kiro | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd` | prompt; tool name, input and result | model, tokens, credits (its OTLP metrics) |
| Cursor | `sessionStart`, `beforeSubmitPrompt`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `afterAgentThought`, `afterAgentResponse`, `stop`, `subagentStart`, `subagentStop`, `preCompact`, `sessionEnd` | prompt; model; tool input, output and duration; reply and thinking; per-turn input, output and cache tokens | cost |
| Antigravity | `SessionStart`, `PreInvocation`, `PostInvocation`, `PreToolUse`, `PostToolUse`, `Stop` | prompt; model; invocation and step numbers; tool name, arguments and error; why the turn ended | model output, tool result, tokens (its stream-json result, which Flow reads, has the tokens); event name in the payload (1.5.4) |

Left out on purpose: Cursor's shell, MCP and file events repeat its generic tool events
(`beforeReadFile` with every file read in full), and an unknown event name makes it drop the
whole file; Kiro's file events repeat its write tool. Cursor's `beforeSubmitPrompt`, `stop`
and `afterAgentResponse` do not fire under `-p`; Flow runs Cursor without it.

A session without full telemetry, or without a collector (a runner session), gets neither
the hooks file nor the variables.

### Checked live (2026-11-13)

Each runtime's image at its pin, the adapter's own hooks file, a real `otlp-ingest`, and a
stand-in for the Rails endpoint that kept what it was sent:

| Runtime | How | Records, each with the session | The tool ran |
| --- | --- | --- | --- |
| Antigravity 1.5.0 | Gemini API key against a scripted model (a `run_command` call, then text); `--print` and TUI | `SessionStart`, `PreInvocation` ×2, `PreToolUse`, `PostToolUse`, `PostInvocation` ×2, `Stop` | yes, whole run 1–2 s |
| Cursor 2026.10.22 | real login, TUI | `sessionStart`, `beforeSubmitPrompt`, `afterAgentThought` ×2, `preToolUse`, `postToolUse`, `stop`, `afterAgentResponse`, `sessionEnd` | yes |
| Kiro 3.0.0 | real IdC login, TUI | `SessionStart`, `UserPromptSubmit`, `SessionEnd` | the account was at its monthly limit, so the model called no tool: Kiro's tool hooks and `Stop` are not yet seen live |

No hook process outlived its event and none was left a zombie. The first Cursor run sent
nothing — the `//` finding above.

## 4. The switch

`TerminalSession#full_telemetry?` decides, once per session. It is `false` for every
session: Flow keeps nothing but usage, so the rest stays off until something forwards it.
The adapters read it in two places:

- `default_env_vars(session, callbacks:)` asks the session — the environment switches,
  Grok's export and the hooks' variables;
- `config_files(credentials, workflow_config)` reads `workflow_config[:full_telemetry]`,
  which `SessionContextService#credential_workflow_config` sets only for a session with a
  collector — Codex's `[otel]` table, Gemini CLI's `telemetry`, and the hooks files.

Both are written when the container starts, so a change reaches the next session, not a
running one.

Without full telemetry each runtime sends what Flow's usage reads and no content: Claude
Code its metrics; Codex its logs; Gemini CLI logs and metrics, with `logPrompts` off and
`traces` not set; Copilot CLI its spans and metrics without message content; Kiro its credit
metrics. Grok exports nothing, and Kiro, Cursor and Antigravity get no hooks.
