# Story 27.2: Recent Comments in Board Context

Status: review

## Story

As a system,
I want the BoardContext builder to include recent task comments,
So that agents can see the latest discussion and any instructions from humans or previous agent runs.

## Acceptance Criteria

1. **Recent comments included** — Given a board task with 8 comments (3 from the last 24 hours), when BoardContext builder builds, then the board-context section includes a "Recent Comments" subsection with up to 5 most recent comments

2. **Comment details shown** — Given each comment in the "Recent Comments" subsection, when rendered, then each shows: author name (via `comment.author&.name`), body truncated to 200 chars

3. **No comments subsection when empty** — Given a board task with no comments, when BoardContext builder builds, then no "Recent Comments" subsection appears in the board-context section

## Tasks / Subtasks

- [x] Task 1: Add recent comments to BoardContext builder (AC: #1, #2, #3)
  - [x] Query recent comments: `board_task.task_comments.recent.limit(5)` (recent scope = order created_at desc, from ApplicationRecord)
  - [x] For each comment: show `comment.author&.name` and `comment.body.truncate(200)`
  - [x] Only include "Recent Comments" subsection when comments exist
  - [x] Eager load: `.includes(:author)` to prevent N+1
- [x] Task 2: Write tests (AC: #1-#3)
  - [x] Test recent comments appear in board-context content
  - [x] Test comment body truncated to 200 chars
  - [x] Test at most 5 comments shown
  - [x] Test no "Recent Comments" subsection when no comments

## Dev Notes

### Architecture Patterns

- **Extends BoardContext builder** from Story 27.1 — adds comments to the `build_board_context` method.
- **Eager loading:** Use `.includes(:author)` to prevent N+1 queries when accessing `comment.author.name`.

### Implementation Details

- Comments query: `board_task.task_comments.recent.limit(5)` — `recent` scope from ApplicationRecord: `order(created_at: :desc)`
- Author name: `comment.author&.name` — `TaskComment` belongs_to `:author, class_name: "User"`, User has `name`
- Body truncation: `comment.body.truncate(200)`
- `TaskComment` model: `body`, `author_id`, `author_type` (enumerize: human/agent/system), `tags` (array)
- Only show subsection if `task.task_comments.recent.limit(5).any?`

### Existing Code Context

- `TaskComment` model: belongs_to `:board_task`, belongs_to `:author` (User)
- `TaskComment` author_type: human, agent, system — can show type in comment for context
- `ApplicationRecord` has `scope :recent, -> { order(created_at: :desc) }`

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Factories:** Need `task_comment` factory with author association
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/board_context_test.rb`

### Project Structure Notes

- Modified file: `app/services/context_builders/board_context.rb`
- Test file: `test/services/context_builders/board_context_test.rb` (add tests)

### References

- [Source: ai/session-context-constructor.md#5.4 BoardContext Builder] — Comments section in design
- [Source: ai/epics/epic-27-board-context-in-sessions.md#Story 27.2] — Acceptance criteria
- [Source: app/models/task_comment.rb] — TaskComment model: body, author (User), author_type, tags

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — all tests passed on first run.

### Completion Notes List
- Extended `BoardContext#build_board_context` to query `task_comments.recent.includes(:author).limit(5)`
- Each comment shows author name, author_type, and body truncated to 200 chars
- "Recent Comments" subsection only appears when comments exist
- 5 new tests added (16 total), 50 assertions — all passing

### File List
- app/services/context_builders/board_context.rb (modified — added comments)
- test/services/context_builders/board_context_test.rb (modified — 5 new tests)
