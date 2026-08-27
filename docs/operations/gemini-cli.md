# Gemini CLI operations

## Decision

Aixle continues to use Gemini CLI for its `gemini_cli` runtime. The integration
authenticates with a company-scoped Google AI Studio API key through
`GEMINI_API_KEY` and selects `gemini-api-key` in `~/.gemini/settings.json`.
Google's June 2026 individual-account transition does not remove this supported
API-key path.

Antigravity CLI is therefore not a drop-in replacement for this runtime. Its
account authentication, executable, configuration directory, plugin model, and
telemetry contract differ. Supporting it should be a separate runtime and adapter
rather than changing the meaning of `gemini_cli` or silently migrating stored
credentials.

## Runtime contract

- Image package: `@google/gemini-cli@0.57.0`, pinned in the Dockerfile.
- Executable: `gemini`.
- Authentication: `GEMINI_API_KEY`; personal OAuth is not captured or injected.
- Configuration: `/home/gemini/.gemini/settings.json`.
- Context: `/home/gemini/.gemini/GEMINI.md`.
- Skills: `/home/gemini/.gemini/skills`.
- Folder trust: `/home/gemini/.gemini/trustedFolders.json`.
- MCP: `mcpServers` merged into the settings file; stdio and HTTP transports are supported.
- Invocation: `gemini --yolo`, with an optional `--model` argument.
- Hooks and extensions: provided by the upstream CLI; Aixle does not rewrite their config.
- Telemetry: local OTLP metrics/logs are correlated with `terminal_session_token`.

Gemini CLI 0.57.0 migrated the deprecated `tools.approvalMode` setting to
`general.defaultApprovalMode`. Aixle writes the current setting and retains the
explicit `--yolo` invocation so container sessions remain non-blocking.

## Verification

After building the image, run:

```sh
docker run --rm --entrypoint gemini aixle/gemini-cli:latest --version
docker run --rm --entrypoint gemini aixle/gemini-cli:latest --help
```

The version must be `0.57.0`; help must list `--model`, `--yolo`, `mcp`, `skills`,
and `hooks`. For an authenticated end-to-end smoke test, inject a test API key and
run headlessly without printing the key:

```sh
docker run --rm -e GEMINI_API_KEY --entrypoint gemini \
  aixle/gemini-cli:latest --yolo --output-format json -p \
  'Reply with exactly AIXLE_GEMINI_OK'
```

The command must exit zero and return `AIXLE_GEMINI_OK`. A 401/403 indicates an
invalid or unsupported key; an individual-account migration message indicates an
OAuth credential was used instead of the required API-key mode.

## Upgrade and rollback

To upgrade, change `GEMINI_CLI_VERSION`, build the image, run the adapter tests and
the image/E2E checks above, then publish the immutable image before updating the
deployment. Review upstream changes to settings, authentication, MCP, skills,
hooks, invocation flags, Node requirements, and OTLP event names on every upgrade.

To roll back, deploy the previous immutable Gemini image digest. If a source
rollback is needed, revert the version pin and settings migration together, rebuild,
and repeat the smoke test. Do not delete or transform stored company API keys, so
rollback requires no credential migration.
