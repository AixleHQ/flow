# Antigravity CLI integration

Aixle runs Antigravity CLI as a separate runtime (`antigravity_cli`); it does not replace Gemini CLI.

The runtime image pins `agy` (1.4.7, `cli_version` in `config/agent_runtimes.json`) and
verifies Google's published SHA-256 checksum during the build.

## Authentication

Aixle connects Antigravity the same way as every other CLI: from Profile or Onboarding, "Connect"/"Authenticate" opens the standard auth-terminal session (`AgentAuthTerminal`), which launches the real `agy` binary directly — no bespoke form or script.

`agy`'s own interactive welcome prompt (confirmed against the real 1.1.27 binary, run with no flags) only offers "Google OAuth" or "Use a Google Cloud project" — both end up going through the same Google OAuth authorization-code flow (just different scopes), and neither has an option to type in a raw API key. That flow's redirect is a Google-hosted URL (`https://antigravity.google/oauth-callback`), not a localhost callback, so it never needs the container to receive anything back: the user opens the printed URL in their own browser and either gets redirected straight through or pastes the resulting authorization code into the terminal by hand.

Account OAuth is fully supported here, unlike the earlier design of this doc assumed: `agy` itself detects that a container has no D-Bus session bus and automatically persists the login to a file instead of the host OS keyring (confirmed in the CLI's own log output: `composite_token_storage.go: Using file-based token storage because no D-Bus session bus detected`), so it is safe to capture and move between ephemeral containers exactly like every other adapter's credential file. A completed real login confirmed the file: `~/.gemini/antigravity-cli/antigravity-oauth-token` (no extension), written as `{"token":{"access_token":...,"token_type":"Bearer","refresh_token":...,"expiry":"<ISO8601>"},"auth_method":"consumer"}` — nested under `token`, unlike `GeminiCliAdapter`'s flat `oauth_creds.json`. `AgentAuthStrategy#before_cleanup` captures that file (`Agents::AntigravityCliAdapter#config_path`) and the backend stores it in the encrypted `AgentCredential` record; on the next session, `#config_files` writes it back in the same shape before `agy` starts.

## Runtime contract

- Interactive sessions run `agy --dangerously-skip-permissions` inside the existing container sandbox.
- Automatic sessions use `agy --output-format stream-json --print`; the option order is significant because `agy` treats the token after `--print` as prompt text.
- MCP servers use `~/.gemini/config/mcp_config.json` and the documented `serverUrl` schema.
- Antigravity imports Gemini-compatible `GEMINI.md` and skills, so Aixle writes those established paths.
- Telemetry follows the user's Google account, not this image. Since 1.1.28 `agy` syncs it from the account's server-side setting and ignores `settings.json`'s `enableTelemetry` (it drops the key when it rewrites the file); no setting, environment variable or flag overrides it up to 1.4.7 (checked 2026-10-26). The user sets it in `/config`, or on the "Terms of Service & Data Use" onboarding step, whose box comes pre-ticked; the auth terminal leaves that step to the user. Even 1.1.27 lost the image's `enableTelemetry: false` once a user passed that step with the box ticked. Antigravity does not expose an OTLP export contract; automatic-run token counts remain available in its stream-JSON result and terminal log.
- Every session container is a fresh install, so agy would open each interactive session with its first-run onboarding (colour scheme, terms, then "Do you trust the contents of this project?"). Session containers get the file agy writes when onboarding finishes (`~/.gemini/antigravity-cli/cache/onboarding.json`, consumer logins only) and `/workspace` in `trustedWorkspaces`, so the session opens at the prompt. The auth terminal is not seeded with the onboarding file.
- The CLI updates itself. Run as root, the image's user, it replaces `/usr/local/bin/agy` with the vendor's newest release a second after it starts, so the session would run whatever shipped that day instead of the pin. `AGY_CLI_DISABLE_AUTO_UPDATE=true` in every container's environment (`Agents::AntigravityCliAdapter#default_env_vars`) stops it; the CLI ignores any other value, `1` included.

Build from the `docker/` directory:

```sh
docker build -f antigravity-cli/Dockerfile -t aixle/antigravity-cli:latest .
```

The image downloads the pinned `agy` release and verifies Google's published SHA-256 checksum during each build. Record the emitted `agy --version` value with the published image digest for rollback traceability.
