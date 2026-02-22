# Rails Rules Audit — Model Query Methods & Scopes

Date: 2025-02-22
Rules checked: `rails-dev-auto.mdc` — sections "Model Query Methods & Scopes", "Changing Existing Code", "Testing Conventions"

## Reference: Gold Standard

`Workflow` model follows all rules correctly:
- `merged_for_project` → returns `ActiveRecord::Relation` via `.or()`
- `merged_for_company` → returns `ActiveRecord::Relation` (`active.for_company`)
- `scope_indicator` → proper instance method, no `define_singleton_method`
- Controllers chain `.ransack().result` and `paginate()` directly

## Violations Found

### 1. `define_singleton_method(:scope_indicator)` on AR records

**Rule:** "NEVER use `define_singleton_method` to inject virtual attributes on AR records — use serializer logic instead"

Every model except `Workflow` uses `define_singleton_method(:scope_indicator)` inside `merged_for_*` methods:

| Model | Methods | Locations |
|-------|---------|-----------|
| `Skill` | `merged_for_project` | `app/models/skill.rb:49,52,57` |
| `Tool` | `merged_for_project`, `merged_for_company` | `app/models/tool.rb:55,62,68,83,88` |
| `MCPServer` | `merged_for_project`, `merged_for_company` | `app/models/mcp_server.rb:52,59,65,80,85` |
| `Agent` | `merged_for_project` | `app/models/agent.rb:47,53` |
| `Repository` | `merged_for_project` | `app/models/repository.rb:23,24` |
| `Asset` | `merged_for_project` | `app/models/asset.rb:41,46` |
| `ConfigItem` | `merged_for_project` | `app/models/config_item.rb:47,53` |

**Note:** `agent_session_strategy.rb` uses `define_singleton_method(:original_filename)` on `StringIO`/`Tempfile` objects — this is a known Rails pattern for ActiveStorage uploads, NOT an AR violation.

### 2. Model methods returning Arrays instead of ActiveRecord::Relation

**Rule:** "Model methods used by controllers for listing/filtering MUST return `ActiveRecord::Relation`"

**Company-level methods (simpler — no deduplication needed):**

| Model | Method | Returns | Controller | Ransack? |
|-------|--------|---------|------------|----------|
| `Tool` | `merged_for_company` | Array | `ToolsController#index` | No |
| `MCPServer` | `merged_for_company` | Array | `MCPServersController#index` | No |
| `Skill` | `visible_for_company` | **Relation** ✅ | `SkillsController#index` | **Yes** ✅ |
| `Workflow` | `merged_for_company` | **Relation** ✅ | `WorkflowsController#index` | **Yes** ✅ |

→ `Tool` and `MCPServer` need `visible_for_company` scopes (same fix as `Skill`).

**Project-level methods (complex — deduplication/overrides needed):**

| Model | Method | Returns | Has override logic? |
|-------|--------|---------|---------------------|
| `Skill` | `merged_for_project` | Array | Yes (name-based overrides + scope_indicator) |
| `Tool` | `merged_for_project` | Array | Yes (name-based overrides + scope_indicator) |
| `MCPServer` | `merged_for_project` | Array | Yes (name-based overrides + scope_indicator) |
| `Agent` | `merged_for_project` | Array | Yes (name-based overrides) |
| `Repository` | `merged_for_project` | Array | Yes (full_name-based overrides) |
| `Asset` | `merged_for_project` | Array | Yes (name-based overrides) |
| `ConfigItem` | `merged_for_project` | Array | Yes (name-based overrides) |
| `Workflow` | `merged_for_project` | **Relation** ✅ | No overrides — all visible |

→ Project-level `merged_for_project` methods have legitimate business logic (deduplication) that can't be expressed as a simple SQL `OR` scope. These are **documented exceptions**.
→ However, models that also need a "show all without deduplication" query (for session context etc.) should ALSO have `visible_for_project` scopes.

### 3. Company-level controllers: missing ransack/pagination capability

Because `Tool.merged_for_company` and `MCPServer.merged_for_company` return arrays, these controllers can't use ransack or pagination:

```
# app/controllers/api/v1/company/tools_controller.rb
tools = Tool.merged_for_company(current_company)        # Array — no ransack possible

# app/controllers/api/v1/company/mcp_servers_controller.rb
servers = MCPServer.merged_for_company(current_company)  # Array — no ransack possible
```

Compare with the fixed `Skill` pattern:
```
skills = Skill.visible_for_company(current_company).ransack(params[:q]).result  # Relation ✅
```

### 4. scope_indicator could be a proper instance method

`Workflow` model demonstrates the correct approach — `scope_indicator` as a real instance method:

```ruby
def scope_indicator
  scope_type == "Company" ? "company" : "project"
end
```

For models with `kind: internal`, this extends to:
```ruby
def scope_indicator
  return "internal" if internal?
  scope_type == "Company" ? "company" : "project"
end
```

The "overrides_company" indicator is the only case that genuinely requires runtime context (knowing which project-level records shadow company-level ones). This belongs in the serializer or a decorator, not `define_singleton_method`.

## Priority Recommendations

### P1 — Quick wins (same pattern as Skill fix)

Add `visible_for_company` scopes to `Tool` and `MCPServer`:

```ruby
# Tool
scope :visible_for_company, ->(company) { internal_tools.or(for_company(company)) }

# MCPServer
scope :visible_for_company, ->(company) { internal_servers.or(for_company(company)) }
```

Update company controllers to use scope + ransack.

### P2 — Add `scope_indicator` instance method

Add to `Skill`, `Tool`, `MCPServer`:
```ruby
def scope_indicator
  return "internal" if internal?
  scope_type == "Company" ? "company" : "project"
end
```

Add to `Agent`, `Repository`, `Asset`, `ConfigItem`:
```ruby
def scope_indicator
  scope_type == "Company" ? "company" : "project"
end
```

Then serializers use `object.scope_indicator` instead of relying on `define_singleton_method`. The "overrides_company" case needs a separate strategy (serializer context or decorator).

### P3 — Refactor `merged_for_project` methods

Once `scope_indicator` is an instance method, `merged_for_project` can be simplified — it only needs to handle deduplication (removing company records shadowed by project records), not injecting `scope_indicator`.

Alternatively, add `visible_for_project` scopes (like Skill already has) for cases where deduplication isn't needed, keeping `merged_for_project` only for contexts that need override detection (session launches).

## Not Violations

- `define_singleton_method` in test stubs (`stub_support.rb`, `*_test.rb`) — correct usage for test doubles
- `define_singleton_method(:original_filename)` on IO objects — standard Rails/ActiveStorage pattern
- `.map`, `.select` in test assertions — testing response bodies, not querying DB
