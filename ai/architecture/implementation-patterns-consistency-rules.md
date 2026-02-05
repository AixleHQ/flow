# Implementation Patterns & Consistency Rules

## Pattern Categories Defined

**Critical Conflict Points Identified:**
5 main categories of patterns that will prevent conflicts between AI agents during project implementation.

## Naming Patterns

**Database Naming Conventions:**
- **Tables:** snake_case, plural — `users`, `workflows`, `workflow_runs`
- **Columns:** snake_case — `user_id`, `created_at`, `company_id`
- **Foreign keys:** `{table}_id` — `user_id`, `project_id`
- **Indexes:** `idx_{table}_{column}` — `idx_users_email`, `idx_workflows_project_id`
- **Rationale:** Rails convention, consistency with ActiveRecord

**API Naming Conventions:**
- **Endpoints:** Plural resources — `/api/v1/users`, `/api/v1/projects`
- **Nested resources:** `/api/v1/projects/:project_id/workflows`
- **Route parameters:** `:id` format — `/api/v1/users/:id`
- **Query parameters:** snake_case — `user_id`, `project_id`
- **Headers:** `X-Custom-Header` format for custom headers
- **Rationale:** RESTful conventions, consistency with Rails routing

**Code Naming Conventions:**

**Frontend (TypeScript/React):**
- **Components:** PascalCase — `UserCard.tsx`, `WorkflowStepper.tsx`
- **Files:** PascalCase for components — `UserCard.tsx`
- **Functions/Variables:** camelCase — `getUserData()`, `userId`
- **Constants:** UPPER_SNAKE_CASE — `API_BASE_URL`, `MAX_RETRIES`

**Backend (Ruby):**
- **Classes:** PascalCase — `UserCard`, `WorkflowService`
- **Methods/Variables:** snake_case — `get_user_data`, `user_id`
- **Constants:** UPPER_SNAKE_CASE — `API_BASE_URL`

## Structure Patterns

**Project Organization:**

**Backend (Rails):**
- **Tests:** `test/` directory (Rails convention, Minitest)
- **Services:** `app/services/` for business logic
- **Utils:** `lib/` for shared utilities
- **Concerns:** `app/models/concerns/` for shared model logic

**Frontend (React/TypeScript):**
- **Tests:** Co-located — `UserCard.test.tsx` next to `UserCard.tsx`
- **Components:** Feature-Sliced Design structure
- **Shared utilities:** `app/frontend/shared/lib/`
- **Feature utilities:** inside feature folders
- **API clients:** `app/frontend/shared/api/`

**Configuration File Organization:**
- **Rails:** `config/` directory + `settings.yml` for configuration
- **Frontend:** Environment variables + `config/` for constants
- **Docker:** `docker-compose.yml` + `.env` files

## Format Patterns

**API Response Formats:**
- **Lists:** Wrapped in `items` — `{items: [{id: 1, ...}, ...]}`
- **Single resources:** Wrapped in `data` — `{data: {id: 1, ...}}`
- **Implementation:** A base serializer automatically adds wrappers
- **Rationale:** Consistency of API responses, uniformity

**Frontend API Response Types:**
```typescript
// shared/api/types.ts
export interface ApiResponse<T> {
  data: T;  // Single resource response
}

export interface ApiCollectionResponse<T> {
  items: T[];  // List response
}
```

**RTK Query transformResponse:**
- **Single resources:** `transformResponse: (response: ApiResponse<T>) => response.data`
- **Lists:** `transformResponse: (response: ApiCollectionResponse<T>) => response.items`
- **Rationale:** Extracting data from the wrapper for convenient use in components

**Error Response Structure:**
- **Validation errors:** Rails standard — `{errors: {field: ["message"]}}`
- **Other errors:** `{error: "message"}` or `{errors: ["message"]}`
- **Rationale:** Rails convention, consistency

**Date/Time Formats:**
- **Format:** ISO 8601 strings — `"2026-01-21T10:30:00Z"`
- **Rationale:** Standard, consistency between frontend and backend

**JSON Field Naming:**
- **API responses:** snake_case — `user_id`, `created_at` (Rails default)
- **Frontend transformation:** The frontend converts to camelCase when necessary
- **Rationale:** Rails convention in the API, JavaScript convention on the frontend

## Communication Patterns

**Event System Patterns:**
- **Status:** Deferred (events are not used in the MVP)
- **Future:** snake_case with dot notation — `user.created`, `workflow.started`

**State Management Patterns:**

**Redux Toolkit:**
- **Updates:** Immutable via Immer (automatically)
- **Action naming:** `feature/action` — `users/fetchUsers`, `workflows/createWorkflow`
- **Selectors:** `select{Entity}{By}` — `selectUserById`, `selectWorkflowsByProject`
- **Usage:** Global state (API cache, user state)

**Zustand:**
- **Updates:** Immer for immutable updates
- **Actions:** Store methods — `fetchUsers()`, `createWorkflow()`
- **Usage:** Local component state

**Logging Formats:**
- **Backend:** Structured JSON via Lograge — `{"level": "info", "message": "...", "context": {...}}`
- **Frontend:** Structured logging — `console.log({level: "info", message: "...", context: {...}})`
- **Rationale:** Consistency, convenience for log analysis

## Process Patterns

**Error Handling Patterns:**

**Backend (Rails):**
- **Global exception handler:** `ApplicationController` rescue_from
- **Service-level errors:** Custom exceptions in services
- **Validation errors:** ActiveRecord validations

**Frontend:**
- **Error boundaries:** React Error Boundaries for components
- **API error handling:** RTK Query error handling
- **User-facing errors:** Toast notifications (MUI Snackbar)

**Loading State Patterns:**
- **Per-request loading:** RTK Query automatically manages loading states
- **Component-level loading:** Zustand for local loading states
- **Rationale:** Separation of responsibilities, automation where possible

**Validation Timing:**
- **Field validation:** On blur (when focus is lost)
- **Form validation:** On submit (when the form is submitted)
- **Implementation:** React Hook Form default behavior
- **Rationale:** Balance between UX and performance

## Enforcement Guidelines

**All AI Agents MUST:**

1. **Follow naming conventions:**
   - Database: snake_case for all tables and columns
   - API: Plural resources, snake_case in responses
   - Code: PascalCase for components/classes, camelCase/snake_case for functions/variables

2. **Maintain structure consistency:**
   - Backend: Rails conventions (`test/controllers/`, `app/services/`, `lib/`)
   - Frontend: Feature-Sliced Design structure
   - Tests: Co-located for frontend, `test/controllers/` for backend (controllers only)

3. **Use consistent formats:**
   - API responses: `{items: [...]}` for lists, `{data: {...}}` for single resources
   - Errors: Rails standard format
   - Dates: ISO 8601 strings

4. **Follow communication patterns:**
   - State management: Redux Toolkit for global, Zustand for local
   - Logging: Structured JSON everywhere
   - Error handling: Error boundaries + RTK Query + toasts

5. **Implement process patterns:**
   - Loading states: RTK Query for API, Zustand for local
   - Validation: On blur + on submit

**Pattern Enforcement:**
- ESLint/Rubocop for automatic checking of naming conventions
- Code review for checking structure and patterns
- Documentation of patterns in this document as a reference

## Pattern Examples

**Good Examples:**

**Database Naming:**
```ruby
# ✅ Correct
create_table :workflow_runs do |t|
  t.references :workflow, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.datetime :started_at
end

# ❌ Incorrect
create_table :WorkflowRuns do |t|
  t.references :WorkflowId
  t.datetime :StartedAt
end
```

**API Response Format:**
```json
// ✅ Correct - List
{
  "items": [
    {"id": 1, "name": "Workflow 1"},
    {"id": 2, "name": "Workflow 2"}
  ]
}

// ✅ Correct - Single resource
{
  "data": {"id": 1, "name": "Workflow 1"}
}

// ❌ Incorrect - Direct response
[
  {"id": 1, "name": "Workflow 1"},
  {"id": 2, "name": "Workflow 2"}
]
```

**Component Naming:**
```typescript
// ✅ Correct
// UserCard.tsx
export const UserCard = () => { ... }

// ❌ Incorrect
// user-card.tsx
export const userCard = () => { ... }
```

**Anti-Patterns:**
- ❌ Mixing naming conventions (snake_case and camelCase in the same place)
- ❌ Direct API responses without wrappers
- ❌ Global loading states instead of per-request
- ❌ Validation only on submit without on blur
- ❌ Unstructured logging
