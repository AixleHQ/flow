# Story 9.5: Skills CRUD with Scoping

Status: done

## Story

As a company admin,
I want to create, manage, and scope skills for AI agents,
so that agent sessions can be enhanced with reusable, domain-specific instructions.

## Acceptance Criteria

1. **Skill model** with `kind` (internal/custom), polymorphic `scope` (Company or Project), name normalization, uniqueness within scope
2. **Migration** creates `skills` table with correct columns, indexes, and constraints (scope nullable for internal)
3. **Company-level CRUD** at `POST/GET/PATCH/DELETE /api/v1/company/skills`
4. **Project-level CRUD** at `POST/GET/PATCH/DELETE /api/v1/company/projects/:project_id/skills`
5. **Merged list** at project level: internal + company + project skills; project overrides company with same name; includes `scope_indicator`
6. **Authorization**: company-level = admin only, project-level = project owner/collaborator
7. **Serializer** includes `scope_indicator` and `internal` computed attributes
8. **Validation**: name format (`/\A[a-z][a-z0-9_-]*\z/`), uniqueness within scope, custom kind requires scope, internal kind has no scope
9. **Parent associations**: `Company has_many :skills` and `Project has_many :skills` (polymorphic)

## Tasks / Subtasks

- [x] Task 1: Migration (AC: #2)
  - [x] Create `skills` table: `name`, `title`, `content`, `description`, `kind` (default: "custom"), `scope_type` (nullable), `scope_id` (nullable), timestamps
  - [x] Unique index on `[scope_type, scope_id, name]`
  - [x] Index on `[scope_type, scope_id]`
  - [x] Index on `kind`

- [x] Task 2: Skill model (AC: #1, #5, #8)
  - [x] `belongs_to :scope, polymorphic: true, optional: true`
  - [x] `kind` enum or string: `internal`, `custom` (default: custom)
  - [x] Name normalization via `name=` setter (downcase, replace non-alphanumeric with `_`, allow `-`)
  - [x] Validations: name format, uniqueness within scope; custom requires scope_type/scope_id/title/content; internal has nil scope
  - [x] Scopes: `for_company`, `for_project`, `internal_skills`, `custom_skills`
  - [x] `merged_for_project(project)` class method with `scope_indicator` (includes internal)
  - [x] `ransackable_attributes` and `ransackable_associations`

- [x] Task 3: Add `has_many :skills` to Company and Project (AC: #9)
  - [x] `has_many :skills, as: :scope, dependent: :destroy` in both models

- [x] Task 4: Company-level controller (AC: #3)
  - [x] `Api::V1::Company::SkillsController` — index, create, update, destroy
  - [x] Strong params: `name`, `title`, `content`, `description`
  - [x] Routes in `config/routes.rb`

- [x] Task 5: Project-level controller (AC: #4)
  - [x] `Api::V1::Company::Projects::SkillsController` — index, create, update, destroy
  - [x] Index uses `Skill.merged_for_project`
  - [x] Routes nested under `projects/:project_id`

- [x] Task 6: Serializer (AC: #7)
  - [x] `Api::V1::SkillSerializer` with `scope_indicator`
  - [x] Attributes: `id`, `name`, `title`, `content`, `description`, `scope_type`, `scope_id`, `scope_indicator`, `created_at`, `updated_at`

- [x] Task 7: Policies (AC: #6)
  - [x] `Api::V1::Company::SkillsPolicy` — admin only
  - [x] `Api::V1::Company::Projects::SkillsPolicy` — project_accessible?

- [x] Task 8: Factory and tests (AC: #1-9)
  - [x] Factory with `:internal`, `:with_company_scope`, `:with_project_scope` traits
  - [x] Model tests: validations, scopes, merged_for_project (with internal), name normalization, kind-conditional validations
  - [x] Controller tests (company-level): CRUD, authorization, name uniqueness
  - [x] Controller tests (project-level): merged list with internal + scope_indicator, authorization

## Dev Notes

### Architecture Pattern — follow exactly

This model follows the **identical pattern** to Agent, Tool, MCPServer, ConfigItem. Every decision below is taken from existing code:

**Model pattern** (see `web/app/models/tool.rb`, `mcp_server.rb` — they have `kind`):
```ruby
belongs_to :scope, polymorphic: true, optional: true  # nil for internal

validates :name, presence: true, format: { with: /\A[a-z][a-z0-9_-]*\z/ }
validates :name, uniqueness: { scope: %i[scope_type scope_id] }
validates :kind, presence: true, inclusion: { in: %w[internal custom] }
validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }, if: :custom?
validates :scope_id, presence: true, if: :custom?
validates :title, presence: true, if: :custom?
validates :content, presence: true, if: :custom?

scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
scope :internal_skills, -> { where(kind: "internal") }
scope :custom_skills, -> { where(kind: "custom") }

def internal? = kind == "internal"
def custom? = kind == "custom"
```

**`merged_for_project` pattern** (returns Array; adds `scope_indicator`; includes internal):
```ruby
def self.merged_for_project(project)
  internals = internal_skills.to_a
  company_items = for_company(project.company).to_a
  project_items = for_project(project).to_a
  project_names = project_items.map(&:name).to_set

  internals.each { |i| i.define_singleton_method(:scope_indicator) { "internal" } }

  company_items.each do |item|
    item.define_singleton_method(:scope_indicator) { "company" }
  end

  project_items.each do |item|
    indicator = company_items.any? { |c| c.name == item.name } ? "overrides_company" : "project"
    item.define_singleton_method(:scope_indicator) { indicator }
  end

  merged = internals + project_items + company_items.reject { |c| project_names.include?(c.name) }
  merged.sort_by(&:name)
end
```

**Controller pattern** (see `agents_controller.rb`, `tools_controller.rb`):
- Company-level: `current_company.skills.ransack(params[:q]).result` for index
- Project-level: `Skill.merged_for_project(current_project)` for index
- Strong params: `params.require(:skill).permit(:name, :title, :content, :description)`
- Uses `respond_with` — no explicit status codes

**Serializer pattern** (see `mcp_server_serializer.rb` — has `internal`):
```ruby
class SkillSerializer < ApplicationSerializer
  attributes :id, :name, :title, :content, :description, :kind,
             :scope_type, :scope_id, :scope_indicator, :internal,
             :created_at, :updated_at

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.internal?
      "internal"
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end

  def internal
    object.internal?
  end
end
```

**Policy pattern** (see `agent_policy.rb`, project-level tool_policy.rb):
- Company: `current_user.admin?` for all actions
- Project: `project_accessible?` via `project.accessible_by?(current_user)`

**Migration pattern** (scope nullable for internal, like tools/mcp_servers):
```ruby
create_table :skills do |t|
  t.string :name, null: false
  t.string :title
  t.text :content
  t.text :description
  t.string :kind, null: false, default: "custom"
  t.string :scope_type    # nullable for internal
  t.bigint :scope_id      # nullable for internal
  t.timestamps
end

add_index :skills, %i[scope_type scope_id name], unique: true
add_index :skills, %i[scope_type scope_id]
add_index :skills, :kind
```

### Skill Content — what goes inside

Skills are markdown instructions injected into agent containers. Each CLI has its own format (Story 9-6 will handle injection):
- **Claude Code**: loaded on-demand via `CLAUDE.md` or skill directory
- **Codex**: `SKILL.md` with YAML front matter (`name`, `description`) in `.codex/skills/<name>/`
- **Gemini CLI**: extensions in `~/.gemini/extensions/<name>/` or custom commands `.gemini/commands/*.toml`
- **Cursor CLI**: auto-discovered from skill directories

For now (this story), we just store `content` as text. Story 9-6 will transform and inject.

### Files to Create/Modify

**New files:**
- `web/db/migrate/YYYYMMDDHHMMSS_create_skills.rb`
- `web/app/models/skill.rb`
- `web/app/controllers/api/v1/company/skills_controller.rb`
- `web/app/controllers/api/v1/company/projects/skills_controller.rb`
- `web/app/serializers/api/v1/skill_serializer.rb`
- `web/app/policies/api/v1/company/skills_policy.rb`
- `web/app/policies/api/v1/company/projects/skills_policy.rb`
- `web/test/factories/skills.rb`
- `web/test/models/skill_test.rb`
- `web/test/controllers/api/v1/company/skills_controller_test.rb`
- `web/test/controllers/api/v1/company/projects/skills_controller_test.rb`

**Modified files:**
- `web/app/models/company.rb` — add `has_many :skills`
- `web/app/models/project.rb` — add `has_many :skills`
- `web/config/routes.rb` — add skill routes

### Key Code References

- **Agent model** (pattern to follow): `web/app/models/agent.rb`
- **Agent controller** (company-level): `web/app/controllers/api/v1/company/agents_controller.rb`
- **Tool project controller** (project-level): `web/app/controllers/api/v1/company/projects/tools_controller.rb`
- **MCP serializer** (scope_indicator): `web/app/serializers/api/v1/mcp_server_serializer.rb`
- **Tool policy** (project-level): `web/app/policies/api/v1/company/projects/tools_policy.rb`
- **Agent factory**: `web/test/factories/agents.rb`
- **Agent controller test**: `web/test/controllers/api/v1/company/agents_controller_test.rb`

### Project Structure Notes

- All paths follow existing conventions exactly
- Controllers in `api/v1/company/` and `api/v1/company/projects/` namespaces
- Policies mirror controller namespace
- Tests in `test/controllers/api/v1/company/` and `test/models/`

### Previous Story Intelligence

Stories 9-1 through 9-4 established:
- `session_config` JSONB on TerminalSession with accessor helpers
- `SessionContextService` as orchestrator for container injection
- Per-CLI adapter pattern: each adapter knows its own config format
- `permit!` was replaced with explicit key whitelist + `to_unsafe_h.slice()`
- `session_tools` table dropped — `tool_ids` in JSONB is source of truth
- MCP env vars removed — internal Aixle MCP injected via adapter config files
- Rubocop enforces `Layout/SpaceInsideArrayLiteralBrackets`

### References

- [Source: ai/cli_agents_deep_research.md — skills per CLI]
- [Source: web/app/models/agent.rb — polymorphic scope pattern]
- [Source: web/app/models/tool.rb — merged_for_project pattern]
- [Source: ai/architecture/api-controller-patterns-2026-01-29.md — controller style]
- [Source: ai/architecture/implementation-patterns-consistency-rules.md — naming]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus (Cursor Agent)

### Debug Log References

- Migration ran successfully in test env, created skills table with 3 indexes
- Model tests: 37/37 passed (validations, scopes, merged_for_project, name normalization, associations)
- Company controller tests: 21/21 passed (CRUD, auth, validation, response format)
- Project controller tests: 10/10 passed (merged list, scope_indicators, overrides, auth)
- Full regression suite: 786/786 passed, 0 failures, 0 errors
- Rubocop: 11 files inspected, 0 offenses

### Completion Notes List

- All 8 tasks implemented following exact patterns from Agent, Tool, MCPServer models
- Skill model supports internal (no scope) and custom (Company/Project scope) kinds
- merged_for_project returns sorted array with internal + company + project skills, project overrides company by name
- Serializer includes scope_indicator (internal/company/project/overrides_company) and internal boolean
- Company-level CRUD restricted to admin role, project-level to project_accessible? (owner/collaborator)
- Name normalization: downcase + replace non-alphanumeric (except hyphens/underscores) with underscore
- Used enumerize for kind enum (consistent with Tool, MCPServer patterns)
- 68 new tests total (37 model + 21 company controller + 10 project controller)

### File List

**New files:**
- web/db/migrate/20260209100001_create_skills.rb
- web/app/models/skill.rb
- web/app/controllers/api/v1/company/skills_controller.rb
- web/app/controllers/api/v1/company/projects/skills_controller.rb
- web/app/serializers/api/v1/skill_serializer.rb
- web/app/policies/api/v1/company/skills_policy.rb
- web/app/policies/api/v1/company/projects/skills_policy.rb
- web/test/factories/skills.rb
- web/test/models/skill_test.rb
- web/test/controllers/api/v1/company/skills_controller_test.rb
- web/test/controllers/api/v1/company/projects/skills_controller_test.rb

**Modified files:**
- web/app/models/company.rb — added `has_many :skills, as: :scope, dependent: :destroy`
- web/app/models/project.rb — added `has_many :skills, as: :scope, dependent: :destroy`
- web/config/routes.rb — added skill routes at company and project levels
- ai/sprint-status.yaml — status updated to in-progress → review
