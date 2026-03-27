# Story 24.2: Board Activity Feed API & UI

**Epic:** 24 — Activity Feed & Filtered Views
**Status:** ready-for-dev
**Priority:** P1 (Post-MVP)
**Depends on:** Story 24.1

## User Story

**As a** user,
**I want** to view an activity feed showing what happened on the board,
**So that** I can track progress and understand what agents and teammates are doing.

## Acceptance Criteria

- [x] API: `GET /board/activities` — paginated (Pagy), newest first
- [x] API: `GET /tasks/:task_id/activities` — task-level feed, paginated
- [x] Filters via query params: `event_type`, `actor_type`, `since` (ISO timestamp)
- [x] `BoardActivitySerializer` with human-readable `description` field
  - Format: "Agent (managed by Artem) moved 'Login API' from Tech Design to Implementation"
  - Format: "Katya added comment with tag 'feedback' on 'Login API'"
- [x] Frontend: activity feed panel on board page (collapsible bottom panel or right sidebar)
- [x] Task detail sidebar: new "Activity" tab showing task-specific events
- [x] Feed updates via ActionCable: new `activity_created` events prepended to feed
- [x] Policy: `project_accessible?` for both endpoints
- [x] Controller and integration tests

## Tasks / Subtasks

### 1. Serializer
- `BoardActivitySerializer` with: `id`, `event_type`, `actor_id`, `actor_type`, `actor_name`, `board_task_id`, `task_title`, `description`, `metadata`, `created_at`
- `description` — virtual attribute, generated from `event_type` + `metadata` + associations
- `actor_name` — resolved: for agent type, format "Agent (managed by {user.name})"

### 2. Board-level activities controller
- `Board::ActivitiesController#index`
- Scoped to `current_board.board_activities`
- Filters: `params[:event_type]`, `params[:actor_type]`, `params[:since]`
- Paginated via `paginate(activities)` with Pagy
- Route: `GET /api/v1/company/projects/:project_id/board/activities`

### 3. Task-level activities controller
- `Board::Task::ActivitiesController#index`
- Scoped to `current_task.board_activities`
- Same filters as board-level
- Route: `GET /api/v1/company/projects/:project_id/board/tasks/:task_id/activities`

### 4. Routes
- Add inside `resource :board` block:
  ```ruby
  resources :activities, controller: "board/activities", only: [:index]
  ```
- Add inside tasks' nested block:
  ```ruby
  resources :activities, controller: "board/task/activities", only: [:index]
  ```

### 5. Policy
- `Board::ActivitiesPolicy` — `index? → project_accessible?`
- `Board::Task::ActivitiesPolicy` — `index? → project_accessible?`

### 6. Frontend: Board Activity Panel
- New component `BoardActivityPanel` in `features/board-management/ui/`
- Collapsible panel at bottom of board page
- Toggle button in board header: "Activity Feed"
- Fetches from `GET /board/activities` via RTK Query endpoint
- Infinite scroll or "Load more" pagination
- Each item: avatar, description text, relative timestamp
- Real-time: `useBoardChannel` handles `activity_created` event → prepend to feed

### 7. Frontend: Task Activity Tab
- New tab "Activity" in `TaskSidebar` (alongside Details, Comments, Assets)
- Fetches from `GET /tasks/:task_id/activities`
- Same item format as board-level feed
- Real-time prepend on `activity_created` for matching task_id

### 8. RTK Query endpoints
- `getBoard Activities: builder.query(...)` — paginated, with filter params
- `getTaskActivities: builder.query(...)` — paginated, with filter params

### 9. Tests
- Controller tests for both endpoints (pagination, filters, access control)
- Serializer test for `description` generation
- Frontend: verify activity panel renders and updates via channel

## Dev Notes

### Description Generation

```ruby
class BoardActivitySerializer < ApplicationSerializer
  attributes :id, :event_type, :actor_id, :actor_type, :actor_name,
             :board_task_id, :task_title, :description, :metadata, :created_at

  def actor_name
    user = object.actor
    case object.actor_type
    when "agent"
      "Agent (managed by #{user.name})"
    else
      user.name
    end
  end

  def task_title
    object.board_task&.title
  end

  def description
    case object.event_type
    when "task_moved"
      "#{actor_name} moved '#{task_title}' from #{object.metadata['from_column']} to #{object.metadata['to_column']}"
    when "task_created"
      "#{actor_name} created '#{object.metadata['title']}'"
    when "comment_added"
      tag_info = object.metadata['tag'] ? " with tag '#{object.metadata['tag']}'" : ""
      "#{actor_name} added comment#{tag_info} on '#{task_title}'"
    when "workflow_started"
      "Workflow '#{object.metadata['workflow_name']}' started on '#{task_title}'"
    when "workflow_completed"
      "Workflow '#{object.metadata['workflow_name']}' completed on '#{task_title}'"
    when "workflow_failed"
      "Workflow '#{object.metadata['workflow_name']}' failed on '#{task_title}'"
    when "asset_attached"
      "#{actor_name} attached '#{object.metadata['name']}' to '#{task_title}'"
    when "human_help_requested"
      "Agent requested help on '#{task_title}': #{object.metadata['question']&.truncate(80)}"
    else
      "#{actor_name} performed #{object.event_type.humanize.downcase} on '#{task_title}'"
    end
  end
end
```

### Pagination Pattern

Use existing Pagy-based `paginate(relation)` helper from `PaginationConcern`. Response format:

```json
{
  "meta": { "page": 1, "per_page": 20, "total_pages": 5, "total_count": 100 },
  "items": [{ "id": 1, "event_type": "task_moved", "description": "...", ... }]
}
```

Frontend uses `page` + `per_page` params. "Load more" button increments page.

### Filtering Pattern

```ruby
def index
  activities = current_board.board_activities.order(created_at: :desc)
  activities = activities.where(event_type: params[:event_type]) if params[:event_type].present?
  activities = activities.where(actor_type: params[:actor_type]) if params[:actor_type].present?
  activities = activities.where("created_at >= ?", Time.parse(params[:since])) if params[:since].present?
  respond_with paginate(activities), each_serializer: BoardActivitySerializer
end
```

### Real-time Integration

`useBoardChannel` already handles various event types. Add handler for `activity_created`:

```typescript
case 'activity_created':
  dispatch(
    boardApi.util.updateQueryData('getBoardActivities', projectId, (draft) => {
      draft.items.unshift(data as BoardActivity);
    }),
  );
  break;
```

### Frontend Architecture

- `BoardActivityPanel` — MUI `Collapse` panel at bottom of `BoardPanel`
- `ActivityItem` — single feed item component: icon (by event type) + description + relative time
- Toggle via Zustand store or local state in BoardPanel
- Task sidebar: add 4th tab "Activity" to existing tabs array

### Dependencies
- Story 24.1 (BoardActivity model + ActivityRecorder)
- Existing: Pagy pagination, BoardChannel, TaskSidebar tabs
