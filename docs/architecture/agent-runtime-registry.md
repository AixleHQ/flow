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
| `cli_version` | The CLI release the image installs, passed as the `CLI_VERSION` build arg. `null` means the vendor's installer only installs its newest release (Cursor, Kiro); the image tag, not the registry, then fixes what a deployment runs. |
| `cli_latest` | Where the weekly canary finds the vendor's newest release: `{ "npm": "<package>" }` or `{ "url": "<text endpoint>" }`. `null` means the canary builds the pin. |

## Who reads it

| Consumer | Uses |
| --- | --- |
| `AgentRuntime` (`app/models/agent_runtime.rb`) | `ids` is `CompanyMembership::AVAILABLE_AGENTS`, which steps, sessions, credentials and the generated TypeScript unions validate against. `fetch(id).image` names the image `AgentBaseStrategy#resolve_image` launches. `Codex::Api::CLIENT_VERSION` is the Codex pin. |
| `app/frontend/shared/ui/agentRuntimes.ts` | Order, labels and copy of `AGENT_RUNTIMES`. Badge colors stay in the frontend. |
| `.github/workflows/images.yml` | The `agent-images` build matrix, the `CLI_VERSION` build arg, and the canary's newest-release lookup. |
| `bin/build-agent-images` (`make build-agents`) | Local builds, with the same build args. |
| The deployment repository | Its agent image build matrix, read from the release tag it deploys. |

`test/config/agent_runtimes_registry_test.rb` checks what still names runtimes by hand:
every Dockerfile exists and takes `ARG CLI_VERSION` with no default, Dependabot watches
every runtime's directory, and `agents.images` overrides plus both launch command maps
cover every runtime.

## Raising a CLI pin

Edit `cli_version` and nothing else. The Dockerfiles carry no default, so the registry is
the only pin; a Docker build without the arg fails with a message naming the file.
Antigravity is the exception that needs a second edit: its download is checksum-verified,
so `docker/antigravity-cli/Dockerfile` keeps a checksum pair per release, and a raised pin
without one fails the build at that check.

A green Monday canary (`canary-YYYYMMDD` tags) is the signal a pin can be raised: it built
the newest releases and its run summary lists the version each image shipped.

## Adding a runtime

1. Add an entry here, a `docker/<image>/` directory, and the directory to the Docker
   entry in `.github/dependabot.yml`.
2. Write the adapter and the launch commands, as `docs/project/context.md` describes.
3. Add the `AGENT_IMAGE_<ID>` override to `config/settings.yml`, a row in
   `docs/reference/configuration.md`, and the runtime to `AgentType`
   (`app/frontend/shared/ui/types.ts`) with a badge color.

Nothing else enumerates runtimes: CI, the local build and the deployment repository pick
the new entry up from this file.
