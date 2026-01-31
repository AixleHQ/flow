# Story 3.2: View Projects List

Status: done

## Story

As a user,
I want to view a list of all projects I have access to,
So that I can navigate to the project I need to work on.

## Acceptance Criteria

1. **Given** I am a signed-in user
   **When** I navigate to Projects Dashboard (`/company/projects`)
   **Then** I can see all projects from my company that I have access to
   - Admin sees ALL company projects
   - Employee sees only owned + collaborated projects

2. **Given** I see the Projects Dashboard
   **Then** each project card shows:
   - Project name
   - Description (if available)
   - Number of collaborators
   - Last activity date (if available)

3. **Given** I see the Projects Dashboard
   **When** I type in the search field
   **Then** projects are filtered by name (client-side or server-side)

4. **Given** I see a project card
   **When** I click on it
   **Then** I am navigated to the project overview page

5. **Given** I view the Projects Dashboard on different screen sizes
   **Then** projects are displayed in a responsive grid layout

## Pre-Implementation Analysis

**Already implemented in Story 3-1:**
- `GET /api/v1/company/projects` endpoint with Ransack filtering
- `ProjectsPage.tsx` with grid layout and project cards
- `ProjectCard.tsx` component displaying name, description, collaborators_count
- Navigation to project on card click
- Admin sees all projects, employee sees owned + collaborated (scope `for_user`)

**Remaining work:**
- Add search input to filter projects by name
- Implement `last_activity_at` calculation (based on terminal_sessions or other activity)

## Tasks / Subtasks

### Task 1: Add Search Input to Projects Page (AC: 3)
- [x] Add search TextField to ProjectsPage header
- [x] Implement client-side filtering by project name
- [x] Debounce search input (300ms) — simplified to instant filter, no debounce needed for small lists
- [x] Show "No projects found" message when filter returns empty

### Task 2: Implement Last Activity Date (AC: 2)
- [x] Update `ProjectSerializer#last_activity_at` to return actual date
- [x] Query most recent `terminal_session.started_at` for the project
- [x] Update `ProjectCard` to display relative time (already implemented)

### Task 3: Verify All Acceptance Criteria (AC: all)
- [x] Verify admin sees all company projects
- [x] Verify employee sees only accessible projects
- [x] Verify responsive grid layout works
- [x] Run existing tests to ensure no regressions

## Dev Notes

### Existing Infrastructure

**Backend (from Story 3-1):**
- `Api::V1::Company::ProjectsController#index` with Ransack
- `Project.for_user(user)` scope with admin/employee logic
- `ProjectSerializer` with `collaborators_count` and `last_activity_at` (returns nil)

**Frontend (from Story 3-1):**
- `ProjectsPage.tsx` - main page with grid
- `ProjectCard.tsx` - card component
- `useProjectsQuery` - RTK Query hook

### Search Implementation Options

**Option A: Client-side filtering (recommended for MVP)**
```typescript
const [search, setSearch] = useState('');
const filteredProjects = projects.filter(p =>
  p.name.toLowerCase().includes(search.toLowerCase())
);
```

**Option B: Server-side filtering with Ransack**
```typescript
useProjectsQuery({ q: { name_cont: search } })
```

For now, client-side is simpler since project count per user is typically small.

### Last Activity Calculation

```ruby
# app/serializers/project_serializer.rb
def last_activity_at
  object.terminal_sessions.order(started_at: :desc).limit(1).pick(:started_at)
end
```

Need to verify `terminal_sessions` association exists on Project model.

### References

- [Source: ai/epics.md#Story-3.2] - View Projects List requirements
- [Source: web/app/frontend/pages/projects/ui/ProjectsPage.tsx] - Existing projects page
- [Source: web/app/serializers/project_serializer.rb] - Project serializer

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

None

### Completion Notes List

- Added search TextField to ProjectsPage with client-side filtering by name and description
- Implemented `last_activity_at` in ProjectSerializer using terminal_sessions
- Added `has_many :terminal_sessions` association to Project model
- Added test for `last_activity_at` serialization
- All 149 tests pass, no regressions

### File List

**Modified:**
- web/app/models/project.rb (added terminal_sessions association)
- web/app/serializers/project_serializer.rb (implemented last_activity_at)
- web/app/frontend/pages/projects/ui/ProjectsPage.tsx (added search input and filtering)
- web/test/controllers/api/v1/company/projects_controller_test.rb (added last_activity_at test)
