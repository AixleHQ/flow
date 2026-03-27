# Story 25.1: ContextSection Value Object & ContextRenderer

Status: done

## Story

As a system,
I want a frozen ContextSection value object and a ContextRenderer that renders sections as XML-tagged markdown,
So that all context output has consistent structure with priority-based ordering and each section is self-describing.

## Acceptance Criteria

1. **ContextSection creation with valid attributes** — Given a ContextSection created with `tag: "test"`, `priority: :critical`, `content: "hello"`, `position_hint: :top`, `builder_name: "critical_rules"`, when the section is inspected, then `section.tag` returns `"test"`, `section.critical?` returns `true`, and `section.to_h` returns `{ tag: "test", priority: :critical, position_hint: :top, builder_name: "critical_rules", content_length: 5 }`

2. **Invalid priority raises ArgumentError** — Given a ContextSection created with `priority: :unknown`, when initialization runs, then `ArgumentError` is raised with message containing "unknown priority: unknown"

3. **Invalid position_hint raises ArgumentError** — Given a ContextSection created with `position_hint: :nowhere`, when initialization runs, then `ArgumentError` is raised

4. **Blank tag raises ArgumentError** — Given a ContextSection created with `tag: ""`, when initialization runs, then `ArgumentError` is raised with message containing "tag required"

5. **Blank content raises ArgumentError** — Given a ContextSection created with `tag: "test"`, `content: ""`, when initialization runs, then `ArgumentError` is raised with message containing "content required"

6. **ContextSection is frozen after creation** — Given a valid ContextSection, when attempting to modify any attribute, then the object raises `FrozenError`

7. **ContextRenderer sorts by position then priority** — Given an array of ContextSection structs with mixed priorities and positions, when `ContextRenderer.render(sections)` is called, then sections are sorted first by position_hint (`:top` → `:middle` → `:bottom`), then by priority (`:critical` → `:important` → `:info`)

8. **ContextRenderer produces XML-tagged output** — Given sections rendered by `ContextRenderer.render(sections)`, then output contains XML open/close tags for each section (e.g. `<critical-rules priority="critical">...</critical-rules>`), every open tag has a matching close tag, and output is a single string with sections separated by double newlines

9. **ContextRenderer handles empty array** — Given an empty array passed to `ContextRenderer.render([])`, then it returns an empty string

## Tasks / Subtasks

- [x] Task 1: Create ContextSection value object (AC: #1, #2, #3, #4, #5, #6)
  - [x] Create `app/services/context_section.rb` with frozen_string_literal
  - [x] Define PRIORITIES = `%i[critical important info].freeze`
  - [x] Define POSITIONS = `%i[top middle bottom].freeze`
  - [x] Implement `initialize` with validation for tag (not blank), priority (in PRIORITIES), content (not blank), position_hint (in POSITIONS, default :middle), builder_name (optional)
  - [x] Freeze all string attributes in initialize (`@tag = tag.to_s.freeze`, `@content = content.freeze`, `@builder_name = builder_name&.to_s&.freeze`)
  - [x] Implement `#critical?` → `priority == :critical`
  - [x] Implement `#to_h` → `{ tag:, priority:, position_hint:, builder_name:, content_length: content.length }`
  - [x] Call `freeze` at end of `initialize`
- [x] Task 2: Create ContextRenderer (AC: #7, #8, #9)
  - [x] Create `app/services/context_renderer.rb` with frozen_string_literal
  - [x] Define `PRIORITY_ORDER = { critical: 0, important: 1, info: 2 }.freeze`
  - [x] Define `POSITION_ORDER = { top: 0, middle: 1, bottom: 2 }.freeze`
  - [x] Implement `self.render(sections)` — sort by `[POSITION_ORDER[s.position_hint], PRIORITY_ORDER[s.priority]]`, map each to `render_section(s)`, join with `"\n\n"`
  - [x] Implement `self.render_section(section)` — produce `<tag priority="priority">\n\ncontent\n\n</tag>` format
  - [x] Return empty string for empty array
- [x] Task 3: Write tests (AC: #1-#9)
  - [x] Create `test/services/context_section_test.rb`
  - [x] Test valid creation and attribute accessors
  - [x] Test `critical?` for critical and non-critical priorities
  - [x] Test `to_h` structure and content_length calculation
  - [x] Test ArgumentError for invalid priority, invalid position, blank tag, blank content
  - [x] Test frozen state (modifications raise FrozenError)
  - [x] Create `test/services/context_renderer_test.rb`
  - [x] Test sorting: position_hint has higher precedence than priority
  - [x] Test XML tag format: `<tag priority="...">content</tag>`
  - [x] Test matching open/close tags
  - [x] Test empty array returns empty string
  - [x] Test multiple sections joined by double newlines

## Dev Notes

### Architecture Patterns

- **Value Objects:** ContextSection is a frozen value object — NOT a bare Struct or OpenStruct. Use explicit `attr_reader` with validation in `initialize`. This matches the project's preference for explicit, validated domain objects.
- **No ActiveRecord:** These are plain Ruby service objects in `app/services/`. No model, no database.
- **Frozen String Literal:** Always include `# frozen_string_literal: true` at the top.

### Implementation Details

- ContextSection priority order: `{ critical: 0, important: 1, info: 2 }` — lower number = higher priority
- ContextSection position order: `{ top: 0, middle: 1, bottom: 2 }` — lower number = earlier in output
- Sorting is stable: position_hint is primary sort key, priority is secondary
- XML format uses kebab-case tags matching the tag attribute value (e.g., `<critical-rules>`, `<agent-role>`)
- The `priority` attribute is embedded in the XML open tag for transparency: `<tag priority="critical">`
- `builder_name` is NOT rendered in XML — it's metadata for traceability only (used by ContextResult in Story 25.5)
- Content is rendered stripped (`.strip`) inside the XML tags to avoid leading/trailing whitespace

### Existing Code Context

The `SessionContextService` (see `app/services/session_context_service.rb`) currently builds context as plain markdown. This story creates the value objects that will eventually replace that approach. The renderer output format is:

```xml
<section-tag priority="critical">

Section content here (markdown)

</section-tag>
```

### Testing Standards

- **Framework:** Minitest (NOT RSpec)
- **Mocks:** mocha gem
- **Factories:** factory_bot_rails (but not needed here — pure Ruby objects)
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_section_test.rb test/services/context_renderer_test.rb`

### Project Structure Notes

- New files: `app/services/context_section.rb`, `app/services/context_renderer.rb`
- Test files: `test/services/context_section_test.rb`, `test/services/context_renderer_test.rb`
- These are service-layer objects, NOT models — no migration needed
- Future builders (Stories 25.2-25.4) will live in `app/services/context_builders/`

### References

- [Source: ai/session-context-constructor.md#4.2 Value Objects] — ContextSection design
- [Source: ai/session-context-constructor.md#6 Renderer] — ContextRenderer design
- [Source: ai/epics/epic-25-unified-context-constructor.md#Story 25.1] — Acceptance criteria
- [Source: ai/project-context.md#Implementation Rules] — Ruby coding standards

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- All tasks completed. Implementation follows epic design. 59 total tests across all Epic 25 stories, 212 assertions, 0 failures.

### File List

- `app/services/context_section.rb`
- `app/services/context_renderer.rb`
- `test/services/context_section_test.rb`
- `test/services/context_renderer_test.rb`
