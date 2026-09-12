# Antigravity CLI integration

Aixle runs Antigravity CLI as a separate runtime (`antigravity_cli`); it does not replace Gemini CLI.

The runtime image pins `agy` 1.1.27 and verifies Google's published SHA-256
checksum during the build. This release includes the upstream fixes for
headless runs hanging when tmux pipes their output and for print-mode shutdown.

## Authentication

Aixle connects Antigravity the same way as every other CLI: from Profile or Onboarding, "Connect"/"Authenticate" opens the standard auth-terminal session (`AgentAuthTerminal`), which launches the real `agy` binary directly — no bespoke form or script.

`agy`'s own interactive welcome prompt (confirmed against the real 1.1.27 binary, run with no flags) only offers "Google OAuth" or "Use a Google Cloud project" — both end up going through the same Google OAuth authorization-code flow (just different scopes), and neither has an option to type in a raw API key. That flow's redirect is a Google-hosted URL (`https://antigravity.google/oauth-callback`), not a localhost callback, so it never needs the container to receive anything back: the user opens the printed URL in their own browser and either gets redirected straight through or pastes the resulting authorization code into the terminal by hand.

Account OAuth is fully supported here, unlike the earlier design of this doc assumed: `agy` itself detects that a container has no D-Bus session bus and automatically persists the login to a file instead of the host OS keyring (confirmed in the CLI's own log output: `composite_token_storage.go: Using file-based token storage because no D-Bus session bus detected`), so it is safe to capture and move between ephemeral containers exactly like every other adapter's credential file. A completed real login confirmed the file: `~/.gemini/antigravity-cli/antigravity-oauth-token` (no extension), written as `{"token":{"access_token":...,"token_type":"Bearer","refresh_token":...,"expiry":"<ISO8601>"},"auth_method":"consumer"}` — nested under `token`, unlike `GeminiCliAdapter`'s flat `oauth_creds.json`. `AgentAuthStrategy#before_cleanup` captures that file (`Agents::AntigravityCliAdapter#config_path`) and the backend stores it in the encrypted `AgentCredential` record; on the next session, `#config_files` writes it back in the same shape before `agy` starts.

## Eligibility

`agy` runs its own eligibility check at startup and can refuse the account outright:

```
⚠ Eligibility Check
  Eligibility check failed: Your current account is not eligible for Antigravity,
  because it is not currently available in your location.
```

Observed 2026-09-12 with a Google Workspace account signed in through the normal consumer OAuth flow. Auth, the model catalogue and `agy models` all still work in that state — what fails is every completion call, so no model traffic reaches the wire at all. Anything that has to be confirmed against a real turn (the usage field names below) needs an account that passes this check, or an egress region that does.

## Models

`#fetch_available_models` calls `POST https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` with a `{}` body and the credential's Bearer token — the same call `agy models` makes, captured through the session image's own MITM proxy.

Two things about that endpoint are easy to get wrong:

- **It gates on the User-Agent.** The same token answers 403 with curl's default agent and 200 with `antigravity/cli/<version> (aidev_client; …)`. The bare `aidev_client` token is not enough — the `antigravity/cli/<version>` prefix is what is checked.
- **The response is bigger than the model picker should be.** `models` holds 33 entries, including internal ones (tab completion, chat experiments, commit messages) that `--model` is not meant to take. `agentModelSorts` is the CLI's own agent list — the 14 ids `agy models` prints, in its order — so the adapter takes the order from there and the display names from `models`. `deprecatedModelIds` feeds `RETIRED_MODEL_REPLACEMENTS`, and `defaultAgentModelId` was `gemini-3.8-flash-high` when this was written.

The stored access token lives about an hour and nothing on our side renews it — `agy` refreshes inside its own container and that file is only captured back during an auth session — so an expired token is the normal case and the adapter falls back to a pinned copy of the 14-model list. Server-side refresh would need Google's client secret, which is embedded in the binary; that is a deliberate decision, not an oversight. The cheaper alternative is to capture the refreshed token file at the end of every agent session, the way auth sessions already do.

## Runtime contract

- Interactive sessions run `agy --dangerously-skip-permissions` inside the existing container sandbox.
- Automatic sessions run the same TUI with a trailing `-i`, and the standard Aixle context instructs the agent to call `finish_session` or `fail_session` — the same shape as every other runtime here. The `-i` is required, not stylistic: `AgentSessionStrategy#launch_agent_in_tmux` appends the prompt as a positional argument and `agy` refuses one (`Error: unexpected argument "…". Prompts are read only from -p/--print, -i/--prompt-interactive, or stdin`), so the flag is what turns the appended prompt into its value.
- The first-run wizard is answered upfront, in both auth and agent sessions. `agy` otherwise opens every fresh container on its colour-scheme picker, then a "Terms of Service & Data Use" consent screen, then a folder-trust prompt — each waiting on a keypress an automatic session never sends. Folder trust is `trustedWorkspaces: ["/workspace"]` in `settings.json`; the other two are gated on `~/.gemini/antigravity-cli/cache/onboarding.json` (`{"consumerOnboardingComplete": true, "enterpriseOnboardingComplete": false, "onboardingComplete": true}`). That file was found by completing the wizard in a container and diffing the whole filesystem — nothing in `settings.json`, `jetski_state.pbtxt`, `installation_id` or `conversation_summaries.db` changes when those screens are answered. Seeding it does not skip the login: with no token file present `agy` still opens on "Select login method". Note the consent screen's checkbox is a telemetry opt-in, and seeding it as answered means the session runs with `enableTelemetry: false` — opted out, never opted in on the user's behalf.
- MCP servers use `~/.gemini/config/mcp_config.json` and the documented `serverUrl` schema.
- Antigravity imports Gemini-compatible `GEMINI.md` and skills, so Aixle writes those established paths.
- Vendor telemetry is disabled, and there is no OTLP path to re-point at our collector: the 1.1.27/1.2.1 binary carries no `OTEL_EXPORTER_OTLP_*` support and no `otlpEndpoint` setting — only OTel SDK limit variables and Google's own client, which ships to `play.googleapis.com/log`. The Gemini CLI's `telemetry.otlpEndpoint` block does not exist in this fork.
- Usage comes from the MITM log, the only source that covers interactive and automatic runs alike now that OTLP is out. `#mitm_tracked_domains` lists `cloudcode-pa.googleapis.com`, `daily-cloudcode-pa.googleapis.com` and `aicode.googleapis.com` (Google's telemetry sink `play.googleapis.com/log` is deliberately not tracked), `#default_env_vars` passes them to the proxy, `#session_log_paths` collects `/var/log/mitm/http.log`, and `#collect_usage` folds the counts in through `UsageStatistics::Accumulator`. Capture is verified against the real binary: `agy` is Go, so it honours `HTTPS_PROXY`/`SSL_CERT_FILE` and the mitmproxy half of the logger sees it — a full `fetchAvailableModels` round trip was captured end to end. (The `http2-logger.js` half only patches Node's http modules and never sees this CLI.)
- **The token field names are not yet confirmed against a live completion.** `#usage_event` reads Google's `usageMetadata` block (`promptTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount`, `cachedContentTokenCount`), which is what every other client of this Code Assist backend receives — but no Antigravity completion has been observed on the wire, because the account available for testing fails Antigravity's own eligibility check (see below). Confirm the names against a real run before trusting the numbers.
- Cost is left at zero on purpose. Antigravity bills against a subscription quota rather than per token, and Google publishes no per-token price for this backend, so tokens are recorded and cost is not invented. `fetchAvailableModels` does return a per-model `quotaInfo` (`remainingFraction`, `resetTime`), which is the natural source for a future `#fetch_subscription_usage`.

Build from the `docker/` directory:

```sh
docker build -f antigravity-cli/Dockerfile -t aixle/antigravity-cli:latest .
```

The image downloads the pinned `agy` 1.1.27 release and verifies Google's published SHA-256 checksum during each build. Record the emitted `agy --version` value with the published image digest for rollback traceability.

**The build-time pin does not hold at runtime.** `agy` runs its own background updater (`agy --bg-updater`) and overwrites `/usr/local/bin/agy` in place: a container started from this image on 2026-09-11 reported 1.1.27 on first launch and 1.2.1 a few minutes later, from the same image. So the checksum verified at build time says nothing about the binary a session actually runs, and a bad upstream release reaches production without an image rebuild. Disabling the updater needs a supported switch (none documented yet) — until then treat the pin as a floor, not a guarantee.
