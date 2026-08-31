# Antigravity CLI integration

Aixle runs Antigravity CLI as a separate runtime (`antigravity_cli`); it does not replace Gemini CLI.

## Authentication

Aixle supports the documented Gemini API-key provider. Connect the runtime from Profile and enter a company-scoped Google AI Studio key. Aixle writes `modelProvider: gemini` to `~/.gemini/antigravity-cli/settings.json` and injects `GEMINI_API_KEY` only into that company's sessions. Account OAuth is intentionally unsupported because Antigravity stores it in an OS keyring, which cannot be safely moved between ephemeral containers. Enterprise ADC can be added separately when company-managed workload identity is available.

## Runtime contract

- Interactive sessions run `agy --dangerously-skip-permissions` inside the existing container sandbox.
- Automatic sessions use `agy --print --output-format stream-json`; the standard Aixle context instructs the agent to call `finish_session` or `fail_session`.
- MCP servers use `~/.gemini/config/mcp_config.json` and the documented `serverUrl` schema.
- Antigravity imports Gemini-compatible `GEMINI.md` and skills, so Aixle writes those established paths.
- Vendor telemetry is disabled. Antigravity does not expose an OTLP export contract; automatic-run token counts remain available in its stream-JSON result and terminal log.

Build from the `docker/` directory:

```sh
docker build -f antigravity-cli/Dockerfile -t aixle/antigravity-cli:latest .
```
