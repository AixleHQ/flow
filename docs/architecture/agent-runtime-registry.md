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

## Who reads it

| Consumer | Uses |
| --- | --- |
| `AgentRuntime` (`app/models/agent_runtime.rb`) | `ids` is `CompanyMembership::AVAILABLE_AGENTS`, which steps, sessions, credentials and the generated TypeScript unions validate against. `fetch(id).image` names the image `AgentBaseStrategy#resolve_image` launches. `Codex::Api::CLIENT_VERSION` is the Codex pin. |
| `app/frontend/shared/ui/agentRuntimes.ts` | Order, labels and copy of `AGENT_RUNTIMES`. Badge colors stay in the frontend. |
| `.github/workflows/images.yml` | The `agent-images` build matrix, the `CLI_VERSION` build arg, the canary's newest-release lookup (`bin/agent-cli-latest`), and its update report (`bin/agent-cli-report`). |
| `bin/build-agent-images` (`make build-agents`) | Local builds, with the same build args. |
| The deployment repository | Its agent image build matrix, read from the release tag it deploys. |

`test/config/agent_runtimes_registry_test.rb` checks what still names runtimes by hand:
every Dockerfile exists and takes `ARG CLI_VERSION` with no default, a Dockerfile that
keeps per-release checksums has a pair for its pin, and `agents.images`
overrides plus both launch command maps cover every runtime. The Dependabot directory
list is not checked — the test image is built without `.github/` — so step 1 below is
on the reviewer.

## Raising a CLI pin

Edit `cli_version` and nothing else. The Dockerfiles carry no default, so the registry is
the only pin; a Docker build without the arg fails with a message naming the file.
Antigravity and Kiro need a second edit: their downloads are checksum-verified, so
`docker/antigravity-cli/Dockerfile` and `docker/kiro-cli/Dockerfile` keep a checksum pair
per release, and the registry test fails while the pin has none. Kiro publishes checksums
only for its latest release (in `stable/latest/manifest.json`), so its Dockerfile also
accepts a version without a pair while it is the channel's latest, checked against that
manifest; that is how the canary builds Kiro's newest. Cursor publishes no checksums, so
its pin is the versioned package URL alone.

The Monday canary (`canary-YYYYMMDD` tags) builds the newest releases and keeps one issue
labelled `agent-cli-updates` up to date: each pin against the vendor's newest release,
the version the canary actually built and whether that build passed, and the vendor's
release notes for every release in between. It closes the issue once every pin is
current. `bin/agent-cli-report` prints the same report locally (needs `jq`, `curl` and an
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
