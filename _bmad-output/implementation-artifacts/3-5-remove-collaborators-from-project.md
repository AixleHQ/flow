# Story 3.5: Remove Collaborators from Project

Epic: 3 - Project & Collaboration Foundation
Story ID: 3.5
Story Key: `3-5-remove-collaborators-from-project`
Status: done

## User Story

As a project admin,
I want to remove collaborators from my project,
So that former team members lose access to project resources.

## Acceptance Criteria

1. **AC1**: Project admin can see list of collaborators with remove option
2. **AC2**: Confirmation dialog shown before removal
3. **AC3**: User removed from project on confirmation
4. **AC4**: Removed user loses access to project resources
5. **AC5**: Success message displayed after removal
6. **AC6**: Admin cannot remove themselves (prevent lockout)

## Pre-Implementation Analysis

### Already Implemented (from Story 3-4)
- `DELETE /api/v1/company/projects/:project_id/collaborators/:id` endpoint exists
- `CollaboratorsController#destroy` action implemented
- `CollaboratorsPolicy#destroy?` authorization (project_admin only)
- Frontend `MembersTab` with remove button and `handleRemoveCollaborator`

### Missing/Needs Enhancement
- Confirmation dialog (currently uses `confirm()` - need proper MUI dialog)
- Cannot remove self validation (backend)
- Success message (Snackbar)
- Active sessions termination (future enhancement, not blocking)

## Tasks/Subtasks

### Task 1: Add Backend Validation (AC: 6)
- [x] Add validation in `CollaboratorsController#destroy` to prevent self-removal
- [x] Return appropriate error message

### Task 2: Enhance Frontend Confirmation Dialog (AC: 2, 5)
- [x] Replace `confirm()` with MUI `Dialog` component
- [x] Add success Snackbar after removal
- [x] Handle error cases with appropriate messages

### Task 3: Add Controller Tests (AC: 6)
- [x] Test admin cannot remove themselves

## Dev Notes

### API Contract (Already Exists)
```
DELETE /api/v1/company/projects/:project_id/collaborators/:user_id
Response: 204 No Content
Error: 422 with { errors: { base: ["Cannot remove yourself"] } }
```

### Frontend Enhancement
- Use `useSnackbar` from notistack for success messages
- Create `RemoveCollaboratorDialog` component or inline in `MembersTab`

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

None

### Completion Notes List

- Added self-removal validation in CollaboratorsController#destroy
- Replaced browser confirm() with MUI Dialog for better UX
- Added notistack Snackbar for success/error messages

### File List

**Modified:**
- web/app/controllers/api/v1/company/projects/collaborators_controller.rb
- web/app/frontend/pages/project/ui/MembersTab.tsx
- web/test/controllers/api/v1/company/projects/collaborators_controller_test.rb
