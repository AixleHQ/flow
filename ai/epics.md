---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
  - step-05-reorganize-by-phases
inputDocuments:
  - ai/prd.md
  - ai/architecture.md
  - ai/workflow-architecture.md
  - ai/ux-design-specification.md
lastUpdated: 2026-02-02
---

# Palad - Epic Breakdown

## Overview

Epic breakdown organized by **Implementation Phases** from workflow-architecture.md dependency graph.

## Dependency Graph

```
WORKFLOWS (Phase 5-6)
    ↓ depends on
SESSION CONTEXT (Phase 4)
    ↓ depends on
MCP SERVERS (Phase 3)
    ↓ depends on
TOOLS (Phase 2)
    ↓ depends on
AGENTS (Phase 1)
    ↓ depends on
SECRETS MANAGEMENT (Phase 0)
```

## Epic Summary

| Epic | Name | Phase | FRs | Status |
|------|------|-------|-----|--------|
| 1 | Auth & User Management | - | FR62-65 | ✅ done |
| 2 | Agent Onboarding | - | UX | ✅ done |
| 3 | Projects & Collaboration | - | FR26-31 | ✅ done |
| 4 | Secrets & Variables | 0 | FR32-36 | backlog |
| 5 | Agent Management | 1 | FR37-42 | backlog |
| 6 | Tools Framework | 2 | FR43-48 | backlog |
| 7 | MCP Servers | 3 | FR49-52 | backlog |
| 8 | Session Context | 4 | FR53-56 | backlog |
| 9 | Agent Sessions Core | 4+ | FR1-9 | in-progress |
| 10 | Artifacts | 6 | FR19-25 | backlog |
| 11 | Workflows | 5-6 | FR10-18 | backlog |
| 12 | Billing & Analytics | 7 | FR57-61 | backlog |
| 13 | External Integrations | 7 | FR66-68 | backlog |

---

## Epic 1: Authentication & User Management ✅

Users can sign in to the platform and manage user access to the company.

**FRs covered:** FR62, FR63, FR64, FR65

**Status:** DONE

### Stories (all done)
- 1.0: Initial Super Admin Setup ✅
- 1.1: Platform Admin Company Management ✅
- 1.2: Google OAuth Sign In with Domain-Based Company Assignment ✅
- 1.3: User Profile & Company Assignment ✅
- 1.4: Invite Users to Company ✅
- 1.5: Assign User Roles ✅
- 1.6: Remove Users from Company ✅

---

## Epic 2: Agent Onboarding & Configuration ✅

New users can configure their AI agents and save personal settings.

**FRs covered:** UX Design requirements (prepares infrastructure for Sessions)

**Status:** DONE

### Stories (all done)
- 2.1: Onboarding Flow Entry ✅
- 2.2: Select Agents for Configuration ✅
- 2.3: Configure Claude Code Agent ✅
- 2.4: Configure Codex Agent ✅
- 2.5: Configure Gemini CLI Agent ✅
- 2.6: Configure Cursor CLI Agent ✅
- 2.7: Save Agent Settings & Complete Onboarding ✅

---

## Epic 3: Project & Collaboration Foundation ✅

Users can create projects and manage team access.

**FRs covered:** FR26, FR27, FR28, FR29, FR30, FR31

**Status:** DONE (3.3 refused as unnecessary)

### Stories
- 3.1: Create New Project ✅
- 3.2: View Projects List ✅
- 3.3: Switch Between Projects (refused - unnecessary)
- 3.4: Add Collaborators to Project ✅
- 3.5: Remove Collaborators from Project ✅
- 3.6: Collaborator Access to Project Resources ✅

---

## Epic 4: Config Items (Secrets & Variables) (Phase 0)

Admins can manage configuration items (secrets and variables) through a unified interface.

**FRs covered:** FR32, FR33, FR34, FR35, FR36

**Phase:** 0 (Foundation - required by all subsequent phases)

**User Outcome:** Single interface to manage both secrets and variables with scoping and container injection.

### Key Concepts

**Config Item** — unified entity with type toggle:

| Type | Visibility | Use Case |
|------|------------|----------|
| **Secret** | Write-only (masked after creation) | API keys, tokens, passwords |
| **Variable** | Readable (can view/edit value) | URLs, feature flags, config values |

**Scoping Rules:**
- Config items can exist at **company** or **project** level
- Company-level: available in all projects
- Project-level: available only in that project
- **Override rule:** If same name exists at both levels, project value overrides company value

### Story 4.1: Config Items CRUD with Type Toggle

As a company/project admin,
I want to create and manage config items with a type selector (Secret/Variable),
So that I can configure both sensitive and non-sensitive values in one place.

**Acceptance Criteria:**
- Unified "Config Items" page (not separate pages for secrets/variables)
- Create form with fields:
  - Name (required, unique within scope)
  - Value (required)
  - Description (optional)
  - Type toggle: Secret | Variable (default: Variable)
  - Scope selector: Company | Project (if in project context)
- When type = Secret:
  - Value encrypted before save
  - Value field cleared after save (cannot be viewed again)
- When type = Variable:
  - Value stored in plain text
  - Value visible and editable
- Can edit name, description for both types
- Can edit value only for Variables
- Can delete config items
- Confirmation dialog for delete

### Story 4.2: Config Item Scoping (Company/Project Override)

As a system,
I want to support company and project level config items with override logic,
So that projects can customize company-wide defaults.

**Acceptance Criteria:**
- Config items have `scope_type` (company/project) and `scope_id`
- Company-level items: `scope_type: company, scope_id: company.id`
- Project-level items: `scope_type: project, scope_id: project.id`
- Name uniqueness enforced within same scope
- Same name can exist at company AND project level
- Resolution order: project → company (project wins)
- UI shows merged list with indicators:
  - "(company)" for company-level items
  - "(project)" for project-level items
  - "(overrides company)" when project item shadows company item

### Story 4.3: Encrypt Secrets at Rest

As a system,
I want to encrypt secret values at rest,
So that credentials are protected if database is compromised.

**Acceptance Criteria:**
- Uses Rails `encrypts` (ActiveSupport::MessageEncryptor)
- Only secrets encrypted (type = secret)
- Variables stored in plain text (type = variable)
- Encryption key in Rails credentials
- Decrypted only when needed for injection
- Never logged or exposed in API responses

### Story 4.4: Inject Config Items into Containers

As a system,
I want to inject config items into agent/tool containers as environment variables,
So that they can access required configuration.

**Acceptance Criteria:**
- Both secrets and variables injected as env vars
- Env var name = config item name (uppercased, sanitized)
- Secrets decrypted at injection time
- Project-level values override company-level (same name)
- Injection happens at container start
- Secrets masked in container logs
- If required config item missing, session fails with clear error

### Story 4.5: Config Items UI

As a user,
I want a unified UI to view and manage all config items,
So that I can easily understand my environment configuration.

**Acceptance Criteria:**
- Single table showing all config items (merged company + project)
- Columns: Name, Type (Secret/Variable), Value, Scope, Description, Actions
- Value column:
  - Variables: shows actual value
  - Secrets: shows ••••••••
- Type column: badge/chip (Secret = red, Variable = blue)
- Scope column: shows "(company)" or "(project)" or "(overrides company)"
- Filter by: Type (Secret/Variable/All), Scope (Company/Project/All)
- Search by name
- Inline edit for variable values
- Delete with confirmation
- Create button opens modal with type toggle

---

## Epic 5: Agent Management (Phase 1)

Admins can create and manage agent configurations with personas.
**Agents are independent of workflows** — they can be used in standalone sessions or workflow steps.

**FRs covered:** FR37, FR38, FR39, FR40, FR41, FR42

**Phase:** 1 (Depends on: Epic 4 Secrets)

**User Outcome:** Reusable agent configurations with personas for standalone sessions and workflows.

### Story 5.1: Agent CRUD with Scoping

As a company admin,
I want to create and manage agent configurations with persona details,
So that agents can be reused across standalone sessions and workflows.

**Acceptance Criteria:**
- Can create agent with: name, title, icon (emoji), persona, communication_style, principles
- Agent scoped to company or project level (polymorphic scope)
- Can edit and delete agents
- Project agents override company agents with same name (merged list)
- Source tracking: `custom` or `bmad_import`
- UI for managing agents (company-level and project-level)

### Story 5.2: Import Agents from BMAD Files

As a company admin,
I want to import agent configurations from BMAD files,
So that I can reuse existing agent definitions.

**Acceptance Criteria:**
- Can upload BMAD agent files (.md)
- Parser extracts persona, communication_style, principles
- Creates Agent record with imported data (source: bmad_import)
- Shows preview before import

### Story 5.3: Select Agent for Session

As a user,
I want to select an agent when starting a standalone session,
So that the agent's persona is applied to my interaction.

**Acceptance Criteria:**
- Session start shows available agents (merged company + project)
- Can select agent for the session
- Selected agent's persona injected as system prompt
- Agent selection saved with session record

---

## Epic 6: Tools Framework (Phase 2)

Admins can create custom tools to extend agent capabilities.

**FRs covered:** FR43, FR44, FR45, FR46, FR47, FR48

**Phase:** 2 (Depends on: Epic 5 Agents)

**User Outcome:** Extensible tools system executed via Docker.

### Story 6.1: Create Tool with Types (Internal/Custom)

As a company admin,
I want to create and manage tools with type distinction,
So that agents can use both platform-provided capabilities and custom extensions.

**Tool Types:**
| Type | Description | Scope |
|------|-------------|-------|
| `internal` | System-provided by Palad (create_workflow, manage_artifacts) | Global (no scope) |
| `custom` | User-created with Docker execution | Company or Project |

**Acceptance Criteria:**
- Tool model with `tool_type`: internal | custom
- Can create custom tool with: name, display_name, description, docker_image, docker_command
- Can define input_schema (JSON Schema)
- Custom tools scoped to company or project (polymorphic)
- Internal tools are global and read-only
- Can edit and delete custom tools only
- UI shows merged list with type indicators

### Story 6.2: Specify Required Secrets for Tool

As a company admin,
I want to specify which secrets a tool requires,
So that secrets are injected when tool runs.

**Acceptance Criteria:**
- Can select required secrets from company secrets
- Can mark secrets as required vs optional
- If required secret missing, tool execution fails

### Story 6.3: Execute Tool as Temporal Activity

As a system,
I want to execute tools as Temporal Activities,
So that execution is reliable and trackable.

**Acceptance Criteria:**
- Temporal Activity pulls Docker image
- Creates container with injected secrets
- Executes tool with parameters
- Captures exit code, stdout, stderr
- Cleans up container after execution

### Story 6.4: Tool Scoping (Company/Project)

As a system,
I want tools scoped to company or project level,
So that project tools override company defaults.

**Acceptance Criteria:**
- Tools have optional project_id
- Session merges project + company tools
- Project tools override company tools with same name

---

## Epic 7: MCP Tools Integration (Phase 3)

Agents can discover and execute custom tools via MCP protocol.

**FRs covered:** FR49, FR50, FR51, FR52

**Phase:** 3 (Depends on: Epic 6 Tools)

**User Outcome:** CLI agents can use custom tools through MCP protocol.

### Architecture Decision

**Approach:** Single MCP server embedded in Rails app using ActionMCP gem with dynamic tool resolution via monkey-patch.

**Why not separate MCP containers?**
- Simpler deployment (no sidecar management)
- Proven pattern (used in other projects)
- Session-based tool filtering built into Rails

```
Agent ──MCP(SSE)──→ Rails/ActionMCP ──Temporal──→ ToolExecutionWorkflow
         ↑                 ↑
    X-Session-Key    Gateway auth +
                     dynamic tools/list
```

### Story 7.1: Dynamic MCP Tools Integration

As a system,
I want to expose custom tools to agents via MCP protocol using ActionMCP,
So that agents can discover and execute tools based on their session context.

**Acceptance Criteria:**
- ActionMCP gem installed and configured
- Gateway authenticates by `mcp_key` header
- `tools/list` returns only tools available for current session
- `tools/call` executes tool via `ToolExecutionWorkflow` (Temporal)
- Session has `mcp_key` for MCP authentication
- Session has `available_tools` association (many-to-many)
- Agent container receives MCP config with session key at startup

### Story 7.2: Select Tools for Session (UI)

As a user,
I want to select which custom tools are available when starting a standalone session,
So that I control what capabilities the agent has.

**Acceptance Criteria:**
- Session start form shows available custom tools (company + project merged)
- Can select 0..N tools for the session
- Selected tools saved to `session_tools` join table
- Default: no tools selected (explicit opt-in)

### Story 7.3: Tool Selection for Workflow Steps (deferred)

As a workflow designer,
I want to specify which tools are available for each workflow step,
So that agents have appropriate capabilities per step.

**Status:** Deferred to Epic 11 (Workflows)

**Note:** Will reuse `session_tools` pattern but configured per workflow step.

### Story 7.4: MCP Server Management

As a company/project admin,
I want to configure MCP servers (internal and custom),
So that agents can access additional tools from external providers like Context7, Tavily, etc.

**MCP Server Types:**
| Type | Description | Scope |
|------|-------------|-------|
| `internal` | System-provided (Palad tools MCP) | Global (automatic) |
| `custom` | User-configured external servers | Company or Project |

**Acceptance Criteria:**
- MCP Server model with `kind`: internal | custom
- Can create custom MCP server with: name, url, transport (sse/stdio), headers (JSON), description
- Custom servers scoped to company or project (polymorphic)
- Internal server is auto-configured per session (from 7.1)
- Can enable/disable MCP servers
- Can edit and delete custom servers only
- UI for managing MCP servers (company-level and project-level)
- Session can have multiple MCP servers (internal + selected custom)

### Story 7.5: Select MCP Servers for Session

As a user,
I want to select which MCP servers are available when starting a session,
So that I control what external tools the agent can access.

**Acceptance Criteria:**
- Session start form shows available MCP servers (company + project merged)
- Internal "Palad Tools" always included if custom tools selected
- Can select 0..N custom MCP servers
- Selected servers saved to `session_mcp_servers` join table
- MCP config injected into agent container with all selected servers

---

## Epic 8: Session Context (Phase 4)

Admins can configure per-CLI session context with credentials and MCP.

**FRs covered:** FR53, FR54, FR55, FR56

**Phase:** 4 (Depends on: Epic 7 MCP Servers)

**User Outcome:** Sessions start with correct configuration for each CLI type.

### Story 8.1: Configure Session Context per CLI Type

As a company admin,
I want to configure session context per CLI type,
So that each agent type has correct configuration.

**Acceptance Criteria:**
- Can configure context for: Claude Code, Cursor CLI, Codex, Gemini CLI
- Context includes: config_files, env_vars, mcp_servers
- Context scoped to company

### Story 8.2: Inject Config Files into Container

As a system,
I want to inject config files into container based on CLI type,
So that agent CLI is properly configured.

**Acceptance Criteria:**
- Config files written to correct paths (e.g., ~/.claude/settings.json)
- Content from SessionContextConfig.config_files
- Files created before session starts

### Story 8.3: Inject Environment Variables with Secrets

As a system,
I want to inject environment variables with resolved secrets,
So that agent has required credentials.

**Acceptance Criteria:**
- Env vars from SessionContextConfig.env_vars
- Secret references resolved (e.g., "secret:api_key" → actual value)
- Vars set in container environment

### Story 8.4: Connect MCP Servers to Session

As a system,
I want to connect configured MCP servers to session,
So that agent can access tools via MCP.

**Acceptance Criteria:**
- MCP servers from SessionContextConfig.mcp_servers started
- Connection established before agent starts
- MCP server URL/config provided to agent

---

## Epic 9: Agent Sessions Core (Phase 4+)

Users can start sessions with AI agents and interact with them.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9

**Phase:** 4+ (Depends on: Epic 8 Session Context)

**Status:** IN PROGRESS (Stories 9.1, 9.2 ready-for-dev)

**User Outcome:** Complete agent session workflow with cost tracking.

### Story 9.1: Start Agent Session

As a user,
I want to start a new agent session with selected agent type,
So that I can work with an AI agent on my project.

**Status:** ready-for-dev

**Acceptance Criteria:**
- Can select agent type (Claude Code, Codex, Gemini CLI, Cursor CLI)
- Can select mode (Interactive / Non-interactive)
- Docker container created with session context
- Session status tracks lifecycle

### Story 9.2: Web Terminal Interface

As a user,
I want to interact with agent through web terminal in Interactive mode,
So that I can communicate in real-time.

**Status:** ready-for-dev

**Acceptance Criteria:**
- Web terminal via xterm.js + WebSocket
- Real-time input/output
- Standard terminal features (cursor, scrolling, copy/paste)
- State preserved on navigation

### Story 9.3: Real-time File Tree

As a user,
I want to view file tree of session workspace in real-time,
So that I can see what agent is working on.

**Acceptance Criteria:**
- File tree panel shows workspace structure
- Updates in real-time via WebSocket
- Can expand/collapse directories
- Click file to view in viewer

### Story 9.4: File Viewer & Browser

As a user,
I want to view and browse files in session workspace,
So that I can see agent's work.

**Acceptance Criteria:**
- Syntax highlighting for code
- View images, PDFs, text files
- Read-only viewing
- Navigate via file tree

### Story 9.5: Stop Active Session

As a user,
I want to stop an active session,
So that I can terminate agent's work.

**Acceptance Criteria:**
- Stop button with confirmation
- Container terminated
- Session status → stopped
- Files preserved in workspace

### Story 9.6: MITM Proxy Token Tracking

As a system,
I want to track token usage via MITM proxy,
So that billing is accurate.

**Acceptance Criteria:**
- All LLM API calls intercepted
- Input/output tokens tracked
- Works for all 4 agents
- Accuracy ≥ 95%

### Story 9.7: Session Cost Display

As a user,
I want to see session cost after completion,
So that I understand the expense.

**Acceptance Criteria:**
- Shows total tokens (input/output)
- Shows cost in USD
- Optional cost breakdown by API call

### Story 9.8: Session History View

As a user,
I want to view session history with status and outcomes,
So that I can review past work.

**Acceptance Criteria:**
- List of all project sessions
- Shows agent type, mode, status, duration, cost
- Can filter by type, status, date
- Click to view details

---

## Epic 10: Artifacts (Phase 6)

Users can upload, view, and manage artifacts.

**FRs covered:** FR19, FR20, FR21, FR22, FR23, FR24, FR25

**Phase:** 6 (Depends on: Epic 9 Sessions)

**User Outcome:** Complete artifact management with versioning and provenance.

### Story 10.1: Upload Assets to Project

**Acceptance Criteria:**
- Upload files to S3
- Metadata saved to database
- Progress indicator
- Supports documents, images, archives, code

### Story 10.2: View Artifacts List

**Acceptance Criteria:**
- List all project artifacts
- Shows name, size, date, uploader, provenance
- Search and filter
- Grid/list view toggle

### Story 10.3: Download Artifacts

**Acceptance Criteria:**
- Download from S3
- Preserves original filename
- Bulk download support

### Story 10.4: Delete Artifacts

**Acceptance Criteria:**
- Soft delete with confirmation
- Can restore within retention period
- Warning if referenced by workflow

### Story 10.5: S3 Storage Integration

**Acceptance Criteria:**
- Files stored in S3 bucket
- Path: projects/{id}/artifacts/{id}/{filename}
- Encrypted at rest
- Access restricted to authenticated requests

### Story 10.6: Artifact History & Versioning

**Acceptance Criteria:**
- New version on same filename upload
- Version numbers (v1, v2, v3)
- Can view/download any version
- Version history shows metadata

### Story 10.7: Artifact Provenance Tracking

**Acceptance Criteria:**
- Manual upload: "Upload by {user} on {date}"
- Workflow: "Workflow '{name}' → Step '{step}' by {user}"
- Provenance displayed everywhere
- Can navigate to workflow run

---

## Epic 11: Workflows (Phase 5-6)

Users can create and execute workflows with step-by-step execution.

**FRs covered:** FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17, FR18

**Phase:** 5-6 (Depends on: Epic 10 Artifacts)

**User Outcome:** Complete workflow system with both execution modes.

### Story 11.1: Create New Workflow

**Acceptance Criteria:**
- Create workflow with name, description
- Associate with project
- Redirect to edit page

### Story 11.2: Define Workflow Steps

**Acceptance Criteria:**
- Add steps with: name, instructions, input_requirements, expected_outputs
- allow_non_interactive flag per step
- Reorder steps (drag & drop)
- Variables in instructions: {{artifact_name}}

### Story 11.3: Edit Existing Workflow

**Acceptance Criteria:**
- Modify all workflow properties
- Existing runs not affected
- Warning if currently running

### Story 11.4: Delete Workflow

**Acceptance Criteria:**
- Delete with confirmation
- Historical runs preserved
- Warning if active runs

### Story 11.5: View Workflows List

**Acceptance Criteria:**
- List all project workflows
- Shows name, steps count, last run
- Search and filter

### Story 11.6: Start Workflow Execution

**Acceptance Criteria:**
- Select input artifacts (auto + manual)
- Select mode (Interactive / Non-interactive)
- Creates WorkflowRun + first StepRun
- Temporal workflow started

### Story 11.7: Interactive Mode Execution

**Acceptance Criteria:**
- WorkflowStepper shows progress
- Each step opens session
- Approve/Reject after step
- Artifacts passed to next step

### Story 11.8: Non-Interactive Mode Execution

**Acceptance Criteria:**
- Steps with allow_non_interactive run automatically
- Steps without wait for approval
- Notifications on completion
- Total cost displayed

### Story 11.9: Artifact Passing Between Steps

**Acceptance Criteria:**
- Step outputs → next step inputs
- input_requirements resolved automatically
- Provenance tracks workflow origin
- Variables replaced in instructions

---

## Epic 12: Billing & Analytics (Phase 7)

Users and admins can track costs and usage analytics.

**FRs covered:** FR57, FR58, FR59, FR60, FR61

**Phase:** 7 (Depends on: Epic 9 Sessions)

**User Outcome:** Complete cost transparency at all levels.

### Story 12.1: View Total Cost for Project

**Acceptance Criteria:**
- Total USD and tokens
- Trend chart over time
- Filter by date range

### Story 12.2: Cost Breakdown by Workflow

**Acceptance Criteria:**
- Cost per workflow
- Bar/pie charts
- Click for details

### Story 12.3: Cost Breakdown by User

**Acceptance Criteria:**
- Cost per user
- Charts
- Click for details

### Story 12.4: Session History with Costs

**Acceptance Criteria:**
- Sessions list with costs
- Filter and search
- Export to CSV

### Story 12.5: Company-Wide Statistics

**Acceptance Criteria:**
- Admin-only view
- Total across all projects
- Breakdowns by project/user
- Export report

---

## Epic 13: External Integrations (Phase 7)

System integrates with external services.

**FRs covered:** FR66, FR67, FR68

**Phase:** 7 (Depends on: Epic 11 Workflows)

**User Outcome:** Seamless integration with development tools.

### Story 13.1: Configure GitHub Repositories

**Acceptance Criteria:**
- Add repos with URL, branch, authentication
- Test connection
- Available for code context and PRs

### Story 13.2: Load Code Context from GitHub

**Acceptance Criteria:**
- Load files into session workspace
- Supports private repos
- Cached for performance

### Story 13.3: Create PR in GitHub

**Acceptance Criteria:**
- Create PR from session changes
- Title, description, target branch
- PR link saved to session

### Story 13.4: Export Tasks to Linear

**Acceptance Criteria:**
- Export workflow output tasks
- Maps to Linear fields
- Link stored in artifacts

---

## FR Coverage Map (Updated)

| FR | Epic | Story |
|----|------|-------|
| FR1-9 | Epic 9 | Agent Sessions |
| FR10-18 | Epic 11 | Workflows |
| FR19-25 | Epic 10 | Artifacts |
| FR26-31 | Epic 3 | Projects ✅ |
| FR32-36 | Epic 4 | Secrets |
| FR37-42 | Epic 5 | Agent Management |
| FR43-48 | Epic 6 | Tools |
| FR49-52 | Epic 7 | MCP Servers |
| FR53-56 | Epic 8 | Session Context |
| FR57-61 | Epic 12 | Billing |
| FR62-65 | Epic 1 | Auth ✅ |
| FR66-68 | Epic 13 | Integrations |

---

_Last updated: 2026-02-02_
_Reorganized by Implementation Phases from workflow-architecture.md_
