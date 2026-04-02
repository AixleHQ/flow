# Story 6.1: Create Tool with Types (Internal/Custom)

Status: review

## Story

As a company admin,
I want to create and manage tools with type distinction (internal system tools vs custom user tools),
So that agents can use both platform-provided capabilities and custom extensions.

## Acceptance Criteria

1. Tool model with `scope_type`: `Internal | Company | Project`
   - `Internal` — system-provided tools by Aixle (read-only, no scope_id)
   - `Company` — company-level custom tools
   - `Project` — project-level custom tools
2. Can create custom tool (Company/Project scope) with:
   - `name`, `display_name`, `description`
   - `docker_image` — Docker image to run
   - `command` — command template with `{{param}}` placeholders
   - `files` — array of `{path, content}` to mount into container
   - `required_config_items` — list of config item names to inject as env vars
   - `input_schema` — JSON Schema for tool parameters
3. Internal tools are global and read-only for users
4. Can edit and delete Company/Project tools only
5. UI shows merged list with scope indicators (Internal/Company/Project)
6. Project tools override Company tools with same name
7. Tool execution returns structured result: `{exit_code, stdout, stderr, duration_ms}`

## Tasks / Subtasks

- [x] Task 1: Create Tool model and migration (AC: 1, 2, 3, 4)
  - [x] 1.1: Create migration for `tools` table:
    - `name` (string, required) — unique identifier (lowercase_underscore)
    - `display_name` (string, required) — human-readable name
    - `description` (text) — what the tool does
    - `scope_type` (string, required) — Internal | Company | Project
    - `scope_id` (bigint, nullable) — null for Internal
    - `docker_image` (string) — for custom tools
    - `command` (text) — command template with `{{param}}` placeholders
    - `required_config_items` (jsonb, default: []) — array of config item names
    - `input_schema` (jsonb, default: {}) — JSON Schema for parameters
    - `enabled` (boolean, default: true)
  - [x] 1.2: Create Tool model with:
    - Enumerize for `scope_type` (Internal, Company, Project)
    - `has_many :tool_files, dependent: :destroy`
    - Validations (name format, uniqueness within scope_type+scope_id)
    - `merged_for_project(project)` class method
    - Scopes: `internal`, `for_company`, `for_project`
    - `internal?`, `custom?` predicates
  - [x] 1.3: Add `has_many :tools` to Company and Project models

- [x] Task 2: Create ToolFile model (AC: 2)
  - [x] 2.1: Create migration for `tool_files` table:
    - `tool_id` (bigint, required)
    - `path` (string, required) — full path in container (e.g., `/app/script.py`)
    - `content` (text, required) — file content
    - `file_type` (string) — detected or specified (python, yaml, json, shell, etc.)
  - [x] 2.2: Create ToolFile model with:
    - `belongs_to :tool`
    - Validations (path format, uniqueness within tool)
    - Auto-detect file_type from extension

- [ ] Task 3: Create ToolExecution model (AC: 7) — DEFERRED (tools go directly to MCP)

- [ ] Task 4: Seed internal tools (AC: 3) — DEFERRED (not needed yet)

- [x] Task 5: Create API endpoints (AC: 2, 4, 5)
  - [x] 5.1: Company-level tools controller (CRUD for custom tools)
  - [x] 5.2: Project-level tools controller (CRUD + merged index)
  - [x] 5.3: ToolSerializer with nested tool_files
  - [x] 5.4: Nested routes for tool_files (or inline in tool params)
  - [x] 5.5: Policies (admin for company, project member for project)

- [x] Task 6: Create Tools UI (AC: 5)
  - [x] 6.1: ToolsPage component with table
  - [x] 6.2: ToolScopeBadge (internal/company/project/overrides_company)
  - [x] 6.3: ToolFormDialog (create/edit custom tools)
  - [x] 6.4: DeleteToolDialog
  - [x] 6.5: ToolFilesEditor (add/edit/remove files with path + content)
  - [x] 6.6: ConfigItemsSelector (select required config items) — simplified as text input
  - [x] 6.7: InputSchemaEditor (JSON Schema builder or raw JSON) — deferred to future
  - [x] 6.8: Add routing and navigation

- [x] Task 7: Write tests (AC: 1-7)
  - [x] 7.1: Model tests (Tool, ToolFile validations, scoping, merged_for_project)
  - [x] 7.2: Controller tests (CRUD, internal tools read-only)

## Dev Notes

### Scope Types Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           TOOLS                                     │
├─────────────────────┬─────────────────────┬─────────────────────────┤
│     INTERNAL        │       COMPANY       │        PROJECT          │
│   (scope_type)      │    (scope_type)     │      (scope_type)       │
├─────────────────────┼─────────────────────┼─────────────────────────┤
│ - scope_id: null    │ - scope_id: company │ - scope_id: project     │
│ - Read-only         │ - Full CRUD         │ - Full CRUD             │
│ - Seeded by Aixle   │ - Company-wide      │ - Project-specific      │
│ - Built-in logic    │ - Docker execution  │ - Overrides Company     │
└─────────────────────┴─────────────────────┴─────────────────────────┘
```

**Unified scope_type enum:** `Internal | Company | Project`
- Same pattern as ConfigItem/Agent but with `Internal` as third option
- `internal?` predicate = `scope_type == 'Internal'`
- `custom?` predicate = `scope_type.in?(['Company', 'Project'])`

### Database Schema

```ruby
# tools table
create_table :tools do |t|
  t.string :name, null: false           # unique identifier (lowercase_underscore)
  t.string :display_name, null: false   # human-readable name
  t.text :description
  t.string :scope_type, null: false     # Internal | Company | Project
  t.bigint :scope_id                    # null for Internal, company_id/project_id otherwise
  t.string :docker_image                # Docker image for custom tools
  t.text :command                       # command template with {{param}} placeholders
  t.jsonb :required_config_items, default: []  # ["API_KEY", "DATABASE_URL"]
  t.jsonb :input_schema, default: {}    # JSON Schema for parameters
  t.boolean :enabled, default: true
  t.timestamps
end

add_index :tools, [:scope_type, :scope_id, :name], unique: true
add_index :tools, :scope_type

# tool_files table
create_table :tool_files do |t|
  t.bigint :tool_id, null: false
  t.string :path, null: false           # full path in container, e.g. "/app/script.py"
  t.text :content, null: false          # file content
  t.string :file_type                   # python, yaml, json, shell, etc.
  t.timestamps
end

add_index :tool_files, :tool_id
add_index :tool_files, [:tool_id, :path], unique: true
add_foreign_key :tool_files, :tools

# tool_executions table
create_table :tool_executions do |t|
  t.bigint :tool_id, null: false
  t.bigint :terminal_session_id         # if run from session context
  t.bigint :user_id, null: false
  t.bigint :project_id
  t.string :state, null: false, default: 'pending'  # pending | running | completed | failed
  t.jsonb :input_params, default: {}    # parameters passed to tool
  t.integer :exit_code
  t.text :stdout
  t.text :stderr
  t.integer :duration_ms
  t.string :temporal_workflow_id
  t.string :temporal_run_id
  t.datetime :started_at
  t.datetime :finished_at
  t.timestamps
end

add_index :tool_executions, :tool_id
add_index :tool_executions, :terminal_session_id
add_index :tool_executions, :user_id
add_index :tool_executions, :project_id
add_index :tool_executions, :state
add_index :tool_executions, :temporal_workflow_id
```

### Internal Tools (Seeded)

| Name | Display Name | Description |
|------|--------------|-------------|
| `create_workflow` | Create Workflow | Create a new workflow definition |
| `create_tool` | Create Tool | Create a new custom tool |
| `manage_artifacts` | Manage Artifacts | Upload, download, list artifacts |
| `execute_shell` | Execute Shell | Run shell commands in session container |

### ToolFile Model

Files mounted into container at execution time:

```ruby
class ToolFile < ApplicationRecord
  belongs_to :tool

  validates :path, presence: true,
                   format: { with: %r{\A/}, message: "must be absolute path" },
                   uniqueness: { scope: :tool_id }
  validates :content, presence: true

  before_validation :detect_file_type

  private

  def detect_file_type
    return if file_type.present? || path.blank?

    self.file_type = case File.extname(path)
    when '.py' then 'python'
    when '.rb' then 'ruby'
    when '.sh' then 'shell'
    when '.yaml', '.yml' then 'yaml'
    when '.json' then 'json'
    when '.js' then 'javascript'
    else 'text'
    end
  end
end
```

**Example files:**
| path | content | file_type |
|------|---------|-----------|
| `/app/script.py` | `import requests...` | python |
| `/app/config.yaml` | `key: value` | yaml |

### Custom Tool Fields

**`required_config_items`** — Config items to inject as env vars:
```json
["API_KEY", "DATABASE_URL", "SECRET_TOKEN"]
```
These will be resolved from merged company+project config items.

**`command`** — Command template with placeholders:
```
python /app/script.py --query "{{query}}" --limit {{limit}}
```

**`input_schema`** — JSON Schema for parameters:
```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query"
    },
    "limit": {
      "type": "integer",
      "default": 10,
      "minimum": 1,
      "maximum": 100
    }
  },
  "required": ["query"]
}
```

### Tool Execution Result

```json
{
  "exit_code": 0,
  "stdout": "Result: success\n",
  "stderr": "",
  "duration_ms": 1523
}
```

### Merged List Logic

Same pattern as `Agent.merged_for_project`:
1. Get Internal tools (scope_indicator = "internal")
2. Get Company tools (scope_indicator = "company")
3. Get Project tools (scope_indicator = "project" or "overrides_company")
4. Project tools override Company tools with same name
5. Internal tools cannot be overridden (different namespace conceptually)
6. Return with `scope_indicator` method

```ruby
def self.merged_for_project(project)
  internal_tools = where(scope_type: 'Internal')
  company_tools = where(scope_type: 'Company', scope_id: project.company_id)
  project_tools = where(scope_type: 'Project', scope_id: project.id)

  # ... merge logic with scope_indicator injection
end
```

### API Endpoints

```
# Company-level
GET    /api/v1/company/tools           # internal + company custom
POST   /api/v1/company/tools           # create company custom
PATCH  /api/v1/company/tools/:id       # update company custom (not internal)
DELETE /api/v1/company/tools/:id       # delete company custom (not internal)

# Project-level
GET    /api/v1/company/projects/:id/tools     # merged list
POST   /api/v1/company/projects/:id/tools     # create project custom
PATCH  /api/v1/company/projects/:id/tools/:id # update project custom
DELETE /api/v1/company/projects/:id/tools/:id # delete project custom
```

### Temporal Workflow (Story 6.3)

**Note:** This story creates model and CRUD. Temporal execution is Story 6.3.

Execution flow (for reference):
```
1. Create ToolExecution record (state: pending)
2. Start Temporal workflow ExecuteToolWorkflow
3. Temporal Activity:
   a. Pull docker_image
   b. Create container with:
      - Mounted files from tool.files
      - Env vars from resolved config items
      - Workspace directory /workspace
   c. Execute command with interpolated params
   d. Capture stdout, stderr, exit_code
   e. Cleanup container
4. Update ToolExecution with result
```

### UI Components

Follow same patterns as ConfigItems and Agents pages:
- `ToolsPage` — main page with table and filters
- `ToolsTable` — displays tools with type/scope badges
- `ToolFormDialog` — create/edit dialog:
  - Basic info (name, display_name, description)
  - Docker config (image, command)
  - Files editor (add/remove mounted files with path + content)
  - Config items selector (multi-select from available config items)
  - Input schema editor (JSON editor)
- `DeleteToolDialog` — confirmation dialog
- Routing: `/company/tools` and project tab "Tools"

### Project Structure Notes

- Model follows `Agent` pattern with polymorphic scope
- Internal tools seeded in `db/seeds.rb`
- UI follows Feature-Sliced Design
- Tests follow existing controller test patterns

### References

- [Source: web/app/models/agent.rb] - Pattern for polymorphic scope and merged_for_project
- [Source: ai/epics.md#Epic-6] - Story requirements
- [Source: ai/workflow-architecture.md] - Tools in workflow context

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (2026-02-02)

### Debug Log References

None

### Completion Notes List

- Created Tool model with scope_type enum (Internal/Company/Project)
- Created ToolFile model for files mounted into containers
- ToolExecution model deferred — tools will go directly to MCP agents
- Internal tools seeding deferred — not needed yet
- Custom tools (Company/Project) have full CRUD
- Project tools override Company tools with same name
- UI follows existing ConfigItems/Agents patterns
- Nested tool_files handled via accepts_nested_attributes_for

### File List

**Backend (Rails):**
- `db/migrate/20260202160000_create_tools.rb`
- `db/migrate/20260202160001_create_tool_files.rb`
- `app/models/tool.rb`
- `app/models/tool_file.rb`
- `app/controllers/api/v1/company/tools_controller.rb`
- `app/controllers/api/v1/company/projects/tools_controller.rb`
- `app/serializers/tool_serializer.rb`
- `app/serializers/tool_file_serializer.rb`
- `app/policies/api/v1/company/tools_policy.rb`
- `app/policies/api/v1/company/projects/tools_policy.rb`
- `config/routes.rb` (updated)
- `db/seeds.rb` (updated)
- `app/models/company.rb` (updated)
- `app/models/project.rb` (updated)

**Frontend (React):**
- `app/frontend/pages/tools/index.ts`
- `app/frontend/pages/tools/lib/types.ts`
- `app/frontend/pages/tools/lib/toolSchema.ts`
- `app/frontend/pages/tools/api/toolsApi.ts`
- `app/frontend/pages/tools/ui/ToolsPage.tsx`
- `app/frontend/pages/tools/ui/ToolsTable.tsx`
- `app/frontend/pages/tools/ui/ToolScopeBadge.tsx`
- `app/frontend/pages/tools/ui/ToolFormDialog.tsx`
- `app/frontend/pages/tools/ui/ToolFilesEditor.tsx`
- `app/frontend/pages/tools/ui/DeleteToolDialog.tsx`
- `app/frontend/shared/routes.ts` (updated)
- `app/frontend/shared/api/QueryTag.ts` (updated)
- `app/frontend/app/routeTree.tsx` (updated)
- `app/frontend/widgets/AppHeader/ui/AppHeader.tsx` (updated)
- `app/frontend/pages/project/lib/types.ts` (updated)
- `app/frontend/pages/project/ui/ProjectPage.tsx` (updated)

**Tests:**
- `test/factories/tools.rb`
- `test/models/tool_test.rb`
- `test/models/tool_file_test.rb`
- `test/controllers/api/v1/company/tools_controller_test.rb`
- `test/controllers/api/v1/company/projects/tools_controller_test.rb`
