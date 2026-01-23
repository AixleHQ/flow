# Story 1.3: User Profile & Company Assignment

Status: ready-for-dev

## Story

As a user,
I want to view and update my profile information,
So that my account information is accurate and up-to-date.

## Acceptance Criteria

1. **Given** I am a signed-in user
   **When** I navigate to my profile page (`/profile` or `/settings/profile`)
   **Then** I can see my:
   - Email address (from Google OAuth, read-only, displayed with lock icon)
   - Display name (editable text field)
   - Company name (read-only, shows my assigned company)
   - Role within company (read-only, displayed as badge)

2. **Given** I am viewing my profile page
   **When** I see my email address
   **Then** it is displayed as read-only (cannot be edited)
   **And** I see a tooltip or helper text: "Email is managed by Google OAuth and cannot be changed"

3. **Given** I am viewing my profile page
   **When** I update my display name
   **And** I click "Save Changes" button
   **Then** the changes are saved via `PATCH /api/v1/current_user`
   **And** I see a success message: "Profile updated successfully"
   **And** the updated name appears immediately on the page
   **And** the updated name appears in the header/navigation
   **And** the updated name persists after page reload

4. **Given** I am viewing my profile page
   **When** I see my company name
   **Then** it displays the company I'm assigned to (from `current_user.company.name`)
   **And** it is read-only (cannot be edited by regular users)
   **And** if I'm a super admin without a company, it shows "Platform Administrator"

5. **Given** I am viewing my profile page
   **When** I see my role
   **Then** it displays my role as a badge (e.g., "Admin", "Employee", "Super Admin")
   **And** it is read-only (cannot be edited by self)
   **And** the badge color matches the role importance (super_admin: purple, admin: blue, employee: gray)

6. **Given** I am on the profile page
   **When** I try to save changes without modifying anything
   **Then** the Save button is disabled
   **And** it becomes enabled only when I make changes to editable fields

7. **Given** I am editing my profile
   **When** I clear my display name field
   **Then** I see a validation error: "Name is required"
   **And** the Save button is disabled
   **And** I cannot submit the form

8. **Given** I am on any page of the application
   **When** I need to access my profile
   **Then** I can navigate to it via:
   - User menu dropdown in the header (clicking on my avatar/name)
   - Direct URL `/profile` or `/settings/profile`
   **And** the navigation is highlighted when I'm on the profile page

## Tasks / Subtasks

### Task 1: Create Profile Page UI Component (AC: 1, 2, 3, 4, 5, 6, 7)
- [ ] Create `ProfilePage.tsx` in `web/app/frontend/pages/profile/ui/`
  - [ ] Use Feature-Sliced Design structure
  - [ ] Create page layout with form container
  - [ ] Add page title "My Profile"
  - [ ] Use Material-UI Card for form container
- [ ] Add read-only fields display:
  - [ ] Email field with lock icon and helper text
  - [ ] Company name field (read-only)
  - [ ] Role badge with conditional styling
- [ ] Add editable name field:
  - [ ] Use react-hook-form for form management
  - [ ] Use zod schema for validation (name required, min 2 chars)
  - [ ] TextField with label "Display Name"
  - [ ] Show validation errors inline
- [ ] Add Save button:
  - [ ] Disabled state when no changes or validation errors
  - [ ] Loading state during API call
  - [ ] Use `useUpdateCurrentUserMutation` from RTK Query
- [ ] Add success/error notifications:
  - [ ] Use notistack for snackbar notifications
  - [ ] Show success message after save
  - [ ] Show error message on API failure

### Task 2: Add Profile Route and Navigation (AC: 8)
- [ ] Add profile route to `routeTree.tsx`
  - [ ] Create `/profile` route under `authLayoutRoute`
  - [ ] Lazy load ProfilePage component
  - [ ] Add to TanStack Router configuration
- [ ] Update routes configuration in `shared/routes.ts`
  - [ ] Add `profilePath` constant
  - [ ] Export for use in navigation
- [ ] Add profile link to user menu:
  - [ ] Update Header component (if exists) or create user menu dropdown
  - [ ] Add "My Profile" menu item
  - [ ] Add avatar/name display that opens dropdown
  - [ ] Highlight active route when on profile page

### Task 3: Update Current User API Integration (AC: 3)
- [ ] Verify `currentUserApi.ts` has update mutation
  - [ ] Confirm `useUpdateCurrentUserMutation` exists
  - [ ] Ensure it uses `PATCH /api/v1/current_user`
  - [ ] Verify it accepts `{ name: string }` parameter
- [ ] Add optimistic updates:
  - [ ] Update cache immediately on mutation
  - [ ] Rollback on error
  - [ ] Invalidate `getCurrentUser` query after success
- [ ] Update `ICurrentUserResponse` interface:
  - [ ] Ensure `company` object has `name` field
  - [ ] Ensure `role` and `state` are properly typed
  - [ ] Add JSDoc comments for clarity

### Task 4: Add Controller Tests (AC: All)
- [ ] Create `web/test/controllers/api/v1/current_user_controller_test.rb`
  - [ ] Test `PATCH #update` with name change
  - [ ] Test validation failure (empty name)
  - [ ] Test that email/company/role cannot be changed via this endpoint
  - [ ] Test response format includes updated name
  - [ ] Test authentication required
  - [ ] Use factories for test data
  - [ ] Follow test patterns from Story 1.1

### Task 5: Add Frontend Integration Tests (AC: 3, 6, 7, 8)
- [ ] Test profile page rendering:
  - [ ] All fields display correctly
  - [ ] Email is read-only
  - [ ] Save button disabled initially
- [ ] Test name update flow:
  - [ ] Type new name
  - [ ] Save button becomes enabled
  - [ ] Click save
  - [ ] Success message appears
  - [ ] Name updates in header
- [ ] Test validation:
  - [ ] Clear name field
  - [ ] Validation error appears
  - [ ] Save button disabled
- [ ] Test navigation:
  - [ ] Can navigate to profile from user menu
  - [ ] Profile route is accessible

## Dev Notes

### Current Implementation Status (from Story 1.1)

**Already Implemented:**
- ✅ `CurrentUserController` with `show` and `update` actions
- ✅ `CurrentUserSerializer` with company data
- ✅ `useGetCurrentUserQuery` hook (RTK Query)
- ✅ `useUpdateCurrentUserMutation` hook (RTK Query)
- ✅ `ICurrentUserResponse` interface with camelCase fields
- ✅ Authentication required for all current user endpoints
- ✅ Company branding included in API response

**What Needs to Be Built:**
- ❌ Profile page UI component
- ❌ Profile route in TanStack Router
- ❌ User menu dropdown with profile link
- ❌ Form validation for name field
- ❌ Frontend tests for profile page

### Architecture Compliance

**Feature-Sliced Design Structure:**
```
web/app/frontend/
├── pages/
│   └── profile/
│       ├── ui/
│       │   ├── ProfilePage.tsx          # Main page component
│       │   └── ProfileForm.tsx          # Form component (optional)
│       └── lib/
│           └── profileSchema.ts         # Zod validation schema
├── entities/
│   └── user/
│       ├── api/
│       │   └── currentUserApi.ts        # Already exists, verify update mutation
│       └── model/
│           └── types.ts                 # Already exists, verify interfaces
└── shared/
    └── routes.ts                        # Add profilePath constant
```

**Backend Structure (Already Exists):**
```
web/app/
├── controllers/
│   └── api/
│       └── v1/
│           └── current_user_controller.rb  # Already has show & update
├── serializers/
│   └── current_user_serializer.rb          # Already includes company data
└── test/
    └── controllers/
        └── api/
            └── v1/
                └── current_user_controller_test.rb  # Already exists, add more tests
```

### API Contract (Already Implemented)

**GET /api/v1/current_user:**
```json
{
  "id": 1,
  "email": "user@company.com",
  "name": "John Doe",
  "role": "employee",
  "state": "active",
  "position": "dev",
  "preferredAgentLanguage": "en",
  "configuredAgents": ["claude_code"],
  "onboardingCompletedAt": "2026-01-22T10:00:00Z",
  "company": {
    "id": 1,
    "name": "Acme Corp",
    "emailDomain": "acme.com",
    "logoUrl": "https://...",
    "primaryColor": "#4785FF",
    "secondaryColor": "#bb9af7"
  }
}
```

**PATCH /api/v1/current_user:**
```json
{
  "name": "Updated Name"
}
```

**Response:** Same as GET (full user object)

### Form Validation Schema

```typescript
// web/app/frontend/pages/profile/lib/profileSchema.ts
import { z } from 'zod';

export const profileSchema = z.object({
  name: z.string()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters')
    .trim(),
});

export type IProfileFormData = z.infer<typeof profileSchema>;
```

### Testing Requirements

**Controller Tests:**
```ruby
# web/test/controllers/api/v1/current_user_controller_test.rb
test "#update with valid name" do
  patch :update, params: { current_user: { name: "New Name" } }
  assert_response :success
  @user.reload
  assert { @user.name == "New Name" }
end

test "#update with empty name fails" do
  patch :update, params: { current_user: { name: "" } }
  assert_response :unprocessable_entity
end

test "#update cannot change email" do
  original_email = @user.email
  patch :update, params: { current_user: { email: "hacker@evil.com" } }
  @user.reload
  assert { @user.email == original_email }
end

test "#update cannot change role" do
  original_role = @user.role
  patch :update, params: { current_user: { role: "admin" } }
  @user.reload
  assert { @user.role == original_role }
end
```

**Frontend Tests (Optional for MVP, but recommended):**
- Profile page renders correctly
- Name field is editable
- Save button enables/disables appropriately
- Validation errors display
- Success message appears after save
- Name updates throughout UI

### UI/UX Considerations

**Material-UI Components:**
- Use `Card` component for profile container
- Use `TextField` for name input (variant="outlined")
- Use `Chip` component for role badge
- Use `LockIcon` for read-only fields
- Use `Button` with loading spinner during save

**Layout:**
```
┌─────────────────────────────────────────┐
│  My Profile                             │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ Email                  🔒         │ │
│  │ user@company.com                  │ │
│  │ Email is managed by Google OAuth  │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ Display Name                      │ │
│  │ John Doe                          │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ Company                 🔒        │ │
│  │ Acme Corp                         │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │ Role                    [Admin]   │ │
│  └───────────────────────────────────┘ │
│                                         │
│  [Save Changes]  (disabled initially)  │
└─────────────────────────────────────────┘
```

**Responsive Design:**
- Desktop-only for MVP (min-width: 1024px)
- Center profile card (max-width: 600px)
- Proper spacing and padding

### Security Considerations

1. **Authentication:**
   - Profile page requires authentication (wrapped in `AuthLayout`)
   - API endpoint already has `authenticate_user!` before_action

2. **Authorization:**
   - Users can only update their own profile
   - Cannot change email (OAuth-managed)
   - Cannot change role (admin-only)
   - Cannot change company (admin-only)

3. **Validation:**
   - Frontend: Zod schema validation
   - Backend: ActiveRecord validations (already in User model)

4. **XSS Prevention:**
   - Material-UI TextField sanitizes input
   - Backend serializer uses safe JSON serialization

### Performance Considerations

1. **Optimistic Updates:**
   - Update UI immediately when user saves
   - Rollback if API call fails
   - Provides instant feedback

2. **Cache Management:**
   - Invalidate `getCurrentUser` query after successful update
   - Header and other components automatically update via RTK Query cache

3. **API Efficiency:**
   - Single PATCH request for updates
   - Only send changed fields (though currently sends full object)

### Previous Story Learnings (from Story 1.1)

**What Worked Well:**
1. ✅ RTK Query with automatic cache management
2. ✅ Camel case conversion between frontend/backend
3. ✅ Material-UI components with theme
4. ✅ TanStack Router for type-safe routing
5. ✅ Controller tests with factories

**Patterns to Follow:**
1. **API Integration:**
   - Use `baseApi.injectEndpoints` for new endpoints
   - Use `providesListTag` for cache tags
   - Use snackbar for success/error notifications

2. **Form Management:**
   - Use react-hook-form with zod resolver
   - Use controlled components
   - Disable submit button during loading

3. **Testing:**
   - Controller tests for all API endpoints
   - Use factories (FactoryBot) for test data
   - Test happy path and error cases
   - Test authentication/authorization

4. **File Organization:**
   - Follow Feature-Sliced Design
   - Keep types close to usage
   - Export shared types from entities

**Challenges from Story 1.1:**
1. ⚠️ React Strict Mode caused duplicate snackbars (use `useRef` to prevent)
2. ⚠️ TanStack Router navigation in render function caused errors (use `useEffect`)
3. ⚠️ State machine events vs states confusion (document clearly)

### References

- [Source: ai/epics.md#Story-1.3] - User Profile & Company Assignment acceptance criteria
- [Source: ai/architecture.md#Frontend-Architecture] - Feature-Sliced Design structure
- [Source: ai/architecture.md#API-Design] - REST API patterns and serialization
- [Source: ai/architecture.md#Authentication--Security] - Authentication and authorization
- [Source: ai/ux-design-specification.md#Profile-Page] - Profile page design (if exists)
- [Source: _bmad-output/implementation-artifacts/1-1-platform-admin-company-management.md] - Previous story patterns and learnings
- [Source: web/app/controllers/api/v1/current_user_controller.rb] - Current User API implementation
- [Source: web/app/frontend/entities/user/api/currentUserApi.ts] - RTK Query hooks

## Dev Agent Record

### Agent Model Used

(To be filled by dev agent during implementation)

### Debug Log References

(To be filled by dev agent)

### Completion Notes List

(To be filled by dev agent)

### File List

**To be Created:**
- `web/app/frontend/pages/profile/ui/ProfilePage.tsx` - Main profile page component
- `web/app/frontend/pages/profile/ui/index.ts` - Barrel export
- `web/app/frontend/pages/profile/lib/profileSchema.ts` - Zod validation schema

**To be Modified:**
- `web/app/frontend/app/routeTree.tsx` - Add profile route
- `web/app/frontend/shared/routes.ts` - Add profilePath constant
- `web/test/controllers/api/v1/current_user_controller_test.rb` - Add tests for name update validation
- `web/app/frontend/entities/user/api/currentUserApi.ts` - Verify update mutation (likely no changes needed)
- `web/app/frontend/entities/user/model/types.ts` - Verify interfaces (likely no changes needed)
- Header/Navigation component (create if doesn't exist) - Add user menu dropdown with profile link
