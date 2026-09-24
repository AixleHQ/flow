# Runtimes

A **runtime** is the actual LLM CLI that runs inside an agent's
container. The persona decides *who* the agent is; the runtime decides
*what model and tool it drives*. The same persona can run on any of the
seven supported runtimes — pick the one whose model and credentials you
have.

## Supported runtimes

| Runtime           | LLM provider | Docker image            | Notes                                                                   |
| ----------------- | ------------ | ----------------------- | ----------------------------------------------------------------------- |
| `claude_code`     | Anthropic    | `aixle/claude-code`     | Default; also runs on your own Amazon Bedrock account.                  |
| `cursor_cli`      | Cursor AI    | `aixle/cursor-cli`      | Editor-style autocomplete and edits.                                    |
| `codex`           | OpenAI       | `aixle/codex`           | OpenAI Codex CLI.                                                       |
| `gemini_cli`      | Google       | `aixle/gemini-cli`      | Google Gemini CLI.                                                      |
| `antigravity_cli` | Google       | `aixle/antigravity-cli` | Google Antigravity CLI; separate runtime, not a Gemini CLI replacement. |
| `grok`            | xAI          | `aixle/grok`            | xAI Grok CLI.                                                           |
| `kiro_cli`        | AWS          | `aixle/kiro-cli`        | AWS Kiro CLI, run on its V3 engine. Metered in credits, not tokens.     |

All seven images are built locally with `make build-agents` and used by
the platform when starting a step's container; a deployed environment
pulls them from its registry instead (`AGENT_IMAGE_PREFIX`,
`AGENT_IMAGE_TAG`). Each runtime has an adapter under
`app/services/agents/` (`*_adapter.rb`) that knows how to launch the
CLI, feed it the assembled context, wire up MCP servers, and record
usage and cost.

## Credentials

Each user connects each runtime once per company, on their **Profile**
page (admins can inspect them under **Admin → Agent Credentials**). The
connection opens a terminal in the page and runs the CLI's own login;
the credential file the CLI writes is captured, stored encrypted, and
injected only at container start — it never lives in the image.

| Runtime           | What you sign in with                                                                  |
| ----------------- | -------------------------------------------------------------------------------------- |
| `claude_code`     | An Anthropic API key, a Claude subscription login, or an Amazon Bedrock connection.    |
| `cursor_cli`      | A Cursor account (`agent login`).                                                      |
| `codex`           | A ChatGPT account, signed in with the device-code flow.                                |
| `gemini_cli`      | A Gemini API key.                                                                      |
| `antigravity_cli` | A Google account, signed in through `agy`'s own interactive OAuth login.               |
| `grok`            | An xAI account, signed in with the device-code flow (or an xAI API key).               |
| `kiro_cli`        | A Kiro account, signed in with the device-code flow.                                   |

A step fails immediately with a "no credentials" error if the runtime's
credentials aren't configured for the user who triggered the run.

## Cost tracking

The platform records `cost_cents` and token counts per session. Where
the numbers come from depends on the runtime:

| Runtime           | Usage source                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------ |
| `claude_code`     | OpenTelemetry, streamed during the session.                                                |
| `cursor_cli`      | Cursor's usage API, matched to the requests in the session's MITM log at cleanup.          |
| `codex`           | OpenTelemetry, streamed; the MITM log at cleanup as a fallback.                            |
| `gemini_cli`      | OpenTelemetry, streamed.                                                                   |
| `antigravity_cli` | The cumulative usage in an automatic session's terminal `result` event, priced from the selected model's configured pricing. |
| `grok`            | The session's MITM log, priced from the xAI model catalogue.                              |
| `kiro_cli`        | Credits: the CLI's own credit telemetry, else the usage summaries in the MITM log, else the change in the account's credit counter. |

If `cost_cents` is `null` on a finished session, the runtime didn't emit
usage events; check **Admin → Session Logs**.

## MCP support

Every runtime's adapter writes the CLI's own MCP configuration, so all
seven reach the same MCP servers. The internal `aixle-tools` server
(board tools, progress, session lifecycle) is always connected
regardless of runtime — see the MCP servers page.

## See also

- **Agents** — personas, the container layout, and how context is assembled.
- **MCP servers** — the tool layer every runtime shares.
