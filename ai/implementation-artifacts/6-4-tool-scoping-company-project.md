# Story 6.4: Tool Scoping (Company/Project)

Status: ready-for-dev

## Story

As a system,
I want tools scoped to company or project level with override logic,
so that project-specific tools can override company defaults.

## Acceptance Criteria

1. Tools have polymorphic scope (Company or Project)
2. Internal tools are global (no scope, kind=internal)
3. Custom tools must have scope (kind=custom)
4. Session/workflow merges project + company tools
5. Project tools override company tools with same name
6. UI shows scope indicators in tool list

## Status: ALREADY IMPLEMENTED IN 6.1

**This story was already completed as part of Story 6.1 implementation.**

### What Was Implemented

1. **Tool Model** (`app/models/tool.rb`):
   - `kind` field: `internal` | `custom` (using Enumerize)
   - Polymorphic `scope` association (Company or Project)
   - `internal?` and `custom?` predicates
   - Scopes: `internal_tools`, `custom_tools`, `for_company`, `for_project`
   - `merged_for_project(project)` - returns internal + company + project with override logic
   - `merged_for_company(company)` - returns internal + company tools

2. **API Endpoints**:
   - `GET /api/v1/company/tools` - merged list for company context
   - `GET /api/v1/company/projects/:id/tools` - merged list for project context
   - CRUD operations for company and project tools

3. **Frontend**:
   - `ToolScopeBadge` component showing scope indicators
   - Filter by kind (internal/custom)
   - Scope indicator in tools table: "internal", "company", "project", "overrides_company"

4. **Tests**:
   - Model tests for scoping and merge logic
   - Controller tests for merged lists and override behavior

## Tasks / Subtasks

- [x] Task 1: Tool model with kind and scope ✅ (done in 6.1)
- [x] Task 2: Merged list logic with override ✅ (done in 6.1)
- [x] Task 3: API endpoints ✅ (done in 6.1)
- [x] Task 4: Frontend scope indicators ✅ (done in 6.1)
- [x] Task 5: Tests ✅ (done in 6.1)

## Dev Notes

### Implementation Summary from 6.1

The scoping was designed with `kind` (internal/custom) separate from polymorphic `scope`:

```ruby
class Tool < ApplicationRecord
  extend Enumerize
  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true
  belongs_to :scope, polymorphic: true, optional: true
  
  validates :scope, presence: true, if: :custom?
  
  scope :internal_tools, -> { where(kind: "internal") }
  scope :for_company, ->(c) { custom_tools.where(scope: c) }
  scope :for_project, ->(p) { custom_tools.where(scope: p) }
end
```

### Merge Logic

```ruby
def self.merged_for_project(project)
  internal = internal_tools.enabled.to_a
  company = for_company(project.company).enabled.to_a
  project_tools = for_project(project).enabled.to_a
  
  # Project tools override company tools with same name
  # Internal tools always included
  # Returns array with scope_indicator singleton method
end
```

### Project Structure Notes

All files already exist:
- `web/app/models/tool.rb`
- `web/app/controllers/api/v1/company/tools_controller.rb`
- `web/app/controllers/api/v1/company/projects/tools_controller.rb`
- `web/app/frontend/features/tools-management/`
- `web/test/controllers/api/v1/company/tools_controller_test.rb`
- `web/test/controllers/api/v1/company/projects/tools_controller_test.rb`

### References

- [Source: _bmad-output/implementation-artifacts/6-1-create-tool-with-types.md]
- [Source: ai/epics.md#Story 6.4]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (6.1 implementation)

### Debug Log References

### Completion Notes List

- Story 6.4 scope functionality was implemented as part of Story 6.1
- No additional work required
- Marking as ready-for-dev → done

### File List

See Story 6.1 file list for all created/modified files.
