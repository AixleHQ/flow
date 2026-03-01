# Story 21.5: Task Comment Model

Status: review

## Story

As a user,
I want to add comments to tasks with tags and author attribution,
so that I can communicate with team members and AI agents through structured feedback.

## Acceptance Criteria

1. Migration creates `task_comments` table: `id` (bigint PK), `board_task_id` (references board_tasks, not null, FK), `body` (text, not null), `author_id` (references users, not null, FK), `author_type` (string, not null, default: "human"), `tags` (string array, default: []), `created_at` (timestamp, not null)
2. **No `updated_at` column** — comments are append-only (FR22)
3. `TaskComment` model with `belongs_to :board_task`, `belongs_to :author, class_name: "User"`
4. `enumerize :author_type, in: %i[human agent system], default: :human`
5. Comments API: `POST /board/tasks/:task_id/comments` (create only)
6. `GET /board/tasks/:task_id/comments` with filters: `tag`, `author_type`
7. No update or delete endpoints — comments are immutable (FR22)
8. `TaskCommentSerializer` with `id`, `body`, `author_id`, `author_name`, `author_type`, `tags`, `created_at`
9. `BoardTask` gains `has_many :task_comments, dependent: :destroy`
10. Update `BoardTaskSerializer#comments_count` to return actual count

## Tasks / Subtasks

- [ ] Task 1: Create migration (AC: #1, #2)
  - [ ] Generate migration `CreateTaskComments`
  - [ ] `board_task_id` with FK to board_tasks, not null
  - [ ] `body` (text, not null)
  - [ ] `author_id` with FK to users, not null
  - [ ] `author_type` (string, not null, default: "human")
  - [ ] `tags` (string array, default: [])
  - [ ] `created_at` only — no `updated_at`
  - [ ] Index on `board_task_id`
- [ ] Task 2: Create TaskComment model (AC: #3, #4)
  - [ ] `app/models/task_comment.rb`
  - [ ] `belongs_to :board_task`, `belongs_to :author, class_name: "User"`
  - [ ] `enumerize :author_type, in: %i[human agent system], default: :human`
  - [ ] Validates `body` presence
  - [ ] No `updated_at` → set `self.record_timestamps = false` and manage `created_at` manually, OR override `timestamp_attributes_for_create` to only return `created_at`
  - [ ] Ransack config
- [ ] Task 3: Add associations (AC: #9)
  - [ ] `BoardTask` gains `has_many :task_comments, dependent: :destroy`
- [ ] Task 4: Create TaskCommentSerializer (AC: #8)
  - [ ] `app/serializers/task_comment_serializer.rb`
  - [ ] Attributes: `id`, `body`, `author_id`, `author_name`, `author_type`, `tags`, `created_at`
  - [ ] `author_name` → `object.author.name`
- [ ] Task 5: Update BoardTaskSerializer (AC: #10)
  - [ ] `comments_count` → `object.task_comments.count`
- [ ] Task 6: Create Pundit policy (AC: #5, #7)
  - [ ] `app/policies/api/v1/company/projects/board/task/comments_policy.rb`
  - [ ] `index?` → `project_accessible?`
  - [ ] `create?` → `project_accessible?`
  - [ ] NO `update?`, `destroy?` — comments are immutable
- [ ] Task 7: Create controller (AC: #5, #6)
  - [ ] `app/controllers/api/v1/company/projects/board/task/comments_controller.rb`
  - [ ] `index`: list comments for task with optional `tag` and `author_type` filters
  - [ ] `create`: create comment with `author_id: current_user.id`, `author_type: :human`
  - [ ] Tag filter: `where("? = ANY(tags)", params[:tag])` when `params[:tag]` present
  - [ ] Author type filter: `where(author_type: params[:author_type])` when present
  - [ ] Strong params: `params.require(:task_comment).permit(:body, tags: [])`
- [ ] Task 8: Add routes (AC: #5)
  - [ ] Nest under tasks: `resources :comments, controller: "board/task/comments", only: [:index, :create]`
- [ ] Task 9: Factory and tests
  - [ ] FactoryBot factory for `task_comment`
  - [ ] Model test: validations, immutability (no update_at)
  - [ ] Controller test: create, index with filters, no update/delete endpoints

## Dev Notes

### Architecture Compliance

- Comments are **append-only** — no PATCH or DELETE endpoints (FR22). Immutability enforced by API surface.
- `tags` uses PostgreSQL array: `where("? = ANY(tags)", tag_param)` for efficient filtering.
- `author_type` is set by the system: `human` for web UI calls, `agent` for MCP tool calls (Epic 23), `system` for auto-generated.
- No `updated_at` column per FR22 — comments cannot be modified after creation.

### Handling No updated_at

Rails expects `updated_at` by default. Options:
- **Recommended:** Define the table without `updated_at`, and in the model:

```ruby
class TaskComment < ApplicationRecord
  self.record_timestamps = true

  # Only set created_at, skip updated_at
  class << self
    def timestamp_attributes_for_update
      []
    end
  end
end
```

OR simpler: just use `t.datetime :created_at, null: false` in migration without `t.timestamps`. Rails will auto-set `created_at` on create.

### Tag Filtering

```ruby
scope :with_tag, ->(tag) { where("? = ANY(tags)", tag) }
scope :by_author_type, ->(type) { where(author_type: type) }
```

### API Contract

```
GET    /api/v1/company/projects/:project_id/board/tasks/:task_id/comments         → index
POST   /api/v1/company/projects/:project_id/board/tasks/:task_id/comments         → create
```

Index supports query params: `tag`, `author_type`

### Controller Nesting

Controller at `board/task/comments_controller.rb` — nested under task (note singular `task` module for namespace, since the resource is `:tasks` plural in routes but the namespace path uses the controller path).

Routes:
```ruby
resources :tasks, controller: "board/tasks" do
  resources :comments, controller: "board/task/comments", only: [:index, :create]
end
```

### Project Structure Notes

- `app/models/task_comment.rb`
- `app/controllers/api/v1/company/projects/board/task/comments_controller.rb`
- `app/serializers/task_comment_serializer.rb`
- `app/policies/api/v1/company/projects/board/task/comments_policy.rb`
- `test/models/task_comment_test.rb`
- `test/controllers/api/v1/company/projects/board/task/comments_controller_test.rb`
- `test/factories/task_comments.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_task_comments.rb`

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.5]
- [Source: ai/prd/board-tasks.md#FR19, FR20, FR21, FR22, FR23]
- [Source: ai/project-context.md#Implementation Rules — enumerize, not ActiveRecord enums]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — clean implementation.

### Completion Notes List
- All ACs implemented: append-only comments, no `updated_at`, tag/author_type filters
- `timestamp_attributes_for_update` returns [] to skip updated_at
- No update/delete endpoints — verified by UrlGenerationError tests
- `BoardTaskSerializer#comments_count` wired to actual count
- 12 model tests + 12 controller tests = 24 tests

### File List
- `db/migrate/20260227100003_create_task_comments.rb`
- `app/models/task_comment.rb`
- `app/models/board_task.rb` (modified: added `has_many :task_comments`)
- `app/serializers/task_comment_serializer.rb`
- `app/serializers/board_task_serializer.rb` (modified: comments_count)
- `app/policies/api/v1/company/projects/board/task/comments_policy.rb`
- `app/controllers/api/v1/company/projects/board/task/comments_controller.rb`
- `config/routes.rb` (modified: added comments routes)
- `test/factories/task_comments.rb`
- `test/models/task_comment_test.rb`
- `test/controllers/api/v1/company/projects/board/task/comments_controller_test.rb`
