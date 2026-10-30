# Agent Runtime Registry

`config/agent_runtimes.json` lists every built-in agent runtime — Claude Code, Cursor
CLI, Codex, Gemini CLI, Antigravity CLI, Grok, Kiro CLI — with the CLI version its image
installs. It is the one place a runtime is enumerated for the build and for the app's
runtime list: CI builds an image per entry, and the app validates, launches and
describes runtimes from the same file. Before it existed, the runtime set was written out
by hand in the image workflow, the canary script, the `Makefile`, the Ruby constant, the
frontend list and the deployment repository's build matrix, and the copies disagreed:
Antigravity shipped without a published image until 2026-09-17, and the deployment
repository's matrix still lacked it after that.

## Fields

| Field | Meaning |
| --- | --- |
| `id` | The runtime's identifier everywhere in the app: `agent_type`, `required_agent_runtime`, `selected_agents`. Never rename one — it is stored in rows. |
| `label` | Short name for pickers, tables and badges. |
| `product_name` | The product's own name, where the runtime is introduced (profile, onboarding). |
| `vendor` | Who makes the CLI. |
| `description` | One line shown where a user connects the runtime. |
| `image` | Image name. Published as `ghcr.io/aixlehq/flow-<image>`; the app resolves it as `AGENT_IMAGE_PREFIX` + `<image>` (+ `:AGENT_IMAGE_TAG`). |
| `dockerfile` | Dockerfile path, built with `docker/` as the context. |
| `cli_version` | The CLI release the image installs, passed as the `CLI_VERSION` build arg. `null` would mean the image installs whatever the vendor ships that day, so the image tag, not the registry, fixes what a deployment runs; every runtime is pinned today. |
| `cli_latest` | Where the weekly canary finds the vendor's newest release (`bin/agent-cli-latest` reads it): `{ "npm": "<package>" }`, or `{ "url": "<endpoint>" }` with a body that is the version, or that URL plus `"jq": "<filter>"` for a JSON body (Kiro's manifest) or `"pattern": "<regex>"` whose first group is the version (Cursor's install script, the only place it publishes one). `null` means the canary builds the pin. |
| `cli_releases` | Where the vendor's release notes are. `{ "github": "<owner/repo>", "tag_prefix": "<prefix before the version>" }`: the canary report quotes them, and they give the newest version when `cli_latest` is `null`; pre-releases and tags that are not `X.Y.Z` are ignored. `{ "url": "<changelog page>" }`: the report links it. |
| `reasoning_effort` | The reasoning-effort levels the pinned CLI takes, which a step's or a session's `reasoning_effort` is checked against and which the UI offers: `levels` (in order, for the CLI's default model and any model no rule names), `requires_model` (the CLI can only attach a level to a model the session names), and `models`, a list of `{ "match": "<regex on the model id>", "levels": [...] }` rules where the first match wins and `[]` means that model has none. `AgentRuntime#reasoning_effort_levels` and `reasoningEffortLevels` (`app/frontend/shared/ui/agentRuntimes.ts`) apply the same rule. See [Reasoning effort](#reasoning-effort). |

## Who reads it

| Consumer | Uses |
| --- | --- |
| `AgentRuntime` (`app/models/agent_runtime.rb`) | `ids` is `CompanyMembership::AVAILABLE_AGENTS`, which steps, sessions, credentials and the generated TypeScript unions validate against. `fetch(id).image` names the image `AgentBaseStrategy#resolve_image` launches. `Codex::Api::CLIENT_VERSION` is the Codex pin. `reasoning_effort_levels(model)` is what a step's or session's reasoning effort is validated against. |
| `app/frontend/shared/ui/agentRuntimes.ts` | Order, labels and copy of `AGENT_RUNTIMES`, and the levels the reasoning-effort select offers. Badge colors stay in the frontend. |
| `.github/workflows/images.yml` | The `agent-images` build matrix, the `CLI_VERSION` build arg, the canary's newest-release lookup (`bin/agent-cli-latest`), and its update report (`bin/agent-cli-report`). |
| `bin/build-agent-images` (`make build-agents`) | Local builds, with the same build args. |
| The deployment repository | Its agent image build matrix, read from the release tag it deploys. |

`test/config/agent_runtimes_registry_test.rb` checks what still names runtimes by hand:
every Dockerfile exists and takes `ARG CLI_VERSION` with no default, a Dockerfile that
keeps per-release checksums has a pair for its pin, and `agents.images`
overrides plus both launch command maps cover every runtime. The Dependabot directory
list is not checked — the test image is built without `.github/` — so step 1 below is
on the reviewer.

## Reasoning effort

A step (`steps.reasoning_effort`, next to `preferred_model`, part of the step's version
snapshot) and a standalone session (`terminal_sessions.reasoning_effort`, set from the
new-session form and `POST /api/v1/terminal_sessions`) can name a reasoning-effort level.
Unset is the CLI's own default, and the launch command is then exactly what it was before
the setting existed.

A level applies only to a model chosen explicitly: a step's `preferred_model`, or a
session's `requested_model`. With the model left on Default the UI hides the select, the
level is not validated, and the launch ignores a saved one, for standalone sessions and
workflow steps alike. The level is not checked against the credential's default model,
because that can change at any time and every saved level would then need re-checking. An
effort for the default model, if it is ever needed, belongs next to the default model in
the agent profile.

A step's session copies its step's level when the step names a model. Because a step can
leave its runtime to resolution, the launch checks the level again against the resolved
runtime and model (`TerminalSession#launch_reasoning_effort`) and launches on the CLI's
default when they do not take it.

Each CLI was checked at its pin, on the binary the image installs (help text, a launch
with a bad level, the strings or bundled source of the release), not only in the vendor's
docs:

| Runtime | Pin | How the level is set | Levels offered | Depends on the model |
| --- | --- | --- | --- | --- |
| Claude Code | 2.1.310 | `claude --effort <level>` | low, medium, high, xhigh, max | Yes: xhigh and max exist on some models only, and the CLI steps an unsupported level down silently. An unknown word is a warning, and the session runs at the default. |
| Cursor CLI | 2026.10.22-27dcf5f | No flag. A parameterized model takes it as a bracket override: `agent --model 'claude-opus-4-8[effort=high]'` | low, medium, high, and only with an explicit model | Yes: the parameters a model takes come from Cursor's backend (`--list-models`, signed in). The common levels are offered. With no model there is nothing to attach the level to, and a model id that already carries `[...]` keeps its own overrides. |
| Codex | 0.164.0 | No flag: the `model_reasoning_effort` config key, passed as `codex -c model_reasoning_effort=<level>` | low…xhigh; up to max on `gpt-6-luna` / `gpt-5.6-luna`; up to ultra on the Sol, Terra, Astra and Daybreak models | Yes: from the model catalog bundled in the binary (`supported_reasoning_levels`). The CLI's enum also has `none` and `minimal`, which no bundled model lists. |
| Gemini CLI | 0.60.0 | No flag: `modelConfigs.customOverrides` in `~/.gemini/settings.json`, matching the `chat-base-3` alias with `thinkingConfig.thinkingLevel` `LOW` or `HIGH` (written by `GeminiCliAdapter#generate_settings`) | low, high | Yes: Gemini 3 models take a thinking level (HIGH is the default), Gemini 2.5 models take a token budget instead, which this setting does not cover, so `gemini-2.*` offers none. Matching the alias keeps the level off the CLI's internal utility calls. |
| Antigravity CLI | 1.4.7 | `agy --effort <level>` | low, medium, high | Yes: the CLI's grammar is low…max, but each model has its own variants, and the CLI refuses a level its model lacks (`--effort=… is not supported for model …`). Without a signed-in account the per-model list cannot be read, so only the levels every model offers are offered. |
| Grok | 1.0.70 | `grok --reasoning-effort <level>` (alias `--effort`), honoured in the TUI as well as headless | low, medium, high, xhigh | Yes: the model catalogue says which models support it, and a model without reasoning effort ignores the flag. |
| Kiro CLI | 2.34.0 | `kiro-cli chat --effort <level>` | low, medium, high, xhigh, max; claude-sonnet-4.6 has no xhigh; `auto` and the Haiku models have none | Yes, checked live on 2.34.0: an unsupported level prints `failed to set effort` and the session continues at the default. |

Every runtime supports a level in some form. The UI disables the select, with the
reason, where the chosen runtime and model offer none: Gemini 2.5 models, and Kiro's
`auto` and Haiku models.

The registry does not keep a full per-model matrix. Where a vendor decides per model
whether a level is honoured (Claude Code's xhigh and max, Grok's models without reasoning
effort, Cursor's backend parameters), it lists the levels the CLI accepts, and the CLI may
lower or ignore a level the model doesn't support. The select says so under the field.

When a pin is raised, re-check the CLI's levels and update `reasoning_effort` with it:
`--help` for a flag, a launch with a bogus level for the accepted list, and for Codex the
bundled catalog's `supported_reasoning_levels`. A level no runtime had before must also be
added to the `reasoning_effort` enum of the template schema
(`config/templates/template.v1.json`); `Templates::ValidatorTest` fails until the two lists
match.

## Raising a CLI pin

Edit `cli_version`. The Dockerfiles carry no default, so the registry is the only pin; a
Docker build without the arg fails with a message naming the file.
Antigravity and Kiro need a second edit: their downloads are checksum-verified, so
`docker/antigravity-cli/Dockerfile` and `docker/kiro-cli/Dockerfile` keep a checksum pair
per release, and the registry test fails while the pin has none. Kiro publishes checksums
only for its latest release (in `stable/latest/manifest.json`), so its Dockerfile also
accepts a version without a pair while it is the channel's latest, checked against that
manifest; that is how the canary builds Kiro's newest. Cursor publishes no checksums, so
its pin is the versioned package URL alone.

For the runtimes whose usage arrives over OTLP (Claude Code, Codex, Gemini CLI), re-capture
what the new CLI exports: `make build-agents`, then `bin/capture-agent-otlp <id>` writes
`test/fixtures/files/otlp/<id>-<version>.json` (the CLI answers one prompt against a mock
model API, its telemetry relayed through `docker/otlp-ingest`).
`test/services/agents/otlp_contract_test.rb` parses that fixture with the real adapter and
fails while the pinned version has none — so a renamed metric or attribute is caught in CI,
not in production usage numbers.

Read the vendor's release notes between the two versions against the adapter too, for more
than credentials: a CLI can keep its login files and telemetry and still change a default
that blocks a headless session or hides its output (Gemini CLI 0.61's build-file prompt
under `--yolo`, Codex 0.157's background server and alternate-screen transcript), or drop
a setting the image relies on (Antigravity 1.1.28 no longer reads `enableTelemetry`).

Then start the old and the new image the way a session does — the adapter's config files
and launch command in the `agent` tmux pane, for an interactive, an automatic and a login
container — with a credential that is not valid, and compare the panes. Each should stop at
its login screen or its authentication error, and the new image should show nothing the old
one did not: no onboarding step, no dialog, no update notice. Check the CLI binary is still
the pinned release afterwards, too; Antigravity replaced its own within a second.

The Monday canary (`canary-YYYYMMDD` tags) builds the newest releases and keeps one issue
labelled `agent-cli-updates` up to date: each pin against the vendor's newest release,
the version the canary actually built and whether that build passed, and the vendor's
release notes for every release in between. A lookup of the newest release that fails
shows as **lookup failed** and keeps the issue open; it closes once every pin is current.
`bin/agent-cli-report` prints the same report locally (needs `jq`, `curl` and an
authenticated `gh`). A green canary build for a runtime is the signal its pin can be
raised.

## Adding a runtime

1. Add an entry here, a `docker/<image>/` directory, and the directory to the Docker
   entry in `.github/dependabot.yml`.
2. Write the adapter and the launch commands, as `docs/project/context.md` describes.
3. Add the `AGENT_IMAGE_<ID>` override to `config/settings.yml`, a row in
   `docs/reference/configuration.md`, and the runtime to `AgentType`
   (`app/frontend/shared/ui/types.ts`) with a badge color.

Nothing else enumerates runtimes: CI, the local build and the deployment repository pick
the new entry up from this file.
