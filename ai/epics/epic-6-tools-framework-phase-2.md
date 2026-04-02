# Epic 6: Tools Framework (Phase 2)

Admins can create custom tools to extend agent capabilities.

**FRs covered:** FR43, FR44, FR45, FR46, FR47, FR48

**Phase:** 2 (Depends on: Epic 5 Agents)

**User Outcome:** Extensible tools system executed via Docker.

## Story 6.1: Create Tool with Types (Internal/Custom)

As a company admin,
I want to create and manage tools with type distinction,
So that agents can use both platform-provided capabilities and custom extensions.

**Tool Types:**
| Type | Description | Scope |
|------|-------------|-------|
| `internal` | System-provided by Aixle (create_workflow, manage_artifacts) | Global (no scope) |
| `custom` | User-created with Docker execution | Company or Project |

**Acceptance Criteria:**
- Tool model with `tool_type`: internal | custom
- Can create custom tool with: name, display_name, description, docker_image, docker_command
- Can define input_schema (JSON Schema)
- Custom tools scoped to company or project (polymorphic)
- Internal tools are global and read-only
- Can edit and delete custom tools only
- UI shows merged list with type indicators

## Story 6.2: Specify Required Secrets for Tool

As a company admin,
I want to specify which secrets a tool requires,
So that secrets are injected when tool runs.

**Acceptance Criteria:**
- Can select required secrets from company secrets
- Can mark secrets as required vs optional
- If required secret missing, tool execution fails

## Story 6.3: Execute Tool as Temporal Activity

As a system,
I want to execute tools as Temporal Activities,
So that execution is reliable and trackable.

**Acceptance Criteria:**
- Temporal Activity pulls Docker image
- Creates container with injected secrets
- Executes tool with parameters
- Captures exit code, stdout, stderr
- Cleans up container after execution

## Story 6.4: Tool Scoping (Company/Project)

As a system,
I want tools scoped to company or project level,
So that project tools override company defaults.

**Acceptance Criteria:**
- Tools have optional project_id
- Session merges project + company tools
- Project tools override company tools with same name

---
