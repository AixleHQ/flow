# Story 36.4: Frontend Permission Props via Inertia Shared Data

Status: review

## Story

As a frontend developer,
I want server-evaluated permission flags shared via Inertia props,
so that the UI gates features based on policy logic instead of raw role string comparison.

## Background — Current State

The frontend currently checks `currentUser?.role === 'admin'` in `AppHeader.tsx` to determine which nav items to show. This is fragile because:

1. It duplicates authorization logic (server policies say `current_user.admin?`, frontend says `role === 'admin'`)
2. It can't express fine-grained permissions (e.g. "can manage members" vs "can manage agents")

**Note:** `super_admin` is NOT a concern here — `Web::ApplicationController#redirect_super_admin_to_admin_panel` redirects super_admins to the admin panel before any Inertia page renders. They never reach company/project pages.

**Goal:** Add a `permissions` object to Inertia shared data, evaluated server-side from policies, and use it in the frontend instead of raw role checks.

## Acceptance Criteria

1. `permissions` object is available in Inertia shared data on all company/project pages
2. `permissions.isAdmin` reflects `current_user.role.admin?` (only `admin` role — `super_admin` never reaches Inertia pages)
3. `permissions.canManageMembers` reflects `MembersPolicy.new(policy_context, current_company).create?`
4. `AppHeader` uses `permissions.isAdmin` instead of `currentUser?.role === 'admin'`
5. TypeScript `SharedProps` type includes `permissions` with proper typing
6. `permissions` is wrapped in `InertiaRails.always { ... }` to ensure it's always fresh
7. All existing tests pass

## Tasks / Subtasks

- [x] Task 1: Add `permissions` to Inertia shared data (AC: 1, 2, 3, 6)
  - [x] In `Web::Company::ApplicationController`, added `inertia_share` block with `permissions`
  - [x] Wrapped in `InertiaRails.always { ... }` so it recalculates on every request
  - [x] Includes `is_admin`, `can_manage_members`, `can_manage_projects`
  - [x] All currently evaluate to `current_user.admin?` (matching existing policies)

- [x] Task 2: Serialization approach — plain hash (AC: 1, 5)
  - [x] Used plain hash (not Alba resource) — simpler for a small, flat permissions object
  - [x] Keys are snake_case; `InertiaPropsCamelizer` converts to camelCase for frontend
  - [x] Manually defined TS type in `types.ts`

- [x] Task 3: Update `SharedProps` TypeScript type (AC: 5)
  - [x] Added `SharedPermissions` interface to `app/frontend/shared/ui/types.ts`
  - [x] Added `permissions?: SharedPermissions` to `SharedProps`
  - [x] Exported `SharedPermissions` from barrel `index.ts`

- [x] Task 4: Update `AppHeader` to use permissions (AC: 4)
  - [x] Replaced `const isAdmin = currentUser?.role === 'admin'` with `const isAdmin = permissions?.isAdmin ?? false`
  - [x] Reads `permissions` from `usePage<SharedProps>().props`
  - [x] `adminOnly` field in menu config unchanged — filter still works

- [x] Task 5: Run tests and verify (AC: 7)
  - [x] `yarn tsc` — clean (exit 0)
  - [x] `docker compose exec web bundle exec rails test` — 12F/11E all pre-existing, none related
  - [x] ESLint on modified files — no errors

## Dev Notes

### Where to Add `inertia_share` for Permissions

**Option A — `Web::Company::ApplicationController` (Recommended):**

The company base controller already has access to `policy_context` and `current_company`. Add a new `inertia_share` block:

```ruby
# app/controllers/web/company/application_controller.rb
inertia_share do
  if signed_in?
    {
      permissions: InertiaRails.always {
        {
          is_admin: current_user.admin?,
          can_manage_members: Web::Company::MembersPolicy.new(policy_context, [:web, :company, :members]).create?,
          can_manage_projects: Web::Company::ProjectsPolicy.new(policy_context, [:web, :company, :projects]).create?
        }
      }
    }
  end
end
```

**Note on policy record:** `dynamic_authorize!` passes `[:web, :company, :agents]` (symbol array) as the record. The policies check `current_user.admin?` and ignore the record entirely. So passing the symbol array as record to the policy constructor is correct.

**Option B — `Web::ApplicationController`:**

The top-level web controller already has an `inertia_share` block. Adding `permissions` here makes it available on ALL web pages including login/onboarding. However, `policy_context` is defined in `Web::Company::ApplicationController`, not the top-level one. You'd need to guard with `respond_to?(:policy_context)` or check `signed_in?` and manually construct the context.

**Recommendation:** Option A is cleaner. Permissions are only meaningful when the user is authenticated and within a company context.

### Existing `inertia_share` in `Web::ApplicationController`

```ruby
# app/controllers/web/application_controller.rb
inertia_share do
  if signed_in?
    {
      current_user: InertiaRails.always { CurrentUserResource.new(current_user).to_h },
      projects: InertiaRails.always { ... },
      flash: flash.to_hash
    }
  else
    { flash: flash.to_hash }
  end
end
```

The `permissions` share in `Web::Company::ApplicationController` will MERGE with these top-level shares. Inertia Rails merges `inertia_share` blocks from all controllers in the chain.

### Serialization Approach — Plain Hash vs Alba Resource

**Plain hash (simpler, recommended for a flat permissions object):**

```ruby
permissions: InertiaRails.always {
  {
    is_admin: current_user.admin?,
    can_manage_members: current_user.admin?,
    can_manage_projects: current_user.admin?
  }
}
```

Inertia's `prop_transformer` (configured in the app) will camelize keys: `is_admin` → `isAdmin`, `can_manage_members` → `canManageMembers`.

**Verify the prop_transformer is configured.** The app has `InertiaRails.config.prop_transformer` set to `camelize(:lower)` — see the Inertia+Alba cursor rule. This means snake_case keys in the hash will become camelCase in the frontend.

**Alba Resource (if Typelizer auto-generation is desired):**

```ruby
# app/resources/permissions_resource.rb
class PermissionsResource < ApplicationResource
  attribute :is_admin
  attribute :can_manage_members
  attribute :can_manage_projects
end
```

This generates a TS type and handles key transformation. But it requires a backing object (not just a hash). You'd need to pass a Struct or OpenStruct:

```ruby
permissions_data = OpenStruct.new(
  is_admin: current_user.admin?,
  can_manage_members: current_user.admin?,
  can_manage_projects: current_user.admin?
)
PermissionsResource.new(permissions_data).to_h
```

**Recommendation:** Use the plain hash approach. Manually define the TS type in `types.ts`. The permissions object is small, stable, and doesn't need Typelizer auto-generation overhead.

### Simplification — All Permissions are `current_user.admin?`

Looking at the current policies:
- `MembersPolicy#create?` → `current_user.admin?`
- `ProjectsPolicy#create?` → `current_user.admin?`

All company-level policies return `current_user.admin?`. So the permissions hash simplifies to:

```ruby
{
  is_admin: current_user.admin?,
  can_manage_members: current_user.admin?,
  can_manage_projects: current_user.admin?
}
```

This is intentionally structured as separate flags even though they're all the same value today. When policies evolve (e.g. non-admins can manage projects), only the server code changes — the frontend already reads the correct flag.

### `current_user.admin?` — No super_admin Concern

`super_admin` users are redirected to the admin panel by `Web::ApplicationController#redirect_super_admin_to_admin_panel` before any Inertia page renders. They never reach company/project pages. So `is_admin` simply uses `current_user.admin?` (the enum check for `admin` role only).

### Frontend Changes — `AppHeader.tsx`

Current code (`app/frontend/shared/ui/AppHeader.tsx`, line 171):
```tsx
const isAdmin = currentUser?.role === 'admin';
```

Replace with:
```tsx
const { permissions } = usePage<SharedProps>().props;
const isAdmin = permissions?.isAdmin ?? false;
```

The `adminOnly` filter on menu items (line 269) stays the same:
```tsx
const visibleItems = menu.items.filter((item) => !item.adminOnly || isAdmin);
```

### TypeScript Type Update

In `app/frontend/shared/ui/types.ts`, add:

```typescript
export interface SharedPermissions {
  isAdmin: boolean;
  canManageMembers: boolean;
  canManageProjects: boolean;
}

export interface SharedProps {
  currentUser: SharedUser | null;
  flash: Record<string, string>;
  projects?: SharedProject[];
  permissions?: SharedPermissions;
  [key: string]: unknown;
}
```

`permissions` is optional because it's not available on unauthenticated pages (login, etc.).

### Files to Create/Modify

| File | Change |
|------|--------|
| `app/controllers/web/company/application_controller.rb` | Add `inertia_share` block with `permissions` |
| `app/frontend/shared/ui/types.ts` | Add `SharedPermissions` interface, update `SharedProps` |
| `app/frontend/shared/ui/AppHeader.tsx` | Replace `role === 'admin'` with `permissions?.isAdmin` |

### Anti-Patterns to Avoid

- **Do NOT create a custom API endpoint for permissions** — use Inertia shared data
- **Do NOT use `useEffect` + `fetch` to load permissions** — they come via props
- **Do NOT duplicate policy logic in TypeScript** — the server is the source of truth
- **Do NOT remove `adminOnly` from menu config** — it's a UI concern, not an auth concern

### References

- [Source: app/controllers/web/application_controller.rb] — existing `inertia_share` block
- [Source: app/controllers/web/company/application_controller.rb] — company base controller
- [Source: app/frontend/shared/ui/AppHeader.tsx] — current role check on line 171
- [Source: app/frontend/shared/ui/types.ts] — SharedProps type
- [Source: app/policies/web/company/members_policy.rb] — MembersPolicy
- [Source: config/initializers/typelizer.rb] — Typelizer config
- [Source: ai/implementation-artifacts/epic-36-policies-dynamic-authorize.md#story-34] — epic design
- [Source: .cursor/rules/rails-rules/inertia-alba-realtime-agent.mdc] — Inertia+Alba patterns

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
- `yarn tsc` — exit 0, clean compilation
- `docker compose exec web bundle exec rails test` — 12F/11E all pre-existing (skill_files, AssetTest, RepositoryTest, SessionContextService, UsageStatisticsController)
- ESLint on modified files — 0 errors

### Completion Notes List
- Used Option A: permissions added in `Web::Company::ApplicationController` (company-scoped, not top-level)
- Plain hash approach chosen over Alba resource — simpler for 3 boolean flags
- `InertiaPropsCamelizer` handles snake_case → camelCase (is_admin → isAdmin)
- `permissions` is optional in `SharedProps` — not present on unauthenticated pages
- All three flags currently evaluate to `current_user.admin?` matching existing policy behavior
- `super_admin` excluded by design — redirected before Inertia pages render

### File List
- `app/controllers/web/company/application_controller.rb` — added `inertia_share` block with permissions
- `app/frontend/shared/ui/types.ts` — added `SharedPermissions` interface, updated `SharedProps`
- `app/frontend/shared/ui/index.ts` — exported `SharedPermissions`
- `app/frontend/shared/ui/AppHeader.tsx` — replaced role string check with `permissions?.isAdmin`
