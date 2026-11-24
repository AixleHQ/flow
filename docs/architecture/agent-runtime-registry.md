# Agent Runtime Registry

`config/agent_runtimes.json` lists every built-in agent runtime — Claude Code, Cursor
CLI, Codex, Gemini CLI, Antigravity CLI, Grok, Kiro CLI, GitHub Copilot CLI — with the CLI version its image
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
| `platforms` | Optional. The platforms the runtime's image is built for, a subset of `["linux/amd64", "linux/arm64"]` that includes `linux/amd64`. Left out, it is both, and CI builds one multi-arch index. Set it to `["linux/amd64"]` for a runtime whose CLI has no arm64 build, and say why in the commit: the runner then falls back to `linux/amd64` for that image, which an arm64 machine runs under emulation. Every runtime installs for arm64 today (checked 2026-11-14), so none sets it. |
| `cli_version` | The CLI release the image installs, passed as the `CLI_VERSION` build arg. `null` would mean the image installs whatever the vendor ships that day, so the image tag, not the registry, fixes what a deployment runs; every runtime is pinned today. |
| `cli_latest` | Where the weekly canary finds the vendor's newest release (`bin/agent-cli-latest` reads it): `{ "npm": "<package>" }`, or `{ "url": "<endpoint>" }` with a body that is the version, or that URL plus `"jq": "<filter>"` for a JSON body (Kiro's manifest) or `"pattern": "<regex>"` whose first group is the version (Cursor's install script, the only place it publishes one). `null` means the canary builds the pin. |
| `cli_releases` | Where the vendor's release notes are. `{ "github": "<owner/repo>", "tag_prefix": "<prefix before the version>" }`: the canary report quotes them, and they give the newest version when `cli_latest` is `null`; pre-releases and tags that are not `X.Y.Z` are ignored. `{ "url": "<changelog page>" }`: the report links it. |
| `reasoning_effort` | The reasoning-effort levels the pinned CLI takes, which a step's or a session's `reasoning_effort` is checked against and which the UI offers: `levels` (in order, for any model no rule names), and `models`, a list of `{ "match": "<regex on the model id>", "levels": [...] }` rules where the first match wins and `[]` means that model has none. `AgentRuntime#reasoning_effort_levels(model)` applies the rule, the only place that does, and returns no level for a blank model. A runtime that takes no level at all carries a `note` instead, saying where its effort is chosen, which the step editor and the new-session form show under the disabled select. See [Reasoning effort](#reasoning-effort). |

## Who reads it

| Consumer | Uses |
| --- | --- |
| `AgentRuntime` (`app/models/agent_runtime.rb`) | `ids` is `CompanyMembership::AVAILABLE_AGENTS`, which steps, sessions, credentials and the generated TypeScript unions validate against. `fetch(id).image` names the image `AgentBaseStrategy#resolve_image` launches, and the one `ContainerRuntime::RunnerRuntime` starts for a runner session. `Codex::Api::CLIENT_VERSION` is the Codex pin, and `Antigravity::Api::USER_AGENT` carries the Antigravity pin to the model catalogue endpoint. `Sessions::Checkpoint` records a suspended session's `cli_version`, and `Sessions::Restore` resumes its conversation only under the same pin. `reasoning_effort_levels(model)` is what a step's or session's reasoning effort is validated against, and what `CompanyMembership#agent_models_for_props` puts on each model option as `reasoning_effort_levels`. The class method `AgentRuntime.reasoning_effort_levels`, the union of every runtime's levels, is only the enum of the `create_workflow_step` and `update_workflow_step` MCP tools. |
| `app/frontend/shared/ui/agentRuntimes.ts` | Order, labels and copy of `AGENT_RUNTIMES`. Badge colors stay in the frontend. The reasoning-effort select does not read the registry: it offers the `reasoningEffortLevels` the server sent on the selected model option. |
| `.github/workflows/images.yml` | The `agent-images` build matrix (with each runtime's `platforms`), the `CLI_VERSION` build arg, the canary's newest-release lookup (`bin/agent-cli-latest`), and its update report (`bin/agent-cli-report`). |
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

Two rules apply, on steps and sessions alike:

1. A level can be set only when both the runtime and the model are chosen explicitly: a
   step's `required_agent_runtime` and `preferred_model`, or a session's `agent_type` and
   `requested_model`.
2. A level that is set must be one this runtime's CLI takes for some model: its grammar,
   `AgentRuntime#reasoning_effort_grammar` (every level in `reasoning_effort`, rules
   included).

Which levels a given model takes is the vendor's to say, per account, and a step does not
know which account will run it, so the model pickers apply that and the validator does
not. Each adapter puts the levels its vendor's catalogue lists on a model entry
(`reasoning_effort_levels`); `AgentRuntime#reasoning_effort_levels(model, offered:)` keeps
them to the grammar, and falls back to the registry's rule for the model when the
catalogue does not say (task #324):

| Runtime | Where a model's levels come from |
| --- | --- |
| Claude Code | Anthropic's `/v1/models`, `capabilities.effort` (`supported`, then one entry per level) |
| Codex | the Codex models API, `supported_reasoning_levels[].effort` |
| Copilot CLI | the CLI's ACP `reasoning_effort` option per model, captured into the credential's metadata (`docker/copilot-cli/aixle-copilot-models.mjs`) |
| Grok | for a signed-in account, the CLI proxy's `/v1/models`, `supports_reasoning_effort` and `reasoning_efforts`; an API key's public catalogue says nothing, so the rule |
| Kiro CLI | the API's `ListAvailableModels`, the `effort` enum in `additionalModelRequestFieldsSchema` (none without a schema); the CLI's own list carries none |
| Gemini CLI | the models API says only `thinking`: a model that does not think takes none, the rule decides the rest |
| Cursor CLI, Antigravity CLI | none: the model id carries the effort |

`ReasoningEffortValidator` checks both rules, with one message per failure, so the REST API and
the MCP tools answer 422. A step is checked on every save; a session, workflow step
sessions included, when it is created. Clearing the model or the runtime while a level is
set is refused the same way, so the caller clears the level with them. The step editor
and the new-session form hide the select until a model is chosen. They offer the levels
the server put on that model option (`CompanyMembership#agent_models_for_props`), so the
rule is evaluated only on the server, and a model switch clears a level the new model
doesn't take (Default takes none). A saved step whose model the credential doesn't list
shows its level with the levels marked unknown. The level is never checked against the
credential's default model, because that can change at any time and every saved level
would then need re-checking. An effort for the default model, if it is ever needed,
belongs next to the default model in the agent profile.

A step's session copies its step's runtime, model and level, and the launch and the
generated CLI config both read the model from the session's captured `requested_model`,
not from the live step. Both pass `session.reasoning_effort` to the adapter as it is.

Each CLI was checked at its pin, on the binary the image installs (help text, a launch
with a bad level, the strings or bundled source of the release), not only in the vendor's
docs:

| Runtime | Pin | How the level is set | Levels offered | Depends on the model |
| --- | --- | --- | --- | --- |
| Claude Code | 2.1.329 | `claude --effort <level>` | low, medium, high, xhigh, max | Yes, from Anthropic's catalogue (above): on 2026-11-21 the 4.6 Opus and Sonnet had no xhigh, the 4.5 Opus stopped at high, the 4.5 Haiku and Sonnet had none. The CLI steps an unsupported level down to high, or drops it, silently. An unknown word is a warning, and the session runs at the default. |
| Cursor CLI | 2026.11.19-f005e9d | None: the effort is part of the model id (`claude-opus-5-5-low`, `gpt-5.2-high`), and the model list offers every variant | none | Yes, and per model: Cursor's `AvailableModels` (`useModelParameters`) gives each model its own parameters (`effort` on Claude models, `reasoning` with `extra-high` on GPT models, only `fast` on Composer). A bracket override is accepted only as a model's complete variant string (`claude-opus-5-5[context=300k,effort=low,fast=false]`); a partial one (`composer-2.5[effort=low]`, `claude-opus-4-8[effort=low]`) makes the CLI print "Cannot use this model" and exit, checked live 2026-11-21 (task #324). |
| Codex | 0.171.0 | No flag: the `model_reasoning_effort` config key, passed as `codex -c model_reasoning_effort=<level>` | low…xhigh; up to max on `gpt-6-luna` / `gpt-5.6-luna`; up to ultra on the Sol, Terra, Astra and Daybreak models | Yes: from the model catalog bundled in the binary (`supported_reasoning_levels`). The CLI's enum also has `none` and `minimal`, which no bundled model lists. |
| Gemini CLI | 0.60.0 | No flag: `modelConfigs.customOverrides` in `~/.gemini/settings.json`, matching the `chat-base-3` alias with `thinkingConfig.thinkingLevel` `LOW` or `HIGH` (written by `GeminiCliAdapter#generate_settings`) | low, high | Yes: Gemini 3 models take a thinking level (HIGH is the default), Gemini 2.5 models take a token budget instead, which this setting does not cover, so `gemini-2.*` offers none. Matching the alias keeps the level off the CLI's internal utility calls. |
| Antigravity CLI | 1.5.13 | None: the effort is part of the model id (`gemini-3.8-flash-low`), and the model list offers every variant | none | Yes, and per model: `fetchAvailableModels` gives a model group its levels (`gemini-3.8-flash`: low, medium, high; the Claude and GPT-OSS models none). `--effort` applies only to a group (`--model gemini-3.8-flash --effort low`, or no `--model`); with a model id, a level the model lacks, or an unknown model, the TUI runs the account's default model and only its log says why, while print mode exits 1. Checked live 2026-11-21 (task #324). |
| Grok | 1.0.89 | `grok --reasoning-effort <level>` (alias `--effort`), honoured in the TUI as well as headless | low, medium, high, xhigh | Yes: the model catalogue says which models support it (`reasoning_efforts` on the CLI proxy's list), and a model without reasoning effort ignores the flag. A model the account lacks runs the default model, so the session checks it against the catalogue when it is created. |
| Kiro CLI | 3.5.0 | `kiro-cli chat --effort <level>` | low, medium, high, xhigh, max; the rules (`auto` and the Haiku models none, claude-sonnet-4.6 no xhigh) only stand in when the API does not answer | Yes, from the API's request schema per model (above). An unsupported level is lowered to high, or dropped on a model with none (3.5.0, 2026-11-21; 2.34.0 printed `failed to set effort`). |
| Copilot CLI | 1.0.114 | `copilot --reasoning-effort <level>` | low, medium, high, xhigh, max; GPT-5.3-Codex and the Grok models stop at xhigh; Gemini and MAI models take low, medium and high; `auto` and Claude Haiku 4.5 have none (some GPT models also take `none`, which is not offered) | Yes: read for every model of the account's catalogue from the CLI's ACP `reasoning_effort` option (`docker/copilot-cli/aixle-copilot-models.mjs`), 2026-11-10. The catalogue is per plan, so a model missing here falls under the default levels. |

Every runtime but Cursor CLI and Antigravity CLI takes a level; those two take the effort
through the model id. The UI disables the select, with the reason, where the chosen
runtime and model offer none: every Cursor and Antigravity model (with the registry's
`note`), Gemini 2.5 models, and Kiro's `auto` and Haiku models.

The registry does not keep a per-model matrix: the catalogues above are the per-model
truth, and the registry's rules only stand in when one does not answer. A level the select
offers from a rule may still be lowered or ignored by the CLI, and the select says so under
the field. A CLI that exits on a combination it refuses fails the step at once
(`Sessions::Checks::AgentExited`, in `docs/architecture/workflows.md`).

When a pin is raised, re-check the CLI's levels and update `reasoning_effort` with it:
`--help` for a flag, a launch with a bogus level for the accepted list, and for Codex the
bundled catalog's `supported_reasoning_levels`. The template schema
(`config/templates/template.v1.json`) types `reasoning_effort` only as a string;
`Templates::Validator#check_reasoning_efforts` checks the level against the step's runtime
and model through `AgentRuntime`, so a new level needs no schema edit. A level the new pin no longer takes (for the CLI or for one model) comes with a data
migration that clears or replaces it on the steps that have it, because a step is validated
on every save and would otherwise refuse unrelated edits.

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

For the runtimes whose usage arrives over OTLP (Claude Code, Codex, Gemini CLI, Copilot CLI), re-capture
what the new CLI exports: `make build-agents`, then `bin/capture-agent-otlp <id>` writes
`test/fixtures/files/otlp/<id>-<version>.json` (the CLI answers one prompt against a mock
model API, its telemetry relayed through `docker/otlp-ingest`).
`test/services/agents/otlp_contract_test.rb` parses that fixture with the real adapter and
fails while the pinned version has none — so a renamed metric or attribute is caught in CI,
not in production usage numbers. Kiro CLI's credit telemetry also arrives over OTLP, but
neither the capture script nor the contract test covers Kiro, so nothing in CI catches a
renamed Kiro metric; its MITM-captured usage summaries and the account's credit counter are
the fallbacks ([index.md](./index.md#agent-adapters)).

A raised pin also changes what a restore does: `Sessions::Restore` resumes a suspended
session's conversation only when the `cli_version` recorded at suspension is the current
pin, so a session suspended before the raise restores with a fresh conversation. Its old
one stays as files in the CLI's home directory, which the restored session's notes name.

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
