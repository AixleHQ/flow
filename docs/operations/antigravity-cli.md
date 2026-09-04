# Antigravity CLI integration

Aixle runs Antigravity CLI as a separate runtime (`antigravity_cli`); it does not replace Gemini CLI.

## Authentication

Aixle supports the documented Gemini API-key provider, connected the same way as every other CLI: from Profile or Onboarding, "Connect"/"Authenticate" opens the standard auth-terminal session (`AgentAuthTerminal`), not a bespoke form.

`agy`'s own interactive welcome prompt (confirmed against the real 1.1.x binary, run with no flags) only offers "Google OAuth" or "Use a Google Cloud project" — it has no option to type in a raw API key, and setting `GEMINI_API_KEY` just skips that prompt without ever writing a credential artifact. Since neither of `agy`'s own login modes is portable across ephemeral containers, the auth terminal runs a small login script (`Agents::AntigravityCliAdapter#auth_launch_commands_for`) instead of `agy` directly: it prompts the user for their company-scoped Google AI Studio key, calls the real CLI to validate it, and — only on success — writes it to `~/.gemini/antigravity-cli/aixle-api-key.json`, the same file `AgentAuthStrategy#before_cleanup` already captures for every adapter. The backend then stores it in the encrypted `AgentCredential` record and injects `GEMINI_API_KEY` only into that company's sessions.

Account OAuth is intentionally unsupported because Antigravity stores it in an OS keyring, which cannot be safely moved between ephemeral containers (also confirmed hands-on: the default sign-in flow blocks on a browser the container cannot open). Enterprise ADC can be added separately when company-managed workload identity is available.

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

The image intentionally downloads GitHub's current `latest` release during each build. Record the emitted `agy --version` value with the published image digest for rollback traceability.
