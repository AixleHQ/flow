# Epic 33: BMAD Method — Standalone Session Integration

> User can enable "Use BMAD Method" when launching a standalone session. The system automatically installs BMAD in the container, hides its files from the user, and the agent gets access to BMAD slash-commands and skills. BMAD artifacts automatically flow into the standard output pipeline.

**Phase:** 19 (Depends on: Epic 25, 29, 8, 9)

**FRs covered:** FR1, FR3, FR4, FR5, FR6, FR7, FR8, FR9, FR10, FR12, FR13, FR15
**NFRs covered:** NFR5, NFR6

---

## Story 33.1: Data Model — bmad_enabled in session_config

As a **platform developer**,
I want `bmad_enabled` and `bmad_modules` stored in the existing `session_config` JSONB on `terminal_sessions`,
So that the system knows whether BMAD should be installed for a given session without requiring a new migration for sessions.

**Acceptance Criteria:**

**Given** a standalone session is being created with `bmad_enabled: true` in session_config
**When** the session record is persisted
**Then** `session.session_config["bmad_enabled"]` returns `true`
**And** `session.session_config["bmad_modules"]` defaults to `["bmm"]` if not explicitly provided

**Given** a standalone session is created without BMAD configuration
**When** the session record is persisted
**Then** `session.session_config["bmad_enabled"]` returns `nil` or `false`

**Given** the user specifies custom modules `["bmm", "cis", "bmb"]`
**When** the session is created
**Then** `session.session_config["bmad_modules"]` stores the exact array provided

**Implementation Notes:**
- No migration needed — `session_config` JSONB already exists on `terminal_sessions`
- Add model-level helper method `bmad_enabled?` to `TerminalSession`
- Add `BMAD_DEFAULT_MODULES = %w[bmm].freeze` constant

---

## Story 33.2: BmadMethodInjector — Install BMAD in Container

As a **developer using BMAD**,
I want the system to automatically install BMAD Method in my container when I enable the checkbox,
So that slash-commands and BMAD workflows are available without any manual setup.

**Acceptance Criteria:**

**Given** a session with `bmad_enabled: true` and agent_type `cursor_cli`
**When** BmadMethodInjector#inject! is called with the container_id
**Then** the system executes `npx bmad-method install` in the container with flags:
  - `--directory /workspace`
  - `--modules bmm` (or configured modules)
  - `--tools cursor`
  - `--user-name "<user.display_name>"`
  - `--communication-language "<resolved_language>"`
  - `--document-output-language English`
  - `--output-folder /workspace/outputs`
  - `--yes`

**Given** agent_type is `claude_code`
**When** BmadMethodInjector resolves the BMAD tools flag
**Then** the `--tools` flag is `claude-code`

**Given** agent_type is `codex`
**When** BmadMethodInjector resolves the BMAD tools flag
**Then** the `--tools` flag is `codex`

**Given** agent_type is `gemini_cli`
**When** BmadMethodInjector resolves the BMAD tools flag
**Then** the `--tools` flag is `gemini`

**Given** custom modules `["bmm", "cis", "bmb"]` are specified
**When** BmadMethodInjector builds the install command
**Then** the `--modules` flag is `bmm,cis,bmb`

**Implementation Notes:**
- Create `app/services/bmad_method_injector.rb`
- `AGENT_TYPE_TO_BMAD_TOOL` mapping constant as defined in PRD
- Uses `@runtime.exec(container_id, cmd)` for container execution
- Language resolution: use `user.preferred_agent_language` or fallback to `"English"`

---

## Story 33.3: Hide BMAD Files in VS Code

As a **developer**,
I want BMAD internal files hidden from the VS Code file explorer,
So that my workspace stays clean and I only see my project files.

**Acceptance Criteria:**

**Given** BMAD is installed in the container
**When** BmadMethodInjector#hide_bmad_in_vscode is called
**Then** the VS Code settings file (`.vscode/settings.json`) includes `files.exclude` entries for:
  - `_bmad`: true
  - `_bmad-output`: true
  - `.cursor/skills`: true
  - `.claude/skills`: true
  - `.agents/skills`: true
  - `.gemini/skills`: true

**Given** a `.vscode/settings.json` already exists with other settings
**When** BMAD exclude entries are added
**Then** existing settings are preserved and BMAD entries are merged in

**Given** no `.vscode/settings.json` exists
**When** BMAD exclude entries are added
**Then** a new `.vscode/settings.json` is created with only the BMAD exclude entries

**Implementation Notes:**
- Read existing settings, JSON.parse, merge `files.exclude`, write back
- Part of `BmadMethodInjector#inject!` — runs after `run_bmad_install`
- Uses `@runtime.exec` to read/write the file inside the container

---

## Story 33.4: ContextBuilders::BmadMethod

As an **AI agent in a BMAD-enabled session**,
I want a context section informing me about BMAD availability, config location, and output rules,
So that I can use BMAD slash-commands and produce artifacts in the correct location.

**Acceptance Criteria:**

**Given** a session with `bmad_enabled: true`
**When** SessionContextConstructor builds the context
**Then** a `<bmad-method>` section is included with priority `:info` and position_hint `:middle`

**Given** the BmadMethod builder is active
**When** the context section is rendered
**Then** it contains:
  - Reference to BMAD files location (`/workspace/_bmad/`)
  - Reference to BMAD config (`/workspace/_bmad/core/config.yaml`)
  - Reference to output folder (`/workspace/outputs/`)
  - Instruction to use available skills/commands for BMAD workflows
  - Note that all BMAD output must go to `/workspace/outputs/`

**Given** a session with `bmad_enabled: false` or nil
**When** SessionContextConstructor builds the context
**Then** no `<bmad-method>` section is included (builder returns `applicable? = false`)

**Given** the BmadMethod builder generates its section
**When** the XML-markdown is rendered
**Then** it follows the project's XML-structured format with proper `<bmad-method priority="info">` tags

**Implementation Notes:**
- Create `app/services/context_builders/bmad_method.rb`
- Register in `SessionContextConstructor::BUILDERS` after `Resources`, before `OutputRules`
- Uses `section()` helper from `Base`
- `applicable?` checks `SessionConfigResolver.new(session).resolve_bmad_enabled`

---

## Story 33.5: SessionConfigResolver — bmad_enabled Resolution

As a **platform developer**,
I want `SessionConfigResolver` to resolve `bmad_enabled` from the appropriate source (session_config for standalone, step for workflow),
So that the BMAD integration logic has a single source of truth for whether BMAD should be active.

**Acceptance Criteria:**

**Given** a standalone session with `session_config["bmad_enabled"] = true`
**When** `SessionConfigResolver.new(session).resolve_bmad_enabled` is called
**Then** it returns `true`

**Given** a standalone session without `bmad_enabled` in session_config
**When** `resolve_bmad_enabled` is called
**Then** it returns `false`

**Given** a workflow step session where `step.bmad_enabled = true`
**When** `resolve_bmad_enabled` is called
**Then** it returns `true`

**Given** a workflow step session where `step.bmad_enabled = false`
**When** `resolve_bmad_enabled` is called
**Then** it returns `false`

**Implementation Notes:**
- Add `resolve_bmad_enabled` method to existing `SessionConfigResolver`
- Standalone: reads from `session.session_config`
- Workflow: reads from `step_run.step.bmad_enabled`
- This story prepares the resolver for both Epic 33 (standalone) and Epic 34 (workflow)

---

## Story 33.6: Integration — BmadMethodInjector in assemble_session_context

As a **developer enabling BMAD**,
I want the BMAD installation to happen automatically during session context assembly,
So that when my session starts, BMAD is already set up and ready to use.

**Acceptance Criteria:**

**Given** a session with `bmad_enabled: true`
**When** `SessionContextService#assemble_session_context` runs
**Then** `BmadMethodInjector#inject!` is called after repositories are cloned (step 7) and before context file generation
**And** the step is measured via `measure_step("bmad_method")`

**Given** a session with `bmad_enabled: false`
**When** `SessionContextService#assemble_session_context` runs
**Then** `BmadMethodInjector` is NOT called

**Given** BMAD installation completes successfully
**When** the session context file is generated
**Then** the ContextBuilders::BmadMethod builder finds BMAD files present and generates the context section

**Given** BMAD outputs are produced during the session
**When** the session ends and outputs are collected
**Then** existing `collect_outputs` mechanism picks up files from `/workspace/outputs/` including BMAD artifacts

**Implementation Notes:**
- Add step 7.5 in `SessionContextService#assemble_session_context`
- Guard with `SessionConfigResolver.new(session).resolve_bmad_enabled`
- BmadMethodInjector receives `container_id`, `session`, and `runtime:`

---

## Story 33.7: Frontend — BMAD Toggle in SessionLaunchWidget

As a **developer launching a standalone session**,
I want a "Use BMAD Method" toggle in the session launch configuration,
So that I can enable BMAD with a single click before starting my session.

**Acceptance Criteria:**

**Given** the user opens the session launch widget
**When** the configuration options are displayed
**Then** a "Use BMAD Method" toggle (MUI Switch) is visible in the configuration section

**Given** the user enables the "Use BMAD Method" toggle
**When** the session is started
**Then** the API request includes `session_config: { bmad_enabled: true }` in the payload

**Given** the user does not interact with the BMAD toggle
**When** the session is started
**Then** `bmad_enabled` is not included (or is `false`) in the session_config

**Given** the toggle is displayed
**When** the user views it on screen
**Then** it follows MUI 6 dark theme styling (background.surface, accent.blue for active state)
**And** it has a proper label "Use BMAD Method"
**And** it is keyboard-accessible with appropriate ARIA attributes

**Implementation Notes:**
- Add to existing `SessionLaunchWidget` component
- MUI `Switch` component with `FormControlLabel`
- State managed in the session launch form state
- Passed as part of `session_config` in the create session API call
