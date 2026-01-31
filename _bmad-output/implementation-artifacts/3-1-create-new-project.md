# Story 3.1: Create New Project

Status: done

## Story

As a company admin,
I want to create a new project within my company,
So that I can organize work and resources.

## Acceptance Criteria

1. **Given** I am a company admin
   **When** I navigate to Projects Dashboard (`/company/projects`)
   **Then** I can see a "Create Project" button

2. **Given** I see the Projects Dashboard
   **When** I click "Create Project" button
   **Then** I see a dialog/form with fields:
   - Project name (required)
   - Description (optional, textarea)

3. **Given** I am filling out the Create Project form
   **When** I enter a project name and click "Create"
   **Then** a new project is created via API
   **And** I am automatically added as the project owner
   **And** the project is associated with my company (`company_id`)
   **And** I see a success message: "Project created successfully"
   **And** the new project appears in the projects list
   **And** I am redirected to the project overview page

4. **Given** I am creating a project
   **When** I enter a name that already exists in my company
   **Then** I see a validation error: "Project name already exists"
   **And** the project is not created

5. **Given** I am a non-admin user (employee)
   **When** I view the Projects Dashboard
   **Then** I can see the "Create Project" button (all users can create projects)
   **And** I can create a project and become its owner

6. **Given** a project is created
   **Then** a unique slug is auto-generated from the project name
   **And** the project state is set to "active"
   **And** the owner is automatically a collaborator (implicit access)

## Tasks / Subtasks

### Task 1: Create Projects API Endpoint (AC: 3, 4, 6)
- [x] Create `Api::V1::Company::ProjectsController` with `create` action
- [x] Implement project creation with `current_user` as owner
- [x] Add validation for unique name within company
- [x] Create `ProjectSerializer` for API responses
- [x] Add routes: `POST /api/v1/company/projects`
- [x] Add Pundit policy: `Api::V1::Company::ProjectsPolicy#create?`

### Task 2: Create Projects Index Endpoint (AC: 1)
- [x] Add `index` action to `Api::V1::Company::ProjectsController`
- [x] Return all projects accessible by current user (owned + collaborated)
- [x] Include computed fields: collaborators count, last activity date
- [x] Add Ransack for filtering by name

### Task 3: Create Project Dialog Component (AC: 2, 3, 4)
- [x] Create `CreateProjectDialog` component in `pages/projects/ui/`
- [x] Add form fields: name (required), description (optional)
- [x] Add validation using zod schema
- [x] Handle API errors and display validation messages
- [x] Show success snackbar on creation

### Task 4: Update Projects Page (AC: 1, 5)
- [x] Add "Create Project" button to `ProjectsPage.tsx`
- [x] Open dialog on button click
- [x] Refresh projects list after creation
- [x] Navigate to new project after creation

### Task 5: Create RTK Query Endpoints (AC: 3)
- [x] Add `useCreateProjectMutation` to `projectsApi.ts`
- [x] Invalidate projects list on creation
- [x] Handle error responses

### Task 6: Add Controller Tests (AC: all)
- [x] Test create returns new project
- [x] Test create with duplicate name fails
- [x] Test create requires authentication
- [x] Test project is associated with user's company
- [x] Test user becomes owner

## Dev Notes

### Existing Infrastructure

**Models (already exist):**
- `Project` model with: `name`, `description`, `slug`, `state`, `company_id`, `owner_id`
- `ProjectCollaborator` model for many-to-many user-project relationship
- Validations: name uniqueness within company, slug auto-generation
- State machine: `active`, `paused`, `archived`

**Schema (from db/schema.rb):**
```ruby
create_table "projects" do |t|
  t.bigint "company_id", null: false
  t.string "name", null: false
  t.text "description"
  t.string "slug", null: false
  t.string "state", null: false
  t.jsonb "settings", default: {}
  t.bigint "owner_id", null: false
  t.string "preferred_artifacts_language", default: "en"
end
```

**Frontend (already exist):**
- `ProjectsPage.tsx` - displays projects grid (uses mock data currently)
- `ProjectCard` component in `entities/project`
- `useProjectsQuery` hook (needs backend implementation)

### Architecture Patterns

**Controller Pattern (from architecture.md):**
```ruby
module Api::V1::Company
  class ProjectsController < ApplicationController
    def index
      projects = Project.for_user(current_user).ransack(params[:q]).result
      respond_with paginate(projects)
    end

    def create
      project = current_user.company.projects.create(project_params.merge(owner: current_user))
      respond_with project
    end

    private

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
```

**Authorization Pattern:**
```ruby
# app/policies/api/v1/company/projects_policy.rb
module Api::V1::Company
  class ProjectsPolicy < ApplicationPolicy
    def index?
      true # All authenticated users can see their projects
    end

    def create?
      true # All authenticated users can create projects
    end
  end
end
```

### API Contract

**POST /api/v1/company/projects:**
```json
// Request
{
  "project": {
    "name": "My New Project",
    "description": "Optional description"
  }
}

// Success Response (201 Created)
{
  "data": {
    "id": 1,
    "name": "My New Project",
    "description": "Optional description",
    "slug": "my-new-project",
    "state": "active",
    "companyId": 1,
    "ownerId": 5,
    "collaboratorsCount": 0,
    "lastActivityAt": null,
    "createdAt": "2026-01-31T10:00:00Z"
  }
}

// Error Response (422)
{
  "errors": {
    "name": ["has already been taken"]
  }
}
```

**GET /api/v1/company/projects:**
```json
{
  "items": [
    {
      "id": 1,
      "name": "My Project",
      "description": "Description",
      "slug": "my-project",
      "state": "active",
      "companyId": 1,
      "ownerId": 5,
      "collaboratorsCount": 3,
      "lastActivityAt": "2026-01-30T15:00:00Z",
      "createdAt": "2026-01-20T10:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "totalCount": 5,
    "totalPages": 1
  }
}
```

### Frontend Structure (FSD)

```
web/app/frontend/
├── pages/
│   └── projects/
│       ├── api/
│       │   └── projectsApi.ts     # RTK Query endpoints
│       ├── lib/
│       │   └── createProjectSchema.ts  # Zod validation
│       ├── ui/
│       │   ├── ProjectsPage.tsx   # Main page (update)
│       │   └── CreateProjectDialog.tsx  # NEW
│       └── index.ts
└── entities/
    └── project/
        ├── model/
        │   └── types.ts           # IProject interface
        └── ui/
            └── ProjectCard.tsx    # Already exists
```

### CreateProjectDialog Component

```typescript
// pages/projects/ui/CreateProjectDialog.tsx
interface CreateProjectDialogProps {
  open: boolean;
  onClose: () => void;
  onSuccess: (project: IProject) => void;
}

// Form fields:
// - name: string (required, min 2 chars, max 100 chars)
// - description: string (optional, max 500 chars)
```

### Security Considerations

1. **Company Isolation**: Projects are always created within `current_user.company`
2. **Authentication**: All endpoints require authentication
3. **Owner Assignment**: User creating project becomes owner automatically
4. **Slug Generation**: Auto-generated, sanitized, unique within company

### References

- [Source: ai/epics.md#Story-3.1] - Create New Project acceptance criteria
- [Source: ai/architecture.md#API-Controller-Patterns] - Minimalist controller style
- [Source: web/app/models/project.rb] - Existing Project model
- [Source: web/app/frontend/pages/projects/ui/ProjectsPage.tsx] - Existing projects page
- [Source: web/db/schema.rb] - Database schema for projects

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

None

### Completion Notes List

- Created `Api::V1::Company::ProjectsController` with `index` and `create` actions
- Created `Api::V1::Company::ProjectsPolicy` with permissive access (all authenticated users)
- Created `ProjectSerializer` with computed `collaborators_count` and `last_activity_at` fields
- Added Ransack support to `Project` model for filtering by name, description, state
- Updated routes.rb with `resources :projects, only: %i[index create]` under company namespace
- Created `CreateProjectDialog` component with form validation and error handling
- Updated `ProjectsPage` with "Create Project" button and success/empty states
- Updated `IProject` type to match API response (snake_case fields)
- Updated `ProjectCard` to work with new IProject type
- Added RTK Query mutation `useCreateProjectMutation` with cache invalidation
- Created comprehensive controller tests (13 tests covering all acceptance criteria)

### File List

**Created:**
- web/app/controllers/api/v1/company/projects_controller.rb
- web/app/policies/api/v1/company/projects_policy.rb
- web/app/serializers/project_serializer.rb
- web/app/frontend/pages/projects/ui/CreateProjectDialog.tsx
- web/test/controllers/api/v1/company/projects_controller_test.rb

**Modified:**
- web/config/routes.rb (added projects resource)
- web/app/models/project.rb (added ransackable_attributes)
- web/app/frontend/pages/projects/api/projectsApi.ts (updated URL, added mutation)
- web/app/frontend/pages/projects/ui/ProjectsPage.tsx (added create button and dialog)
- web/app/frontend/entities/project/model/types.ts (updated IProject interface)
- web/app/frontend/entities/project/ui/ProjectCard.tsx (updated for new IProject)
- web/app/frontend/pages/project/ui/ProjectPage.tsx (updated mock data)
