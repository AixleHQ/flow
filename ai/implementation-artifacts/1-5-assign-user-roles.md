# Story 1.5: Assign User Roles

Status: done

## Story

As a company admin,
I want to assign roles to company members,
So that I can control access to company resources.

## Acceptance Criteria

1. **Given** I am a company admin
   **When** I navigate to Company Settings → Members
   **Then** I can see each member's current role (Admin/Employee badge)

2. **Given** I am viewing Company Settings → Members
   **When** I click on actions menu for a user
   **Then** I see role change options:
   - "Make Admin" (if user is Employee)
   - "Make Employee" (if user is Admin)

3. **Given** I am changing a member's role
   **When** I click "Make Admin" for an Employee
   **Then** the role change is saved via API
   **And** the member immediately has Admin permissions
   **And** I see a success message: "User role updated to admin"
   **And** the role badge updates in the table

4. **Given** I am changing a member's role
   **When** I click "Make Employee" for an Admin
   **Then** the role change is saved via API
   **And** the member immediately loses Admin permissions
   **And** I see a success message: "User role updated to employee"

5. **Given** I am viewing my own user record
   **When** I open the actions menu
   **Then** I cannot see role change options for myself
   **And** I cannot change my own role (prevent lockout)

6. **Given** there is only one admin in the company
   **When** I try to change that admin's role to Employee
   **Then** I see an error message: "Cannot demote the last admin"
   **And** the role change is prevented

7. **Given** I am a non-admin user
   **When** I try to access role change functionality
   **Then** I receive a 403 Forbidden error
   **And** I cannot see role change options in the UI

## Tasks / Subtasks

### Task 1: Add Self-Role-Change Protection (AC: 5)
- [x] Update `MembersTable.tsx` to hide role change options for current user
- [x] Add `canChangeRole` check: `selectedUser.id !== currentUser.id`
- [x] Apply to both "Make Admin" and "Make Employee" menu items

### Task 2: Add Last Admin Protection - Backend (AC: 6)
- [x] Update `Api::V1::Company::UsersPolicy#update?` to check `not_changing_own_role?`
- [x] Add validation in User model `cannot_demote_last_admin`
- [x] Return appropriate error message when last admin demotion attempted

### Task 3: Add Last Admin Protection - Frontend (AC: 6)
- [x] Update `MembersTable.tsx` to disable "Make Employee" for last admin
- [x] Add check: count of admins in current users list (`isLastAdmin`)
- [x] Show tooltip explaining why action is disabled

### Task 4: Add Controller Tests (AC: 5, 6)
- [x] Test cannot change own role
- [x] Test cannot demote last admin (covered via multiple admin scenarios)
- [x] Test role change success scenarios (already exists)

## Dev Notes

### Implementation Status

**IMPORTANT:** Most of the functionality is already implemented in Story 1-4:
- ✅ `handleRoleChange` function in `MembersTable.tsx`
- ✅ "Make Admin" / "Make Employee" menu items
- ✅ `useUpdateCompanyUserMutation` RTK Query hook
- ✅ Backend `UsersController#update` with role parameter
- ✅ `UsersPolicy#update?` authorization check
- ✅ Controller test `#update changes user role`

**Need to add:**
- 🔲 Self-role-change protection (frontend + backend)
- 🔲 Last admin demotion protection (backend validation + frontend UX)

### Existing Code References

**Frontend - MembersTable.tsx:**
```typescript
// Lines 153-163: handleRoleChange already implemented
const handleRoleChange = async (role: UserRole) => {
  if (!selectedUser) return;
  try {
    await updateUser({ id: selectedUser.id, role }).unwrap();
    enqueueSnackbar(`User role updated to ${role}`, { variant: 'success' });
  } catch {
    enqueueSnackbar('Failed to update user role', { variant: 'error' });
  }
  handleMenuClose();
};

// Lines 260-263: Menu items already exist
{selectedUser?.role === 'employee' && <MenuItem onClick={() => handleRoleChange('admin')}>Make Admin</MenuItem>}
{selectedUser?.role === 'admin' && <MenuItem onClick={() => handleRoleChange('employee')}>Make Employee</MenuItem>}
```

**Backend - UsersController:**
```ruby
# app/controllers/api/v1/company/users_controller.rb
def update
  user = current_company.users.find(params[:id])
  user.update(update_user_params)
  respond_with user
end

def update_user_params
  params.require(:user).permit(:email, :name, :role, :state_event)
end
```

**Backend - UsersPolicy:**
```ruby
# app/policies/api/v1/company/users_policy.rb
def update?
  current_user.admin? && record_exists? && same_company?
end
```

### Required Changes

**MembersTable.tsx - Add canChangeRole check:**
```typescript
// Add alongside existing canDeleteUser
const canChangeRole = selectedUser && currentUser && selectedUser.id !== currentUser.id;

// Update menu items
{canChangeRole && selectedUser?.role === 'employee' && (
  <MenuItem onClick={() => handleRoleChange('admin')}>Make Admin</MenuItem>
)}
{canChangeRole && selectedUser?.role === 'admin' && !isLastAdmin(selectedUser) && (
  <MenuItem onClick={() => handleRoleChange('employee')}>Make Employee</MenuItem>
)}
```

**UsersPolicy - Add not_self check:**
```ruby
def update?
  current_user.admin? && record_exists? && same_company? && not_changing_own_role?
end

private

def not_changing_own_role?
  # If role is being changed, ensure it's not for self
  return true unless record.role_changed?
  record.id != current_user.id
end
```

### Security Considerations

1. **Authorization**: Only company admins can change roles
2. **Self-protection**: Cannot change own role to prevent lockout
3. **Last admin protection**: At least one admin must remain in company
4. **Company isolation**: Can only change roles for users in same company

### API Contract

**PATCH /api/v1/company/users/:id (Role Change):**
```json
// Request
{
  "user": {
    "role": "admin"  // or "employee"
  }
}

// Success Response (200 OK)
{
  "data": {
    "id": 2,
    "email": "user@company.com",
    "name": "John Doe",
    "role": "admin",  // Updated
    "state": "active",
    // ...
  }
}

// Error Response (422) - Last Admin
{
  "errors": {
    "role": ["Cannot demote the last admin"]
  }
}

// Error Response (403) - Self Role Change
{
  "error": "Not authorized"
}
```

### References

- [Source: ai/epics.md#Story-1.5] - Assign User Roles acceptance criteria
- [Source: _bmad-output/implementation-artifacts/1-4-invite-users-to-company.md] - Previous story with base implementation
- [Source: web/app/frontend/pages/company-members/ui/MembersTable.tsx] - Existing role change UI
- [Source: web/app/controllers/api/v1/company/users_controller.rb] - Existing controller
- [Source: web/app/policies/api/v1/company/users_policy.rb] - Existing policy

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5

### Debug Log References

None

### Completion Notes List

- Task 1: Added `canChangeRole` check in `MembersTable.tsx` to prevent users from changing their own role. Menu items "Make Admin" and "Make Employee" now hidden for current user.
- Task 2: Added `not_changing_own_role?` method to `UsersPolicy` to block role changes via API for self. Added `cannot_demote_last_admin` validation to User model.
- Task 3: Added `isLastAdmin` calculation in `MembersTable.tsx`. "Make Employee" option disabled with tooltip for the last remaining admin.
- Task 4: Added controller tests `#update cannot change own role` and enhanced `#update cannot demote the last admin` test.

### Change Log

- 2026-01-31: Implemented Story 1.5 - Assign User Roles with self-protection and last admin protection

### File List

- web/app/frontend/pages/company-members/ui/MembersTable.tsx (modified)
- web/app/policies/api/v1/company/users_policy.rb (modified)
- web/app/models/user.rb (modified)
- web/test/controllers/api/v1/company/users_controller_test.rb (modified)
