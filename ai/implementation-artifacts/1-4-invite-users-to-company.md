# Story 1.4: Invite Users to Company

Status: review

## Story

As a company admin,
I want to invite users to my company by email,
So that they can join the platform and access company resources.

## Acceptance Criteria

1. **Given** I am a company admin
   **When** I navigate to Company Settings → Members (`/company/members`)
   **Then** I can see a paginated list of all company members with:
   - Name, email, role badge, state badge (active/pending/archived)
   - Last activity date
   - "Invite User" button at the top
   - Filters: by role, state, email (search), name (search)

2. **Given** I am viewing Company Settings → Members
   **When** I click "Invite User" button
   **Then** I see a dialog with:
   - Email address input field (required, must end with @{company.email_domain})
   - Name input field (required)
   - Role selector (Admin/Employee, default: Employee)
   - "Invite" button
   - "Cancel" button

3. **Given** I am inviting a user
   **When** I enter valid email and name, click "Invite"
   **Then** a `User` record is created in database with:
   - State = `active` (always for invited users)
   - `invited_by_id` = current user
   - `invited_at` = current timestamp
   **And** I see a success message: "User invited successfully"
   **And** the user appears in the members list

4. **Given** I am inviting a user
   **When** I enter an email that doesn't end with @{company.email_domain}
   **Then** I see a validation error: "Email must end with @{company.email_domain}"
   **And** the user is not created

5. **Given** I am inviting a user
   **When** I enter an email of an existing user
   **Then** I see a validation error: "User with this email already exists"
   **And** no duplicate is created

6. **Given** I see a user in members list
   **When** I click "Archive" action
   **Then** the user state changes to `archived`
   **And** they can no longer sign in

7. **Given** I see an archived user in members list
   **When** I click "Activate" action
   **Then** the user state changes to `active`

### Filters (AC: 1)

8. **Given** I am viewing members list
   **When** I filter by role (Admin/Employee)
   **Then** I see only users with selected role

9. **Given** I am viewing members list
   **When** I filter by state (active/pending/archived)
   **Then** I see only users with selected state

10. **Given** I am viewing members list
    **When** I search by email or name
    **Then** I see users matching the search query (partial match)

### OAuth Registration Flow (auto_accept_users)

11. **Given** a new user signs in via Google OAuth
    **And** their email domain matches a company with `auto_accept_users = true`
    **And** no existing user record for this email
    **Then** a new User is created with state = `active`
    **And** they proceed to onboarding

12. **Given** a new user signs in via Google OAuth
    **And** their email domain matches a company with `auto_accept_users = false`
    **And** no existing user record for this email
    **Then** a new User is created with state = `pending`
    **And** they cannot access the platform (AuthLayout redirects to login with message)

13. **Given** an existing user with state = `pending` signs in via OAuth
    **Then** they cannot access the platform (AuthLayout handles this)
    **And** their state does NOT change automatically

## Extended Scope: Company Layout with Whitelabeling

### AC9: Company Layout Structure
**Given** I navigate to any company settings page (`/company/*`)
**Then** I see a Company Layout with:
- Header showing company logo and name (from `current_user.company.branding`)
- Sidebar navigation with menu items: Members, Settings, Branding
- Content area for the active page
- Back button to return to main app (Projects)

### AC10: Whitelabeling Theme Application
**Given** the company has custom branding colors
**When** I view any Company Settings page
**Then** the sidebar navigation uses `primary_color` for active items
**And** buttons use `primary_color` as primary color
**And** the header background uses a subtle tint of `primary_color`
**And** if no custom colors, defaults are used (#4785FF, #bb9af7)

## Tasks / Subtasks

### Task 1: Add Invitation Fields to User Model (AC: 3, 4)
- [x] Create migration to add fields to `users` table:
  - [x] `invited_by_id` (references users, nullable)
  - [x] `invited_at` (datetime, nullable)
- [x] Update `User` model:
  - [x] Add `belongs_to :invited_by, class_name: 'User', optional: true`
  - [x] Add `has_many :invited_users, class_name: 'User', foreign_key: :invited_by_id`
  - [x] Add validation: email domain matches company domain (on create)
  - [x] Add scope: `invited` → where invited_by_id is not null
  - [x] Add callback to set `invited_by` and `invited_at` when created via API:
    ```ruby
    attr_accessor :inviter
    before_create :set_invitation_fields

    def set_invitation_fields
      return unless inviter.present?
      self.invited_by = inviter
      self.invited_at = Time.current
      self.state = :active  # Invited users always active
    end
    ```

### Task 2: Create Users Management API Endpoints (AC: 1-10)
- [x] Create `Api::V1::Company::UsersController`
  - [x] `index` - list company users with Ransack + pagination:
    ```ruby
    def index
      users = current_company.users.ransack(params[:q]).result
      respond_with paginate(users)
    end
    ```
  - [x] `create` - invite new user (always creates with `active` state)
  - [x] `update` - change user state (activate, archive) via state_event
- [x] Create `CompanyUserSerializer` for API responses (updated UserSerializer)
- [x] Add routes:
  ```ruby
  namespace :company do
    resources :users, only: [:index, :create, :update]
  end
  ```
- [x] Add Pundit policy: `UserPolicy` with `index?`, `create?`, `update?` (only admins can manage company users)
- [x] Configure Ransack searchable attributes:
  - [x] `email_cont` - email contains
  - [x] `name_cont` - name contains
  - [x] `role_eq` - role equals
  - [x] `state_eq` - state equals

### Task 3: Handle Pending Users in Frontend (AC: 12, 13)
- [x] Update AuthLayout to handle pending user state:
  - [x] If `current_user.state === 'pending'` → redirect to login with message
  - [x] Show appropriate error message on login page
- [x] Note: OAuth flow already implemented in `GoogleOmniAuthService`:
  - New users get `state = company.auto_accept_users ? 'active' : 'pending'`
  - Existing users keep their current state

### Task 4: Create Company Layout Component (AC: 9, 10)
- [x] Create `CompanyLayout` in `app/frontend/app/layouts/CompanyLayout/`
  - [x] Header with company logo and name
  - [x] Sidebar navigation: Members, Settings, Branding
  - [x] Back button to /projects
  - [x] Content area with `<Outlet />`
- [x] Create `CompanySidebar` component
  - [x] Active state highlighting with primary_color
  - [x] Menu items with icons (People, Settings, Palette)
- [x] Create `useCompanyTheme` hook for dynamic theming
  - [x] Override MUI primary/secondary colors from company branding
  - [x] Wrap CompanyLayout content with dynamic ThemeProvider

### Task 5: Create Company Members Page (AC: 1-10)
- [x] Create `CompanyMembersPage` in `app/frontend/pages/company-members/`
  - [x] Use Feature-Sliced Design structure
  - [x] Members table: name, email, role badge, state badge, actions
  - [x] "Invite User" button opening dialog
  - [x] Actions dropdown: Activate (for archived/pending), Archive, Make Admin, etc.
  - [x] Pagination controls
- [x] Create filters section:
  - [x] Search input (email/name) → `q[email_or_name_cont]`
  - [x] Role dropdown (All/Admin/Employee) → `q[role_eq]`
  - [x] State dropdown (All/Active/Pending/Archived) → `q[state_eq]`
- [x] Create `InviteUserDialog` component
  - [x] Email input with validation (must end with @{company.email_domain})
  - [x] Name input with validation
  - [x] Role selector (Admin/Employee)
  - [x] "Invite" button
  - [x] Domain validation error display
- [x] Create RTK Query endpoints in `companyUsersApi.ts`:
  - [x] `useGetCompanyUsersQuery` - GET /api/v1/company/users with filter params
  - [x] `useCreateCompanyUserMutation` - POST /api/v1/company/users (invite)
  - [x] `useUpdateCompanyUserMutation` - PATCH /api/v1/company/users/:id (change state/role)

### Task 6: Add Routes and Navigation (AC: 9)
- [x] Add company routes to `routeTree.tsx`:
  - [x] `/company` - CompanyLayout wrapper (redirect to /company/members)
  - [x] `/company/members` - CompanyMembersPage
  - [x] `/company/settings` - Placeholder (future story)
  - [x] `/company/branding` - Placeholder (future story)
- [x] Add routes to `shared/routes.ts`
- [x] Update AppHeader with link to Company Settings (for admins only)

### Task 7: Controller Tests (AC: All)
- [x] Create `test/controllers/api/v1/company/users_controller_test.rb`
  - [x] Test index returns company users
  - [x] Test index with filters (role, state, search)
  - [x] Test index pagination
  - [x] Test create (invite) creates active user
  - [x] Test create with invalid email domain
  - [x] Test create with existing email
  - [x] Test update state (activate, archive)
  - [x] Test authorization (only admins)
- [x] Note: OAuth tests already exist in GoogleOmniAuthService tests

## Dev Notes

### Simplified Architecture (No Invitation Model)

**Changes in the User model:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ... existing code ...

  # Invitation tracking
  belongs_to :invited_by, class_name: 'User', optional: true
  has_many :invited_users, class_name: 'User', foreign_key: :invited_by_id

  # Scopes
  scope :invited, -> { where.not(invited_by_id: nil) }
  scope :pending, -> { where(state: 'pending') }

  # Validation for new users (on create)
  validate :email_domain_matches_company, on: :create

  private

  def email_domain_matches_company
    return if company.blank? || email.blank?
    return if super_admin?

    domain = email.split('@').last
    return if domain == company.email_domain

    errors.add(:email, "domain must match company domain (#{company.email_domain})")
  end
end
```

**Migration:**
```ruby
# db/migrate/xxx_add_invitation_fields_to_users.rb
class AddInvitationFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :invited_by, foreign_key: { to_table: :users }, null: true
    add_column :users, :invited_at, :datetime

    add_index :users, :invited_by_id
    add_index :users, :invited_at
  end
end
```

### Invite User Flow

```
Admin clicks "Invite User"
    ↓
Dialog: email (must be @company.email_domain), name, role
    ↓
POST /api/v1/company_users
    ↓
Backend creates User:
  - state = 'active' (ALWAYS for invites)
  - invited_by_id = current_user.id
  - invited_at = Time.current
  - password = nil (will authenticate via OAuth)
    ↓
User appears in members list as "Active"
    ↓
[Later] User signs in via Google OAuth
    ↓
User found, state == 'active' → sign in, proceed to onboarding/app
```

### OAuth Registration Flow (New Users - Self-Registration)

```
New user signs in via Google OAuth
    ↓
Backend: User.find_by(email: email) → nil (not found)
    ↓
Backend: Company.find_by_email_domain(email) → company
    ↓
If company.nil? → redirect to login: "No company found for your domain"
    ↓
Backend creates User:
  - state = company.auto_accept_users ? 'active' : 'pending'
  - invited_by_id = nil (self-registered)
  - invited_at = nil
    ↓
If state == 'active' → sign in, proceed to onboarding
If state == 'pending' → redirect to login: "Account pending approval"
```

### OAuth Sign-in Flow (Existing Users)

```
Existing user signs in via Google OAuth
    ↓
Backend: User.find_by(email: email) → user
    ↓
If user.active? → sign in, proceed to app
If user.pending? → redirect to login: "Account pending approval" (NO auto-activation!)
If user.archived? → redirect to login: "Account has been deactivated"
```

### API Contract

**GET /api/v1/company/users:**
```
GET /api/v1/company/users?q[role_eq]=admin&q[state_eq]=active&q[email_or_name_cont]=john&page=1&per_page=25
```

```json
{
  "items": [
    {
      "id": 1,
      "email": "admin@company.com",
      "name": "John Admin",
      "role": "admin",
      "state": "active",
      "position": "dev",
      "invitedAt": null,
      "invitedBy": null,
      "createdAt": "2026-01-20T10:00:00Z"
    },
    {
      "id": 2,
      "email": "invited@company.com",
      "name": "Jane Invited",
      "role": "employee",
      "state": "active",
      "position": null,
      "invitedAt": "2026-01-28T10:00:00Z",
      "invitedBy": {
        "id": 1,
        "name": "John Admin"
      },
      "createdAt": "2026-01-28T10:00:00Z"
    }
  ],
  "meta": {
    "currentPage": 1,
    "totalPages": 3,
    "totalCount": 52,
    "perPage": 25
  }
}
```

**POST /api/v1/company/users (Invite):**
```json
// Request
{
  "company_user": {
    "email": "newuser@company.com",  // MUST end with @{company.email_domain}
    "name": "New User",
    "role": "employee"
  }
}

// Response (201 Created)
{
  "data": {
    "id": 3,
    "email": "newuser@company.com",
    "name": "New User",
    "role": "employee",
    "state": "active",  // ALWAYS active for invites
    "invitedAt": "2026-01-29T15:00:00Z",
    "invitedBy": {
      "id": 1,
      "name": "John Admin"
    }
  }
}

// Error Response (422 Unprocessable Entity) - wrong domain
{
  "errors": {
    "email": ["must end with @company.com"]
  }
}
```

**PATCH /api/v1/company_users/:id (Change State):**
```json
// Request
{
  "company_user": {
    "state_event": "activate"  // or "archive", "suspend"
  }
}

// Response (200 OK)
{
  "data": {
    "id": 2,
    "state": "active",
    // ... rest of user data
  }
}
```

### OAuth Flow (Already Implemented)

OAuth logic is already implemented in `GoogleOmniAuthService`:

```ruby
# app/services/google_omni_auth_service.rb (existing)
def find_or_create_user
  user = User.find_or_initialize_by(email: email)

  if user.new_record?
    company = Company.find_by_email_domain(email)
    user.company = company
    user.state = company&.auto_accept_users ? "active" : "pending"
    user.role = "employee"
  end

  # ... update OAuth attributes and save
end
```

**What needs to be added:**
- The Frontend (AuthLayout) must check `current_user.state`
- If `state === 'pending'` → redirect to login with a message

### Controller Implementation

```ruby
# app/controllers/api/v1/company/application_controller.rb
module Api::V1::Company
  class ApplicationController < Api::V1::ApplicationController
    private

    def current_company
      @current_company ||= current_user.company
    end
  end
end
```

```ruby
# app/controllers/api/v1/company/users_controller.rb
module Api::V1::Company
  class UsersController < ApplicationController
    # GET /api/v1/company/users
    def index
      authorize User  # Pundit policy check
      users = current_company.users.ransack(params[:q]).result
      respond_with paginate(users)
    end

    # POST /api/v1/company/users
    def create
      authorize User  # Pundit policy check
      user = current_company.users.create(user_params)
      respond_with user
    end

    # PATCH /api/v1/company/users/:id
    def update
      user = current_company.users.find(params[:id])
      authorize user  # Pundit policy check
      user.update(user_params)
      respond_with user
    end

    private

    def user_params
      params.require(:user).permit(:email, :name, :role, :state_event).merge(inviter: current_user)
    end
  end
end
```

```ruby
# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  def index?
    user.admin?
  end

  def create?
    user.admin?
  end

  def update?
    user.admin? && same_company?
  end

  private

  def same_company?
    record.company_id == user.company_id
  end
end
```

**Note:** `inviter` is passed in params and, via the callback, sets `invited_by`, `invited_at`, `state = :active`.

### Company Layout Structure

```
web/app/frontend/
├── app/
│   └── layouts/
│       ├── AuthLayout/
│       │   └── AuthLayout.tsx
│       ├── CompanyLayout/           # NEW
│       │   ├── CompanyLayout.tsx
│       │   ├── CompanySidebar.tsx
│       │   ├── CompanyHeader.tsx
│       │   ├── useCompanyTheme.ts
│       │   └── index.ts
│       └── index.ts
├── pages/
│   └── company-members/             # NEW
│       ├── ui/
│       │   ├── CompanyMembersPage.tsx
│       │   ├── MembersTable.tsx
│       │   └── InviteUserDialog.tsx
│       ├── lib/
│       │   └── inviteUserSchema.ts
│       └── index.ts
└── entities/
    └── company-user/                # NEW (or extend user entity)
        ├── api/
        │   └── companyUserApi.ts
        └── model/
            └── types.ts
```

### Whitelabeling Implementation

**useCompanyTheme Hook:**
```typescript
// app/frontend/app/layouts/CompanyLayout/useCompanyTheme.ts
import { useMemo } from 'react';
import { createTheme, Theme } from '@mui/material/styles';
import { useGetCurrentUserQuery } from 'entities/user';
import { baseTheme } from 'shared/theme';

export const useCompanyTheme = (): Theme => {
  const { data: user } = useGetCurrentUserQuery();

  return useMemo(() => {
    const primaryColor = user?.company?.primaryColor || '#4785FF';
    const secondaryColor = user?.company?.secondaryColor || '#bb9af7';

    return createTheme({
      ...baseTheme,
      palette: {
        ...baseTheme.palette,
        primary: {
          main: primaryColor,
          // Generate light/dark variants
          light: adjustColor(primaryColor, 20),
          dark: adjustColor(primaryColor, -20),
        },
        secondary: {
          main: secondaryColor,
        },
      },
    });
  }, [user?.company?.primaryColor, user?.company?.secondaryColor]);
};
```

**CompanySidebar:**
```typescript
const menuItems = [
  { path: '/company/members', label: 'Members', icon: <PeopleIcon /> },
  { path: '/company/settings', label: 'Settings', icon: <SettingsIcon /> },
  { path: '/company/branding', label: 'Branding', icon: <PaletteIcon /> },
];
```

### Security Considerations

1. **Authorization:**
   - Only company admins can access `/company/*` pages
   - Only company admins can invite/manage users
   - Users can only see members of their own company
   - CompanyLayout should check `current_user.admin?`

2. **Validation:**
   - Email domain must match company domain
   - Cannot create duplicate users (email unique)
   - Cannot demote last admin (prevent lockout)

3. **State Transitions:**
   - Only valid AASM transitions allowed via API
   - StateEventConcern handles `state_event` param

### Existing State Machine (Already Implemented)

From `user_state_machine.rb`:
- States: `active` (initial), `pending`, `suspended`, `archived`
- Events: `activate`, `suspend`, `archive`, `mark_pending`
- Transitions work correctly with StateEventConcern

### References

- [Source: ai/epics.md#Story-1.4] - Invite Users to Company acceptance criteria
- [Source: ai/architecture.md#State-Machine-Pattern] - AASM with StateEventConcern
- [Source: ai/architecture.md#API-Response-Formats] - {items: [...]} for lists
- [Source: _bmad-output/retrospectives/epic-2-retrospective.md] - Access model decisions
- [Source: web/app/state_machines/user_state_machine.rb] - Existing user states
- [Source: web/app/models/company.rb] - auto_accept_users field, branding methods
- [Source: web/db/schema.rb] - Current database schema

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5

### Debug Log References

None

### Completion Notes List

- Task 1: Added migration `20260130100000_add_invitation_fields_to_users.rb` with `invited_by_id` and `invited_at` columns. Updated User model with associations, validation, scopes, and callback for setting invitation fields.
- Task 2: Created `Api::V1::Company::UsersController` with index (Ransack filtering + pagination), create (invite), and update (state change) actions. Added `UserPolicy` for Pundit authorization. Updated `UserSerializer` with invitation fields and created `UserBriefSerializer` for nested user references.
- Task 3: Updated `AuthLayout` to check user state and redirect pending/archived/suspended users to login with appropriate error messages. Added `deactivated` error handling to LoginPage.
- Task 4: Created `CompanyLayout` with header (company logo/name, back button), sidebar navigation, and dynamic theming via `useCompanyTheme` hook that applies company branding colors.
- Task 5: Created `CompanyMembersPage` with members table, filters (search, role, state), pagination, and `InviteUserDialog`. Implemented RTK Query endpoints in `companyUsersApi.ts`.
- Task 6: Added company routes to `routeTree.tsx` and `shared/routes.ts`. Updated `AppHeader` with "Company Settings" menu item for admins.
- Task 7: Created comprehensive controller tests covering all endpoints, filters, pagination, authorization, and error cases. All 124 tests pass.
- Additional: Added `Pundit::NotAuthorizedError` and `ActiveRecord::RecordNotFound` error handlers to API ApplicationController. Fixed test factories to generate emails matching company domain.

### Change Log

- 2026-01-30: Initial implementation of Story 1.4 - Invite Users to Company with Company Layout and Whitelabeling

### File List

**Backend (Ruby on Rails):**
- web/db/migrate/20260130100000_add_invitation_fields_to_users.rb (new)
- web/app/models/user.rb (modified)
- web/app/controllers/api/v1/application_controller.rb (modified)
- web/app/controllers/api/v1/company/application_controller.rb (new)
- web/app/controllers/api/v1/company/users_controller.rb (new)
- web/app/controllers/concerns/authorization_concern.rb (modified)
- web/app/policies/user_policy.rb (new)
- web/app/serializers/user_serializer.rb (modified)
- web/app/serializers/user_brief_serializer.rb (new)
- web/config/routes.rb (modified)
- web/test/factories/users.rb (modified)
- web/test/controllers/admin/users_controller_test.rb (modified)
- web/test/controllers/api/v1/company/users_controller_test.rb (new)

**Frontend (React/TypeScript):**
- web/app/frontend/app/layouts/AuthLayout/AuthLayout.tsx (modified)
- web/app/frontend/app/layouts/CompanyLayout/index.ts (new)
- web/app/frontend/app/layouts/CompanyLayout/CompanyLayout.tsx (new)
- web/app/frontend/app/layouts/CompanyLayout/CompanyHeader.tsx (new)
- web/app/frontend/app/layouts/CompanyLayout/CompanySidebar.tsx (new)
- web/app/frontend/app/layouts/CompanyLayout/useCompanyTheme.ts (new)
- web/app/frontend/app/layouts/index.ts (modified)
- web/app/frontend/app/routeTree.tsx (modified)
- web/app/frontend/pages/company-members/index.ts (new)
- web/app/frontend/pages/company-members/api/companyUsersApi.ts (new)
- web/app/frontend/pages/company-members/lib/types.ts (new)
- web/app/frontend/pages/company-members/lib/inviteUserSchema.ts (new)
- web/app/frontend/pages/company-members/ui/CompanyMembersPage.tsx (new)
- web/app/frontend/pages/company-members/ui/MembersTable.tsx (new)
- web/app/frontend/pages/company-members/ui/InviteUserDialog.tsx (new)
- web/app/frontend/pages/login/ui/LoginPage.tsx (modified)
- web/app/frontend/shared/api/types.ts (modified)
- web/app/frontend/shared/api/index.ts (modified)
- web/app/frontend/shared/api/QueryTag.ts (modified)
- web/app/frontend/shared/routes.ts (modified)
- web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx (modified)
- web/package.json (modified - added use-debounce, date-fns)
