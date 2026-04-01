# BMAD Method Checkbox Integration

**Date:** 2026-03-16
**Status:** Approved Plan
**Author:** Artem Petrov + AI Analysis
**Depends on:** [system-workflow-bmad-integration.md](./system-workflow-bmad-integration.md), [session-context-constructor.md](./session-context-constructor.md)

---

## 1. Goal

Add a **"Use BMAD Method"** checkbox when launching a standalone session and in the workflow step configuration. When enabled — automatically install BMAD Method into the container via the official npm CLI, ensuring:

- Slash commands (`/brainstorming`, `/create-prd`, `/dev-story`, etc.) work out of the box
- The Aixle context (user, language, project) is seamlessly passed through into the BMAD config
- BMAD files are invisible to the user in VS Code
- BMAD artifact output goes to `/workspace/outputs/` for reuse in the pipeline

---

## 2. Key decision: we use `npx bmad-method install`

BMAD Method v6.2 provides an npm CLI with a **non-interactive install mode**:

```bash
npx bmad-method install \
  --directory /workspace \
  --modules bmm,cis,bmb \
  --tools cursor \
  --user-name "Artem" \
  --communication-language Russian \
  --document-output-language English \
  --output-folder /workspace/outputs \
  --yes
```

### What the installer does automatically

1. Copies `_bmad/` (core + selected modules) into `--directory`
2. Generates **skills** into IDE-specific folders:
   - Cursor: `.cursor/skills/<name>/SKILL.md`
   - Claude Code: `.claude/skills/<name>/SKILL.md`
   - Codex: `.agents/skills/<name>/SKILL.md`
   - Gemini: `.gemini/skills/<name>/SKILL.md`
3. Patches `config.yaml` with the user settings
4. Generates manifests (agent-manifest.csv, workflow-manifest.csv, etc.)

### Advantages

- We don't write our own installer — we use the official CLI, always the latest version
- Automatic support for new community modules
- Correct format for each IDE — the CLI knows 20+ IDEs
- BMAD updates for free — a new npm version = new workflows
- Non-interactive mode — ideal for the container

---

## 3. Mapping agent_type → BMAD tools flag

| Aixle `agent_type` | BMAD `--tools` flag | Skills directory |
|---------------------|---------------------|----------------------------------|
| `cursor_cli` | `cursor` | `.cursor/skills/<name>/SKILL.md` |
| `claude_code` | `claude-code` | `.claude/skills/<name>/SKILL.md` |
| `codex` | `codex` | `.agents/skills/<name>/SKILL.md` |
| `gemini_cli` | `gemini` | `.gemini/skills/<name>/SKILL.md` |

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  "Use BMAD Method" checkbox (UI: session launch / step config)        │
│                                                                      │
│  What happens on assemble_session_context:                       │
│                                                                      │
│  1. RUN in the container:                                               │
│     npx bmad-method install \                                       │
│       --directory /workspace \                                       │
│       --modules bmm,cis,bmb \                                       │
│       --tools <agent_type_mapped> \                                  │
│       --user-name "<user.display_name>" \                            │
│       --communication-language "<user.locale>" \                     │
│       --output-folder /workspace/outputs \                           │
│       --yes                                                          │
│                                                                      │
│  2. The installer automatically:                                        │
│     - Creates /workspace/_bmad/ with all modules                   │
│     - Generates skills into the correct IDE-specific folders         │
│     - Patches config.yaml with our values                        │
│     - Generates manifests                                           │
│                                                                      │
│  3. POST-INSTALL (BmadMethodInjector):                              │
│     - files.exclude in VS Code settings: _bmad, .cursor/skills, etc │
│     - A section in the context file (AGENTS.md/CLAUDE.md)              │
│       via ContextBuilders::BmadMethod                             │
│                                                                      │
│  4. Result:                                                       │
│     - Slash commands work (/brainstorming, /create-prd...)       │
│     - The agent knows about BMAD through the context                           │
│     - Output goes to /workspace/outputs/                     │
│     - The files are hidden from the user                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Code changes

### 5.1 DB: Migration

```ruby
# terminal_sessions — add to the session_config jsonb
# session_config["bmad_enabled"] = true/false
# session_config["bmad_modules"] = ["bmm", "cis", "bmb"] (optional, default: all)

# steps — add a field
add_column :steps, :bmad_enabled, :boolean, default: false
```

For `terminal_sessions` we use the existing `session_config` jsonb — no separate column is needed.

### 5.2 SessionConfigResolver

Resolve `bmad_enabled` from the step (for workflow) or from session_config (for standalone):

```ruby
def resolve_bmad_enabled
  return session.session_config&.dig("bmad_enabled") if standalone_session?

  step&.bmad_enabled || false
end
```

### 5.3 BmadMethodInjector (new service)

```ruby
class BmadMethodInjector
  AGENT_TYPE_TO_BMAD_TOOL = {
    "cursor_cli" => "cursor",
    "claude_code" => "claude-code",
    "codex" => "codex",
    "gemini_cli" => "gemini"
  }.freeze

  BMAD_HIDDEN_PATHS = %w[
    _bmad
    _bmad-output
    .cursor/skills
    .claude/skills
    .agents/skills
    .gemini/skills
  ].freeze

  def initialize(container_id, session, runtime:)
    @container_id = container_id
    @session = session
    @runtime = runtime
  end

  def inject!
    run_bmad_install
    hide_bmad_in_vscode
  end

  private

  def run_bmad_install
    tool = AGENT_TYPE_TO_BMAD_TOOL[@session.agent_type]
    user = @session.user
    modules = resolve_modules.join(",")

    cmd = [
      "npx", "bmad-method", "install",
      "--directory", "/workspace",
      "--modules", modules,
      "--tools", tool,
      "--user-name", user.display_name || user.email,
      "--communication-language", resolve_language,
      "--document-output-language", "English",
      "--output-folder", "/workspace/outputs",
      "--yes"
    ]

    @runtime.exec(@container_id, cmd)
  end

  def resolve_modules
    @session.session_config&.dig("bmad_modules") || %w[bmm cis bmb]
  end

  def resolve_language
    # TODO: from user settings or session_config
    "English"
  end

  def hide_bmad_in_vscode
    # Add to VS Code settings files.exclude
    # to hide the _bmad/ and skills directories
  end
end
```

### 5.4 SessionContextService — new step

In `assemble_session_context`, after repositories (step 7), before the context log:

```ruby
# Step 7.5: BMAD Method
if SessionConfigResolver.new(session).resolve_bmad_enabled
  measure_step("bmad_method") { inject_bmad_method(container_id, session) }
end
```

### 5.5 ContextBuilders::BmadMethod (new builder)

Add to `SessionContextConstructor::BUILDERS` after `Resources`:

```ruby
module ContextBuilders
  class BmadMethod < Base
    def applicable?
      SessionConfigResolver.new(session).resolve_bmad_enabled
    end

    def build
      [section(
        tag: "bmad-method",
        priority: :info,
        content: build_bmad_context
      )]
    end

    private

    def build_bmad_context
      <<~MD
        ## BMAD Method

        The BMAD Method (Breakthrough Method of Agile AI-driven Development) is installed
        and available in this session. You have access to slash-commands for structured
        workflows covering the full product development lifecycle.

        - BMAD files: `/workspace/_bmad/`
        - BMAD config: `/workspace/_bmad/core/config.yaml`
        - Output folder: `/workspace/outputs/`

        Use the available skills/commands to invoke BMAD workflows (e.g. brainstorming,
        create-prd, create-architecture, dev-story, etc.).
        All BMAD output must go to `/workspace/outputs/`.
      MD
    end
  end
end
```

### 5.6 VS Code Settings — files.exclude

In `docker/base/vscode-settings.json` or dynamically in `BmadMethodInjector#hide_bmad_in_vscode`:

```json
{
  "files.exclude": {
    "_bmad": true,
    "_bmad-output": true,
    "_bmad/_config": true,
    ".cursor/skills": true,
    ".claude/skills": true,
    ".agents/skills": true,
    ".gemini/skills": true
  }
}
```

### 5.7 Frontend

- `SessionLaunchWidget` — add a "Use BMAD Method" toggle
- Step editor (workflow builder) — add a "Use BMAD Method" toggle
- Both pass `bmad_enabled: true` into session_config / step

### 5.8 Docker — Node.js in the container

We need to ensure that Node.js (v20+) is installed in the agent container images.
`npx` must be available. Check the current Dockerfiles.

---

## 6. Hiding from the user

| What we hide | How |
|---|---|
| `_bmad/` directory | `files.exclude` in VS Code settings |
| `.cursor/skills/` (BMAD skills) | `files.exclude` in VS Code settings |
| `.claude/skills/` | `files.exclude` |
| `.agents/skills/` | `files.exclude` |
| `.gemini/skills/` | `files.exclude` |
| `_bmad-output/` | `files.exclude` + we rewrite output_folder to `/workspace/outputs/` |

At the same time, the agent (Cursor/Claude/Codex/Gemini) **sees** these files and can read them — skills work at the IDE agent level, not the VS Code file explorer.

---

## 7. Output → /workspace/outputs/

BMAD uses `output_folder` from config.yaml for all artifacts.
We set `--output-folder /workspace/outputs` → artifacts automatically land in the standard Aixle output directory.

The existing `collect_outputs` mechanism in `AgentSessionStrategy` picks up files from `/workspace/outputs/` and creates `Asset` records.

In the workflow pipeline, `WorkflowStepStrategy` passes outputs as `WorkflowRunAsset` to the next steps.

---

## 8. Extensibility (V2+)

### V2: Custom modules

The user can specify additional BMAD modules via `--custom-content`:
```bash
npx bmad-method install \
  --custom-content /workspace/repo/my-custom-module \
  ...
```

This allows connecting modules from the user's repository.

### V3: Module marketplace

At the platform level — a catalog of BMAD modules (npm packages).
The user selects which modules to connect in the UI.
`bmad_modules` in session_config stores the list of selected modules.

### V4: Full integration (System Workflows)

Described in [system-workflow-bmad-integration.md](./system-workflow-bmad-integration.md).
BmadModuleRegistry, agent mapping, composite workflows.

---

## 9. Time estimate

| Task | Duration |
|--------|------|
| Model + migration (`bmad_enabled` on steps, session_config) | 0.5 days |
| `BmadMethodInjector` (running npx in the container + post-install) | 1.5 days |
| `ContextBuilders::BmadMethod` | 0.5 days |
| VS Code settings (files.exclude for BMAD) | 0.5 days |
| Frontend — checkbox in SessionLaunchWidget + Step editor | 1 day |
| Docker — verify/add Node.js v20+ in agent images | 0.5 days |
| e2e testing (all 4 agent types) | 1 day |
| **Total** | **~5.5 days** |

---

## 10. Open questions

| # | Question | Proposal |
|---|--------|-------------|
| 1 | Is Node.js v20+ present in all agent container images? | Check the Dockerfiles. If not — add it to the base image. |
| 2 | Do we need to cache the BMAD install between sessions? | MVP: no, we install every time. V2: Docker layer cache or pre-baked image. |
| 3 | Which modules should be installed by default? | MVP: bmm (core methodology). Optionally: cis, bmb. |
| 4 | How should npx install errors be handled? | Log them, don't block the session. BMAD = nice-to-have, not critical path. |
| 5 | Do we need `--communication-language` from the user profile? | Yes, map it from user.locale or user.settings. MVP: English. |
| 6 | How long does npx bmad-method install take? | ~10-30 sec. Run it in parallel with other assemble_session_context steps if possible. |
