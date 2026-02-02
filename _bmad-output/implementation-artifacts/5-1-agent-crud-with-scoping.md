# Story 5.1: Agent CRUD with Scoping

Status: review

## Story

As a company admin,
I want to create and manage agent configurations with persona details,
So that agents can be reused across standalone sessions and workflows.

## Acceptance Criteria

1. **AC1:** Can create agent with: name, title, icon (emoji), persona, communication_style, principles
2. **AC2:** Agent scoped to company or project level (polymorphic scope like ConfigItem)
3. **AC3:** Can edit and delete agents
4. **AC4:** Project agents override company agents with same name (merged list)
5. **AC5:** Source tracking: `custom` or `bmad_import` (for future import feature)
6. **AC6:** UI for managing agents (company-level and project-level)

## Tasks / Subtasks

- [x] Task 1: Create Agent model and migration (AC: 1, 2, 5)
  - [x] 1.1: Create migration with all fields
  - [x] 1.2: Create Agent model with Enumerize, validations, scoping methods
  - [x] 1.3: Add associations to Company and Project models

- [x] Task 2: Create API endpoints (AC: 1, 2, 3, 4)
  - [x] 2.1: Company-level agents controller (CRUD)
  - [x] 2.2: Project-level agents controller (CRUD + merged index)
  - [x] 2.3: Pundit policies
  - [x] 2.4: Serializer

- [x] Task 3: Write backend tests (AC: 1-5)
  - [x] 3.1: Model tests (validations, scoping methods)
  - [x] 3.2: Controller tests

- [x] Task 4: Create Agents UI (AC: 6)
  - [x] 4.1: AgentsPage component with table
  - [x] 4.2: AgentFormDialog (create/edit)
  - [x] 4.3: DeleteAgentDialog
  - [x] 4.4: Add routing and navigation

## Dev Notes

### Model Design

```ruby
# Agent — LLM persona configuration, independent of workflows
# Can be used in standalone sessions or workflow steps
#
# Stores only data for the system prompt (persona fields).
# Does NOT store activation/menu — that is BMAD-specific runtime logic.
class Agent < ApplicationRecord
  extend Enumerize

  belongs_to :scope, polymorphic: true  # Company or Project

  enumerize :scope_type, in: [:company, :project], predicates: true
  enumerize :source, in: [:custom, :bmad_import], default: :custom

  validates :name, presence: true,
                   uniqueness: { scope: [:scope_type, :scope_id], case_sensitive: false },
                   format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, underscores" }
  validates :title, presence: true
  validates :persona, presence: true

  # Merged list for project context
  def self.merged_for_project(project)
    company_agents = project.company.agents.to_a
    project_agents = project.agents.to_a

    # Project agents override company agents with same name
    merged = company_agents.reject { |ca| project_agents.any? { |pa| pa.name == ca.name } }
    merged += project_agents

    # Inject scope_indicator
    merged.each do |agent|
      indicator = if agent.scope_type.project?
        company_agents.any? { |ca| ca.name == agent.name } ? "overrides_company" : "project"
      else
        "company"
      end
      agent.define_singleton_method(:scope_indicator) { indicator }
    end

    merged.sort_by(&:name)
  end

  # Build system prompt from persona fields
  def to_system_prompt
    parts = []
    parts << "# #{title}" if title.present?
    parts << persona if persona.present?
    parts << "\n## Communication Style\n#{communication_style}" if communication_style.present?
    parts << "\n## Principles\n#{principles}" if principles.present?
    parts.join("\n\n")
  end
end
```

### Database Schema

```ruby
create_table :agents do |t|
  t.string :name, null: false           # unique identifier (lowercase_underscore): "analyst", "pm"
  t.string :title, null: false          # display title: "Business Analyst", "Product Manager"
  t.string :icon                        # emoji for UI: "📊", "📋"
  t.text :persona, null: false          # role + identity (who the agent is)
  t.text :communication_style           # how the agent communicates
  t.text :principles                    # operating principles
  t.string :source, null: false, default: "custom"  # custom | bmad_import
  t.string :scope_type, null: false     # Company | Project
  t.bigint :scope_id, null: false
  t.timestamps
end

add_index :agents, %i[scope_type scope_id name], unique: true
add_index :agents, %i[scope_type scope_id]
```

### BMAD Import Mapping

When importing from a BMAD file:

| BMAD XML | Agent field | Notes |
|----------|-------------|-------|
| `id` attribute | — | not used |
| `name` attribute | — | this is the persona's name ("Mary"), not stored |
| `title` attribute | `title` | "Business Analyst" |
| `icon` attribute | `icon` | "📊" |
| `<role>` + `<identity>` | `persona` | combined into a single field |
| `<communication_style>` | `communication_style` | ✅ |
| `<principles>` | `principles` | ✅ |
| `<activation>` | — | not stored (BMAD runtime) |
| `<menu>` | — | not stored (BMAD runtime) |
| filename | `name` | "analyst.md" → "analyst" |

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/company/agents` | List company agents |
| POST | `/api/v1/company/agents` | Create company agent |
| PATCH | `/api/v1/company/agents/:id` | Update company agent |
| DELETE | `/api/v1/company/agents/:id` | Delete company agent |
| GET | `/api/v1/company/projects/:id/agents` | List merged agents (company + project) |
| POST | `/api/v1/company/projects/:id/agents` | Create project agent |
| PATCH | `/api/v1/company/projects/:id/agents/:id` | Update project agent |
| DELETE | `/api/v1/company/projects/:id/agents/:id` | Delete project agent |

### Serializer

```ruby
class AgentSerializer < ApplicationSerializer
  attributes :id, :name, :title, :icon, :persona, :communication_style,
             :principles, :source, :scope_type, :scope_id, :scope_indicator,
             :created_at, :updated_at

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end
end
```

### Frontend Types

```typescript
interface Agent {
  id: number;
  name: string;           // lowercase_underscore
  title: string;          // "Business Analyst"
  icon: string | null;    // emoji
  persona: string;
  communicationStyle: string | null;
  principles: string | null;
  source: 'custom' | 'bmad_import';
  scopeType: 'Company' | 'Project';
  scopeId: number;
  scopeIndicator: 'company' | 'project' | 'overrides_company';
  createdAt: string;
  updatedAt: string;
}
```

### Key Differences from ConfigItem

| Aspect | ConfigItem | Agent |
|--------|------------|-------|
| Name format | UPPERCASE_UNDERSCORE | lowercase_underscore |
| Required fields | name, value | name, title, persona |
| Has encrypted value | Yes (secrets) | No |
| Source tracking | No | Yes (custom/bmad_import) |

### UI Components Structure

```
web/app/frontend/pages/agents/
├── api/
│   └── agentsApi.ts
├── lib/
│   ├── types.ts
│   └── agentSchema.ts
├── ui/
│   ├── AgentsPage.tsx
│   ├── AgentsTable.tsx
│   ├── AgentFormDialog.tsx
│   ├── DeleteAgentDialog.tsx
│   └── AgentScopeBadge.tsx
└── index.ts
```

### References

- [Source: ai/workflow-architecture.md#10.1] — Agent model design
- [Source: ai/epics.md#Story 5.1, 5.4] — Original stories (merged)
- [Pattern: web/app/models/config_item.rb] — Scoping pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5

### Debug Log References

N/A

### Completion Notes List

- Created Agent model with polymorphic scope (Company/Project), Enumerize for source
- Auto-downcase name with validation (lowercase letters, numbers, underscores, starts with letter)
- Implemented `merged_for_project` class method with scope_indicator injection
- Added `to_system_prompt` method for building LLM system prompts from persona fields
- Created company-level and project-level API controllers (CRUD)
- Created Pundit policies (admin for company, project member for project)
- Created AgentSerializer with scope_indicator
- Added routes for agents at company and project levels
- Created full frontend UI: AgentsPage, AgentsTable, AgentFormDialog, DeleteAgentDialog, AgentScopeBadge
- Added company-level route `/company/agents`
- Added Agents tab to ProjectPage for project-level agents
- Added "Agents" nav item to AppHeader (admin only)

### File List

- web/db/migrate/20260202150000_create_agents.rb (new)
- web/app/models/agent.rb (new)
- web/app/models/company.rb (modified - added agents association)
- web/app/models/project.rb (modified - added agents association)
- web/app/controllers/api/v1/company/agents_controller.rb (new)
- web/app/controllers/api/v1/company/projects/agents_controller.rb (new)
- web/app/serializers/agent_serializer.rb (new)
- web/app/policies/api/v1/company/agents_policy.rb (new)
- web/app/policies/api/v1/company/projects/agents_policy.rb (new)
- web/config/routes.rb (modified - added agents routes)
- web/test/controllers/api/v1/company/agents_controller_test.rb (new)
- web/test/controllers/api/v1/company/projects/agents_controller_test.rb (new)
- web/app/frontend/pages/agents/index.ts (new)
- web/app/frontend/pages/agents/lib/types.ts (new)
- web/app/frontend/pages/agents/lib/agentSchema.ts (new)
- web/app/frontend/pages/agents/api/agentsApi.ts (new)
- web/app/frontend/pages/agents/ui/AgentsPage.tsx (new)
- web/app/frontend/pages/agents/ui/AgentsTable.tsx (new)
- web/app/frontend/pages/agents/ui/AgentFormDialog.tsx (new)
- web/app/frontend/pages/agents/ui/DeleteAgentDialog.tsx (new)
- web/app/frontend/pages/agents/ui/AgentScopeBadge.tsx (new)
- web/app/frontend/shared/api/QueryTag.ts (modified - added Agents tag)
- web/app/frontend/shared/routes.ts (modified - added companyAgentsPath)
- web/app/frontend/app/routeTree.tsx (modified - added companyAgentsRoute)
- web/app/frontend/pages/project/lib/types.ts (modified - added 'agents' to ProjectTab)
- web/app/frontend/pages/project/ui/ProjectPage.tsx (modified - added Agents tab)
- web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx (modified - added Agents nav item)
