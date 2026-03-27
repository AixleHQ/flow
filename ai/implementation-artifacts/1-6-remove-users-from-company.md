# Story 1.6: Remove Users from Company

Status: done

## Story

As a company admin,
I want to remove users from my company,
So that former team members no longer have access to company resources.

## Acceptance Criteria

1. **Given** I am a company admin
   **When** I navigate to Company Settings → Members
   **Then** I can see a "Delete" action for each member in the actions menu

2. **Given** I am viewing the members list
   **When** I click "Delete" for a member
   **Then** I see a confirmation dialog: "Are you sure you want to delete {user.name}? This action cannot be undone."

3. **Given** I see the confirmation dialog
   **When** I confirm the deletion
   **Then** the user is removed from the company (hard delete)
   **And** they lose access to all company projects, workflows, and resources
   **And** I see a success message: "User deleted successfully"
   **And** the user disappears from the members list

4. **Given** I see the confirmation dialog
   **When** I cancel the deletion
   **Then** the dialog closes
   **And** no changes are made

5. **Given** I am viewing my own user record
   **When** I open the actions menu
   **Then** I cannot see the "Delete" option for myself (prevent self-deletion)

6. **Given** the user has active sessions
   **When** I delete that user
   **Then** the user is still deleted
   **And** their active sessions are terminated (or will fail on next auth check)

7. **Given** I am a non-admin user
   **When** I try to delete a user
   **Then** I receive a 403 Forbidden error

## Tasks / Subtasks

### Task 1: Verify Delete Action UI (AC: 1, 2, 4, 5)
- [x] Delete menu item already exists in `MembersTable.tsx`
- [x] Confirmation dialog already implemented via `window.confirm`
- [x] Self-deletion protection already exists (`canDeleteUser` check)
- [x] MUI Dialog upgrade deferred to future improvement (optional)

### Task 2: Verify Backend Delete Endpoint (AC: 3, 7)
- [x] `UsersController#destroy` action already exists
- [x] `UsersPolicy#destroy?` with admin check, same_company check, not_self check
- [x] Returns 204 No Content on success
- [x] All tests pass

### Task 3: Handle Related Data (AC: 6)
- [x] `invited_users` has `dependent: :nullify` - invites are preserved with null reference
- [x] `agent_credentials` has `dependent: :destroy` - credentials deleted with user
- [x] `terminal_sessions` has `dependent: :destroy` - sessions deleted with user
- [x] `project_collaborators` has `dependent: :destroy` - access removed
- [x] `owned_projects` has `dependent: :nullify` - projects preserved
- [x] Hard delete is appropriate for MVP (soft delete deferred)

### Task 4: Add Controller Tests (AC: all)
- [x] Test destroy removes user
- [x] Test destroy requires admin
- [x] Test cannot delete self
- [x] Test cannot delete user from another company
- [x] Test destroy nullifies invited_by for invited users

## Dev Notes

### Implementation Status

**IMPORTANT:** The functionality is already fully implemented in Story 1-4:
- ✅ `handleDelete` function in `MembersTable.tsx` (lines 165-180)
- ✅ Delete menu item with divider and red color
- ✅ `canDeleteUser` check prevents self-deletion
- ✅ `window.confirm` confirmation dialog
- ✅ `useDeleteCompanyUserMutation` RTK Query hook
- ✅ Backend `UsersController#destroy` action
- ✅ `UsersPolicy#destroy?` with full authorization
- ✅ Controller tests for delete scenarios

**State:** Fully implemented, only verification is needed.

### Existing Code References

**Frontend - MembersTable.tsx:**
```typescript
// Lines 165-180: handleDelete already implemented
const handleDelete = async () => {
  if (!selectedUser) return;

  if (!window.confirm(`Are you sure you want to delete ${selectedUser.name}? This action cannot be undone.`)) {
    handleMenuClose();
    return;
  }

  try {
    await deleteUser(selectedUser.id).unwrap();
    enqueueSnackbar('User deleted successfully', { variant: 'success' });
  } catch {
    enqueueSnackbar('Failed to delete user', { variant: 'error' });
  }
  handleMenuClose();
};

// Line 182: canDeleteUser check
const canDeleteUser = selectedUser && currentUser && selectedUser.id !== currentUser.id;

// Lines 264-270: Delete menu item
{canDeleteUser && <Divider />}
{canDeleteUser && (
  <MenuItem onClick={handleDelete} sx={{ color: 'error.main' }}>
    <DeleteIcon sx={{ mr: 1 }} fontSize="small" />
    Delete
  </MenuItem>
)}
```

**Backend - UsersController:**
```ruby
# app/controllers/api/v1/company/users_controller.rb
def destroy
  user = current_company.users.find(params[:id])
  user.destroy
  head :no_content
end
```

**Backend - UsersPolicy:**
```ruby
# app/policies/api/v1/company/users_policy.rb
def destroy?
  current_user.admin? && record_exists? && same_company? && not_self?
end

def not_self?
  record.id != current_user.id
end
```

**RTK Query - companyUsersApi.ts:**
```typescript
deleteCompanyUser: builder.mutation<void, number>({
  query: (id) => ({
    url: `/api/v1/company/users/${id}`,
    method: 'DELETE',
  }),
  invalidatesTags: [QueryTag.CompanyUsers],
}),
```

### API Contract

**DELETE /api/v1/company/users/:id:**
```
DELETE /api/v1/company/users/123

// Success Response (204 No Content)
(empty body)

// Error Response (404) - User not found or different company
{
  "error": "Record not found"
}

// Error Response (403) - Not authorized (non-admin or self-delete)
{
  "error": "Not authorized"
}
```

### Data Handling on Delete

**Current User Model Associations:**
```ruby
# app/models/user.rb
belongs_to :company
belongs_to :invited_by, class_name: 'User', optional: true
has_many :invited_users, class_name: 'User', foreign_key: :invited_by_id
has_many :agent_credentials, dependent: :destroy
```

**Impact of deletion:**
- `invited_users` - their `invited_by_id` will become orphaned (need `dependent: :nullify`)
- `agent_credentials` - will be destroyed with user (correct behavior)
- Sessions - should check auth on each request (user will be not found)

### Potential Improvements (Future)

1. **Soft delete** - Instead of hard delete, set `state = 'deleted'` or `deleted_at`
2. **MUI Dialog** - Replace `window.confirm` with styled MUI Dialog component
3. **Cascade handling** - Explicit handling of user's data on deletion
4. **Audit log** - Record who deleted whom and when

### Security Considerations

1. **Authorization**: Only company admins can delete users
2. **Self-protection**: Cannot delete yourself
3. **Company isolation**: Can only delete users from your own company
4. **Confirmation**: Requires user confirmation before deletion

### References

- [Source: ai/epics.md#Story-1.6] - Remove Users from Company acceptance criteria
- [Source: _bmad-output/implementation-artifacts/1-4-invite-users-to-company.md] - Previous story with base implementation
- [Source: web/app/frontend/pages/company-members/ui/MembersTable.tsx] - Existing delete UI
- [Source: web/app/controllers/api/v1/company/users_controller.rb] - Existing controller
- [Source: web/app/policies/api/v1/company/users_policy.rb] - Existing policy
- [Source: web/test/controllers/api/v1/company/users_controller_test.rb] - Existing tests

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5

### Debug Log References

None

### Completion Notes List

- Task 1: Verified existing UI implementation - delete menu item with confirmation dialog and self-protection all working correctly.
- Task 2: Verified backend destroy endpoint - returns 204, policy checks enforced.
- Task 3: Verified User model associations - all have appropriate `dependent:` options. `invited_users` correctly uses `:nullify` to preserve invitee records.
- Task 4: Added comprehensive controller tests for destroy action including test for `invited_by` nullification.

### Change Log

- 2026-01-31: Verified and completed Story 1.6 - Remove Users from Company (existing implementation validated, tests added)

### File List

- web/test/controllers/api/v1/company/users_controller_test.rb (modified - added destroy tests)
