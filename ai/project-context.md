---
project_name: 'app'
user_name: 'Artem_petrov'
date: '2026-01-21'
sections_completed:
  ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 50+
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

**Core Technologies:**
- **Backend:** Ruby on Rails 8.0.2, Ruby 3.x
- **Frontend:** React 19.0.0, TypeScript 5.9.3
- **Database:** PostgreSQL 15.3
- **Cache:** Redis 7.2
- **Orchestration:** Temporal (temporalio gem)
- **Build Tool:** Vite 7.3.1
- **UI Library:** Material UI 6.4.7

**Key Dependencies:**
- **Routing:** TanStack Router 1.114.27
- **State Management:** Redux Toolkit 2.7.0 (global), Zustand 5.0.9 (local)
- **Forms:** React Hook Form 7.56.1, Zod 3.24.3
- **Authorization:** Pundit
- **Storage:** Shrine 3.6, AWS S3
- **Container Management:** Docker API 2.3

**Critical Version Constraints:**
- Rails 8.0.2 — use exact version
- React 19 — new JSX transform (no React import needed)
- TypeScript 5.9.3 — strict mode required
- Vite 7.3.1 — requires vite-plugin-ruby for Rails integration

## Critical Implementation Rules

### Language-Specific Rules

**TypeScript/JavaScript:**
- **Strict Mode:** Always enabled (`strict: true` in tsconfig.json)
- **Base URL:** Use `./app/frontend` as base for imports
- **No Unused Code:** `noUnusedLocals` and `noUnusedParameters` enforced
- **Import Order:** Follow ESLint import/order rules (builtin → external → internal → parent → sibling → index)
- **Case Conversion:** Use `camelcaseKeys`/`decamelizeKeys` utilities for API request/response transformation
- **CSRF Token:** Extract from meta tag: `document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')`

**Ruby/Rails:**
- **Frozen String Literals:** Always include `# frozen_string_literal: true` at top of all Ruby files
- **Enumerize:** Use `enumerize` gem for enums, not ActiveRecord enums
- **Naming:** snake_case for methods/variables, PascalCase for classes
- **Validations:** Use ActiveRecord validations with proper error messages
- **Scopes:** Define reusable scopes in models

### Framework-Specific Rules

**React:**
- **No React Import:** React 19 doesn't require `import React from 'react'` for JSX
- **Hooks Rules:** Always follow hooks rules (use at top level, in correct order)
- **Memoization:** Use `useMemo`, `useCallback`, `React.memo` when appropriate for performance
- **Component Structure:** Follow Feature-Sliced Design layers (app → pages → features → entities → shared)
- **State Management:** Redux Toolkit for global state (API cache, user state), Zustand for local component state
- **Forms:** Use React Hook Form with Zod validation, validate on blur + on submit

**Rails:**
- **API Responses:** Wrap lists in `items`, single resources in `data` (via base serializer)
- **Error Handling:** Use `rescue_from` in ApplicationController for global exception handling
- **Authorization:** Use Pundit policies for all resource-level authorization checks
- **Serializers:** Use ActiveModelSerializers for API response formatting
- **Multi-tenancy:** Always filter by `company_id` in all queries

**RTK Query:**
- **Base API:** Use `baseApi` from `shared/api/baseApi.ts` for all API endpoints
- **Case Conversion:** Automatic snake_case ↔ camelCase conversion via interceptors
- **CSRF Token:** Automatically added via axios interceptor
- **Error Handling:** 401 errors redirect to `/login` automatically
- **Query Tags:** Use QueryTag enum for cache invalidation

**TanStack Router:**
- **Type-safe Routes:** Use generated routes from `ts_routes` gem
- **Navigation:** Use `useNavigate()` hook for programmatic navigation

### Testing Rules

**Backend (Rails/Minitest):**
- **Location:** All tests in `test/` directory
- **Structure:** Follow Rails test conventions (test/models, test/controllers, test/services)
- **Fixtures:** Use factories (factory_bot_rails) instead of fixtures
- **Mocks:** Use mocha for mocking

**Frontend (Vitest):**
- **Location:** Co-located tests (`*.test.tsx` next to component files)
- **Structure:** Test component behavior, not implementation details
- **Mocking:** Mock API calls and external dependencies

### Code Quality & Style Rules

**ESLint/Prettier:**
- **Import Order:** Enforced by ESLint (builtin → external → internal → parent → sibling → index)
- **Feature-Sliced Import Groups:** FSD layers grouped separately in imports
- **Prettier:** Auto-format on save, configured via ESLint plugin
- **TypeScript Strict:** All strict checks enabled, no unused locals/parameters

**Code Organization:**
- **Backend:** Rails MVC structure (`app/controllers/`, `app/models/`, `app/services/`)
- **Frontend:** Feature-Sliced Design (`app/frontend/` with layers)
- **Shared Utilities:** `lib/` for Ruby, `app/frontend/shared/lib/` for TypeScript

**Naming Conventions:**
- **Database:** snake_case, plural tables (`users`, `workflows`)
- **API Endpoints:** Plural resources (`/api/v1/users`, `/api/v1/projects`)
- **Frontend Components:** PascalCase (`UserCard.tsx`)
- **Frontend Functions/Variables:** camelCase (`getUserData`, `userId`)
- **Backend Classes:** PascalCase (`UserCard`, `WorkflowService`)
- **Backend Methods/Variables:** snake_case (`get_user_data`, `user_id`)

**Documentation:**
- **Comments:** Use JSDoc for TypeScript functions
- **Ruby:** Use YARD-style comments for complex methods

### Development Workflow Rules

**Git:**
- **Branch Naming:** Use descriptive branch names (feature/, fix/, refactor/)
- **Commit Messages:** Clear, descriptive commit messages

**API Development:**
- **Request Format:** camelCase in frontend, automatically converted to snake_case for backend
- **Response Format:** snake_case from backend, automatically converted to camelCase in frontend
- **Error Format:** Rails standard (`{errors: {...}}` for validation, `{error: "message"}` for others)

### Critical Don't-Miss Rules

**Anti-Patterns to Avoid:**
- ❌ **Mixing naming conventions:** Don't mix snake_case and camelCase in same context
- ❌ **Direct API responses:** Always wrap in `items` (lists) or `data` (single resource)
- ❌ **Global loading states:** Use per-request loading via RTK Query, not global state
- ❌ **Validation only on submit:** Use on blur + on submit pattern
- ❌ **Unstructured logging:** Use structured JSON logging everywhere
- ❌ **Missing frozen_string_literal:** Always include in Ruby files
- ❌ **Forgetting company_id:** Always filter by company_id in multi-tenant queries
- ❌ **Direct state mutation:** Use immutable updates (Immer in Redux Toolkit/Zustand)

**Edge Cases:**
- **CSRF Token:** Must extract from meta tag, not hardcode
- **401 Handling:** Automatic redirect to `/login` via axios interceptor
- **Case Conversion:** Preserve numeric-dash keys (e.g., "9-12") during camelCase conversion
- **API Error Format:** Handle both validation errors (`{errors: {...}}`) and other errors (`{error: "message"}`)

**Security Rules:**
- **Multi-tenancy:** Always filter by `company_id`, never trust user input for company context
- **Authorization:** Use Pundit policies for all resource access checks
- **Secrets:** Never log or display secret values after creation
- **CSRF:** All API requests must include CSRF token

**Performance Gotchas:**
- **Memoization:** Use `useMemo`/`useCallback` for expensive computations, not everything
- **RTK Query:** Leverage automatic caching, don't duplicate state
- **Import Order:** Follow ESLint rules to prevent circular dependencies

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code
- Follow ALL rules exactly as documented
- When in doubt, prefer the more restrictive option
- Update this file if new patterns emerge

**For Humans:**

- Keep this file lean and focused on agent needs
- Update when technology stack changes
- Review quarterly for outdated rules
- Remove rules that become obvious over time

**Last Updated:** 2026-01-21
