# Epic 4: Config Items (Secrets & Variables) (Phase 0)

Admins can manage configuration items (secrets and variables) through a unified interface.

**FRs covered:** FR32, FR33, FR34, FR35, FR36

**Phase:** 0 (Foundation - required by all subsequent phases)

**User Outcome:** Single interface to manage both secrets and variables with scoping and container injection.

## Key Concepts

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

## Story 4.1: Config Items CRUD with Type Toggle

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

## Story 4.2: Config Item Scoping (Company/Project Override)

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

## Story 4.3: Encrypt Secrets at Rest

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

## Story 4.4: Inject Config Items into Containers

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

## Story 4.5: Config Items UI

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
