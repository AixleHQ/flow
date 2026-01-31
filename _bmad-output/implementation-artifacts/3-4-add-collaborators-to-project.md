# Story 3.4: Add Collaborators to Project

Status: review

## Story

As a project admin,
I want to add collaborators to my project,
So that team members can access project resources.

## Acceptance Criteria

1. **Given** I am a project admin (owner)
   **When** I navigate to Project page → Members tab/section
   **Then** I can see a list of current project collaborators
   **And** I see the project owner at the top

2. **Given** I see the Members section
   **When** I click "Add Collaborator" button
   **Then** I see a dialog to select a user from my company

3. **Given** I am adding a collaborator
   **When** I search/select a user from my company
   **And** I click "Add"
   **Then** the user is added as a collaborator to the project
   **And** they immediately have access to all project resources
   **And** I see a success message

4. **Given** I try to add a collaborator
   **When** I select a user who is already a collaborator
   **Then** I see a validation error

5. **Given** I try to add a collaborator
   **When** I select a user from a different company
   **Then** I see a validation error (should not be possible in UI)

6. **Given** I am NOT the project owner
   **Then** I cannot see "Add Collaborator" button
   **And** I can only view the collaborators list

## Pre-Implementation Analysis

**Existing Infrastructure:**

**Backend:**
- `ProjectCollaborator` model with validations (same company, not owner)
- `Project#add_collaborator(user)` method
- `Project#collaborators` association

**Missing Backend:**
- `Api::V1::Company::Projects::CollaboratorsController` for CRUD
- Policy for collaborators management

**Frontend:**
- Project page exists but no Members section
- Need new component for collaborators list and add dialog

## Tasks / Subtasks

### Task 1: Create Collaborators API Endpoints (AC: 1, 3, 4, 5)
- [x] Create `Api::V1::Company::Projects::CollaboratorsController`
- [x] Implement `index` action (list collaborators + owner)
- [x] Implement `create` action (add collaborator)
- [x] Implement `destroy` action (remove collaborator)
- [x] Add Pundit policy (only owner can add/remove)
- [x] Add routes: `GET/POST/DELETE /api/v1/company/projects/:project_id/collaborators`

### Task 2: Add Controller Tests (AC: all)
- [x] Test index returns collaborators and owner
- [x] Test create adds collaborator
- [x] Test create with duplicate user fails
- [x] Test create requires project admin
- [x] Test create validates same company
- [x] Test destroy removes collaborator

### Task 3: Create Collaborators List Component (AC: 1, 6)
- [x] Create `MembersTab` component
- [x] Display owner with "Owner" badge
- [x] Display collaborators list
- [x] Show "Add Collaborator" button only for owner

### Task 4: Create Add Collaborator Dialog (AC: 2, 3, 4)
- [x] Create inline dialog in MembersTab
- [x] Fetch company users list
- [x] Filter out existing collaborators and owner
- [x] Select user from dropdown
- [x] Handle API errors

### Task 5: Integrate into Project Page (AC: 1)
- [x] Add Members tab to ProjectPage
- [x] Wire up MembersTab component

## Dev Notes

### API Contract

**GET /api/v1/company/projects/:project_id/collaborators:**
```json
{
  "items": [
    {
      "id": 1,
      "userId": 5,
      "projectId": 10,
      "user": {
        "id": 5,
        "name": "John Doe",
        "email": "john@company.com",
        "role": "employee"
      },
      "isOwner": true,  // Virtual field for owner
      "createdAt": "2026-01-30T10:00:00Z"
    },
    {
      "id": 2,
      "userId": 6,
      "projectId": 10,
      "user": {
        "id": 6,
        "name": "Jane Smith",
        "email": "jane@company.com",
        "role": "employee"
      },
      "isOwner": false,
      "createdAt": "2026-01-31T10:00:00Z"
    }
  ]
}
```

**POST /api/v1/company/projects/:project_id/collaborators:**
```json
// Request
{
  "collaborator": {
    "user_id": 7
  }
}

// Success Response (201 Created)
{
  "data": {
    "id": 3,
    "userId": 7,
    "projectId": 10,
    "user": { ... },
    "isOwner": false,
    "createdAt": "2026-01-31T12:00:00Z"
  }
}

// Error Response (422)
{
  "errors": {
    "user": ["is already a collaborator on this project"]
  }
}
```

### Controller Pattern

```ruby
module Api::V1::Company::Projects
  class CollaboratorsController < Api::V1::Company::ApplicationController
    def index
      project = current_company.projects.find(params[:project_id])
      # Return owner + collaborators
      respond_with project_members(project)
    end

    def create
      project = current_company.projects.find(params[:project_id])
      user = current_company.users.find(collaborator_params[:user_id])
      collaborator = project.add_collaborator(user)
      respond_with collaborator
    end

    private

    def collaborator_params
      params.require(:collaborator).permit(:user_id)
    end

    def project_members(project)
      # Combine owner (as virtual collaborator) + actual collaborators
      # ...
    end
  end
end
```

### Policy

```ruby
module Api::V1::Company::Projects
  class CollaboratorsPolicy < Api::V1::Company::ApplicationPolicy
    def index?
      project_accessible?
    end

    def create?
      project_admin?
    end

    private

    def project
      record.is_a?(Project) ? record : record.project
    end

    def project_accessible?
      project.accessible_by?(current_user)
    end

    def project_admin?
      project.admin?(current_user)
    end
  end
end
```

### Frontend Structure

```
web/app/frontend/
├── pages/
│   └── project/
│       ├── api/
│       │   └── collaboratorsApi.ts  # NEW
│       └── ui/
│           ├── ProjectPage.tsx      # Add Members tab
│           ├── ProjectCollaborators.tsx  # NEW
│           └── AddCollaboratorDialog.tsx # NEW
```

### References

- [Source: ai/epics.md#Story-3.4] - Add Collaborators requirements
- [Source: web/app/models/project.rb] - Project model with add_collaborator
- [Source: web/app/models/project_collaborator.rb] - ProjectCollaborator validations

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

None

### Completion Notes List

- Created `Api::V1::Company::Projects::CollaboratorsController` with index, create, destroy actions
- Created `Api::V1::Company::Projects::CollaboratorsPolicy` for authorization
- Extended `BaseContext` to support project parameter for policy context
- Created `MembersTab` component with collaborators list and add/remove functionality
- Added Members tab to ProjectPage
- Added RTK Query endpoints for collaborators API
- All 160 tests pass, no regressions

### File List

**Created:**
- web/app/controllers/api/v1/company/projects/collaborators_controller.rb
- web/app/policies/api/v1/company/projects/collaborators_policy.rb
- web/app/serializers/project_member_serializer.rb
- web/app/frontend/pages/project/api/collaboratorsApi.ts
- web/app/frontend/pages/project/ui/MembersTab.tsx
- web/test/controllers/api/v1/company/projects/collaborators_controller_test.rb

**Modified:**
- web/config/routes.rb (added collaborators resource)
- web/app/contexts/base_context.rb (added project parameter)
- web/app/models/project.rb (changed add_collaborator to use create!)
- web/app/frontend/pages/project/ui/ProjectPage.tsx (added Members tab)
- web/app/frontend/pages/project/lib/types.ts (added 'members' to ProjectTab)
- web/app/frontend/shared/api/QueryTag.ts (added ProjectCollaborators)
- web/app/frontend/shared/api/routes.ts (added collaborators routes)
