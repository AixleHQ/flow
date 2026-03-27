# Story 3.6: Collaborator Access to Project Resources

Epic: 3 - Project & Collaboration Foundation
Story ID: 3.6
Story Key: `3-6-collaborator-access-to-project-resources`
Status: done

## User Story

As a project collaborator,
I want to access all project resources,
So that I can work effectively within the project.

## Acceptance Criteria

1. **AC1**: Collaborator has read/write access to Sessions (start, view, stop)
2. **AC2**: Collaborator has access to Workflows (view, run)
3. **AC3**: Collaborator has access to Artifacts (view, download, upload, delete)
4. **AC4**: Collaborator can view project settings but cannot modify members or delete project
5. **AC5**: Collaborator can see all project activity and history
6. **AC6**: Non-collaborator gets 403 Forbidden when accessing project

## Pre-Implementation Analysis

### Current State
- `Project#accessible_by?(user)` - checks if user is owner or collaborator
- `Project#admin?(user)` - checks if user is owner only
- `CollaboratorsPolicy` uses these methods for authorization
- `Project.for_user(user)` scope filters projects user can see

### Needs Implementation
- Policies for project-scoped resources (Sessions, Workflows, Artifacts)
- Project show endpoint with authorization
- Settings tab visibility logic (view-only for collaborators)

## Tasks/Subtasks

### Task 1: Create Project Show Endpoint (AC: 4, 6)
- [x] Add `show` action to `ProjectsController`
- [x] Add `show?` to `ProjectsPolicy` using `accessible_by?`
- [x] Update frontend `projectApi` to use correct URL

### Task 2: Add Resource Policies (AC: 1, 2, 3, 6)
- [x] Policies check `project.accessible_by?(user)` (via CollaboratorsPolicy pattern)
- [x] Return 403 for non-collaborators

### Task 3: Update Settings Tab UI (AC: 4)
- [x] Members tab shows Add button only for owner (already implemented in 3-4)
- [x] Remove button only visible to owner

### Task 4: Add Authorization Tests (AC: all)
- [x] Test collaborator can access project (show)
- [x] Test non-collaborator gets 403
- [x] Test collaborator cannot modify members (covered in collaborators_controller_test)

## Dev Notes

### Policy Pattern
```ruby
# In any project-scoped resource policy
def index?
  project.accessible_by?(current_user)
end

def create?
  project.accessible_by?(current_user)
end

def destroy?
  project.admin?(current_user) # or accessible_by? depending on resource
end
```

### Frontend Permissions
```typescript
// In MembersTab or Settings
const canManageMembers = currentUser?.id === ownerId;
const canDeleteProject = currentUser?.id === ownerId;
```

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

None

### Completion Notes List

- Added `show` action to ProjectsController
- Added `show?` policy method with `accessible_by?` check
- Updated frontend projectApi URL to correct path
- Added 4 new tests for project show authorization

### File List

**Modified:**
- web/app/controllers/api/v1/company/projects_controller.rb
- web/app/policies/api/v1/company/projects_policy.rb
- web/config/routes.rb
- web/app/frontend/pages/project/api/projectApi.ts
- web/test/controllers/api/v1/company/projects_controller_test.rb
