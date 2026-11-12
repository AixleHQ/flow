# Agent telemetry: what each runtime sends

Status: implemented for the runtimes with OpenTelemetry export; hooks for the others are
not built yet (§3).

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

So each runtime is set to emit **every signal and every content switch it has**: what
Flow does not read costs it a parse; what it does not emit is lost to Insights for good.

## 1. Switches per runtime

Versions are the pins in `config/agent_runtimes.json`. Each switch is set only when the
session has a collector (a runner session has none yet).

| Runtime | Signals | Content switches set | Flow's own usage reads |
| --- | --- | --- | --- |
| Claude Code 2.1.318 | logs, metrics, traces (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`) | `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`; `OTEL_METRICS_INCLUDE_{VERSION,ENTRYPOINT,REPOSITORY}` | metrics |
| Codex 0.166.0 | logs, metrics, traces (`[otel]` exporters) | `log_user_prompt`, `log_agent_responses`, `log_guardian_assessments`, `[otel.tool_result] max_bytes = 65536` | logs (`response.completed`) |
| Gemini CLI 0.60.0 | logs, metrics, traces (`telemetry.traces`) | `telemetry.logPrompts` | logs |
| Copilot CLI 1.0.108 | traces, metrics (it has no logs) | `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`; `OTEL_INSTRUMENTATION_GENAI_CAPTURE_CONTENT=SPAN_AND_EVENT` in case it is honoured | `chat` spans |
| Grok 1.0.70 | logs, metrics (`GROK_EXTERNAL_OTEL`) | `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT` | MITM log (no cost in OTLP) |
| Kiro CLI 3.0.0 | metrics, `--no-interactive` runs only | none exist | credit metrics, MITM fallback |
| Cursor CLI | none to a collector | — | Cursor usage API |
| Antigravity CLI 1.5.0 | none | — | stream-json result |

Notes:

- **Volume.** Claude Code's raw API bodies resend the conversation with every request, each
  cut at `CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH` (60 KiB by default); they are most of a
  session's telemetry. `otlp-ingest` refuses a request over 10 MB.
- **Codex metrics** default to OpenAI's Statsig. With a collector they come to Flow instead;
  without one (a runner session) the default stays, and the MITM fallback of
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

## 3. Runtimes without OpenTelemetry: hooks (not built)

Kiro, Cursor and Antigravity have lifecycle hooks that a user-level config in the
container's home directory can install, without touching the repository. A hook would
receive the CLI's event JSON on stdin and post it — unchanged, as the body of one OTLP log
record — to the collector in the background, with the session named in the command Flow
writes (whether hooks inherit the CLI's environment is not confirmed for every CLI).

| Runtime | Hook config | Events | What a hook sees that OTLP does not give |
| --- | --- | --- | --- |
| Kiro CLI 3.0.0 | `~/.kiro/hooks/*.json` | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd` | prompts; tool name, input, success and result. No model, tokens or credits. |
| Cursor CLI | `~/.cursor/hooks.json` | `beforeSubmitPrompt`, `preToolUse`, `postToolUse(Failure)`, `afterShellExecution`, `afterMCPExecution`, `afterAgentResponse`, `stop`, … | prompts; tool input, output, id and duration; model; per-turn tokens on `stop` / `afterAgentResponse`. No cost. |
| Antigravity CLI 1.5.0 | `~/.gemini/config/hooks.json` | `PreInvocation` / `PostInvocation`, `PreToolUse` / `PostToolUse`, `Stop` | prompt and tool name and arguments. No tool result, no tokens; event name and tool id only from 1.5.4. Its stream-json output, which Flow already captures, has more. |

Each needs a live run in Flow's container before it ships: that the hooks fire in the way
Flow runs the CLI, and that a slow or failing hook does not hold up the agent (Kiro, Cursor
and Grok wait for tool hooks).
