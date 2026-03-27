# Story 4.2: Config Item Scoping (Company/Project Override)

Status: review

## Story

As a system,
I want to support company and project level config items with override logic,
So that projects can customize company-wide defaults.

## Acceptance Criteria

1. **AC1:** Config items have `scope_type` (company/project) and `scope_id` ✅ (done in 4-1)
2. **AC2:** Company-level items: `scope_type: Company, scope_id: company.id` ✅ (done in 4-1)
3. **AC3:** Project-level items: `scope_type: Project, scope_id: project.id` ✅ (done in 4-1)
4. **AC4:** Name uniqueness enforced within same scope ✅ (done in 4-1)
5. **AC5:** Same name CAN exist at company AND project level
6. **AC6:** Resolution order: project → company (project wins)
7. **AC7:** API returns merged list with scope indicators for project context

## Tasks / Subtasks

- [x] Task 1: Add merged list method to ConfigItem model (AC: 5, 6, 7)
  - [x] 1.1: Create `merged_for_project` class method that returns company + project items with scope_indicator
  - [x] 1.2: Add `effective_for_project` method that resolves overrides (for container injection)

- [x] Task 2: Update project config_items#index to return merged list (AC: 7)
  - [x] 2.1: Change Projects::ConfigItemsController#index to use merged_for_project
  - [x] 2.2: Update serializer to include `scope_indicator` attribute

- [x] Task 3: Create tests (AC: all)
  - [x] 3.1: Model tests for merged list
  - [x] 3.2: Controller tests for merged index

## Dev Notes

### Model Methods

```ruby
# app/models/config_item.rb

class ConfigItem < ApplicationRecord
  # ... existing code ...

  # Get merged list of company + project items (for display)
  # Returns all items with scope indicators
  def self.merged_for_project(project)
    company_items = for_company(project.company)
    project_items = for_project(project)

    # Combine and mark overrides
    project_names = project_items.pluck(:name)

    result = []

    # Add project items first (they take precedence)
    project_items.each do |item|
      result << item.tap { |i| i.define_singleton_method(:scope_indicator) {
        company_items.exists?(name: i.name) ? "overrides_company" : "project"
      }}
    end

    # Add company items that are NOT overridden
    company_items.where.not(name: project_names).each do |item|
      result << item.tap { |i| i.define_singleton_method(:scope_indicator) { "company" }}
    end

    result
  end

  # Get effective config items for container injection (resolved overrides)
  def self.effective_for_project(project)
    company_items = for_company(project.company).index_by(&:name)
    project_items = for_project(project).index_by(&:name)

    # Merge with project taking precedence
    company_items.merge(project_items).values
  end

  # Check if this project item overrides a company item
  def overrides_company?
    return false unless scope_type == "Project"

    ConfigItem.exists?(
      scope_type: "Company",
      scope_id: scope.company_id,
      name: name
    )
  end
end
```

### Controller

```ruby
# app/controllers/api/v1/company/projects/config_items_controller.rb

def index
  # Returns merged list: company items + project items with scope indicators
  items = ConfigItem.merged_for_project(current_project)
  # Note: pagination handled differently for merged list (array, not AR relation)
  respond_with({ items: items.map { |i| ConfigItemSerializer.new(i).as_json } })
end
```

### Serializer Update

```ruby
# app/serializers/config_item_serializer.rb

class ConfigItemSerializer < ApplicationSerializer
  attributes :id, :name, :description, :item_type, :scope_type, :scope_id,
             :value, :value_editable, :scope_indicator, :created_at, :updated_at

  def value
    object.display_value
  end

  def value_editable
    object.value_editable?
  end

  # Scope indicator for merged list
  # Returns: "company", "project", or "overrides_company"
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

### API Endpoints

```
GET /api/v1/company/config_items          → company items only
GET /api/v1/company/projects/:id/config_items → merged list (company + project)
```

### API Response Example

```json
// GET /api/v1/company/projects/:id/config_items
{
  "items": [
    {
      "id": 1,
      "name": "API_KEY",
      "value": "••••••••",
      "item_type": "secret",
      "scope_type": "Project",
      "scope_indicator": "overrides_company"
    },
    {
      "id": 2,
      "name": "BASE_URL",
      "value": "https://project.example.com",
      "item_type": "variable",
      "scope_type": "Project",
      "scope_indicator": "project"
    },
    {
      "id": 3,
      "name": "TIMEOUT",
      "value": "30",
      "item_type": "variable",
      "scope_type": "Company",
      "scope_indicator": "company"
    }
  ]
}
```

### Project Structure Notes

- Model: `web/app/models/config_item.rb` (modify - add merged methods)
- Controller: `web/app/controllers/api/v1/company/projects/config_items_controller.rb` (modify - change index)
- Serializer: `web/app/serializers/config_item_serializer.rb` (modify - add scope_indicator)
- Tests:
  - `web/test/models/config_item_test.rb` (new)
  - `web/test/controllers/api/v1/company/projects/config_items_controller_test.rb` (modify)

### References

- [Source: ai/epics.md#Story 4.2]
- [Source: _bmad-output/implementation-artifacts/4-1-config-items-crud-with-type-toggle.md]
- [Source: web/app/models/config_item.rb] — existing model

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

N/A

### Completion Notes List

- Added `merged_for_project` class method - returns company + project items with dynamic `scope_indicator` method
- Added `effective_for_project` class method - returns hash of resolved config for container injection (project wins)
- Updated Projects::ConfigItemsController#index to return merged list instead of just project items
- Added `scope_indicator` attribute to ConfigItemSerializer
- Created comprehensive model tests for merge logic and override detection
- Updated controller tests for merged index endpoint

### File List

- web/app/models/config_item.rb (modified - added merged_for_project, effective_for_project)
- web/app/controllers/api/v1/company/projects/config_items_controller.rb (modified - changed index)
- web/app/serializers/config_item_serializer.rb (modified - added scope_indicator)
- web/test/models/config_item_test.rb (new)
- web/test/controllers/api/v1/company/projects/config_items_controller_test.rb (modified)
- web/test/controllers/api/v1/company/config_items_controller_test.rb (modified - fixed set_value → value=)
