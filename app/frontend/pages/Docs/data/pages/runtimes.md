# Runtimes

A **runtime** is the actual LLM CLI that runs inside an agent's
container. The persona decides *who* the agent is; the runtime decides
*what model and tool it drives*. The same persona can run on any of the
six supported runtimes — pick the one whose model and credentials you
have.

## Supported runtimes

| Runtime           | LLM provider | Docker image            | Notes                                                                   |
| ----------------- | ------------ | ----------------------- | ------------------------------------------------------------------------|
| `claude_code`     | Anthropic    | `aixle/claude-code`     | Default; supports MCP natively.                                        |
| `cursor_cli`      | Cursor AI    | `aixle/cursor-cli`      | Editor-style autocomplete and edits.                                   |
| `codex`           | OpenAI       | `aixle/codex`           | OpenAI Codex CLI.                                                       |
| `gemini_cli`      | Google       | `aixle/gemini-cli`      | Google Gemini CLI.                                                      |
| `antigravity_cli` | Google       | `aixle/antigravity-cli` | Google Antigravity CLI; separate runtime, not a Gemini CLI replacement. |
| `grok`            | xAI          | `aixle/grok`            | xAI Grok CLI.                                                           |

All six images are built locally with `make build-agents` and used by
the platform when starting a step's container. Each runtime has an
adapter under `app/services/agents/` (`*_adapter.rb`) that knows how to
launch the CLI, feed it the assembled context, wire up MCP servers, and
parse usage/cost out of its logs.

## Credentials

Each user configures runtime credentials on their **Profile** page (or
admins on **Admin → Agent Credentials**). Credentials are stored
encrypted and injected only at container start — they never live in the
image.

| Runtime           | Required credentials                                                   |
| ----------------- | ---------------------------------------------------------------------- |
| `claude_code`     | Anthropic API key, or an OAuth-signed session for Claude Code Pro.     |
| `cursor_cli`      | Cursor API key.                                                        |
| `codex`           | OpenAI API key.                                                        |
| `gemini_cli`      | Google AI Studio API key.                                              |
| `antigravity_cli` | Google account, signed in through `agy`'s own interactive OAuth login. |
| `grok`            | xAI account, signed in with the device-code flow (or an xAI API key).  |

A step fails immediately with a "no credentials" error if the runtime's
credentials aren't configured for the user who triggered the run.

## Cost tracking

The platform records `cost_cents` and token counts per session by
parsing usage events out of the runtime's logs. This works only on
runtimes whose adapter overrides `#collect_usage` to parse them —
`antigravity_cli` currently leaves it as the base no-op, so it never
reports cost or token counts. If `cost_cents` is `null` on a finished
session, the runtime didn't emit usage events; check
**Admin → Session Logs**.

## MCP support

`claude_code` speaks MCP natively. The other runtimes are wired to the
same MCP servers through their adapters. The internal `aixle-tools`
server (board tools, progress, session lifecycle) is always connected
regardless of runtime — see the MCP servers page.

## See also

- **Agents** — personas, the container layout, and how context is assembled.
- **MCP servers** — the tool layer every runtime shares.
