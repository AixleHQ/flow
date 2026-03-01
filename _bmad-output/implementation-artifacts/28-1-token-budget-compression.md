# Story 28.1: Token Budget Compression

Status: review

## Story

As a system,
I want the ContextRenderer to compress low-priority sections when total context exceeds the token budget,
So that critical instructions are never diluted by verbose reference material.

## Acceptance Criteria

1. **Compression applied when over budget** — Given a context with total estimated size > 6000 tokens (~24000 chars), when ContextRenderer renders sections, then compression is applied in priority order:
   1. `previous-steps` — truncate notes, drop data fields
   2. Board comments — limit to 3 most recent (from 5)
   3. Tool descriptions — drop parameter details, keep tool names and one-line descriptions only
   4. Skills — omit content, keep names only
   5. Repository section — drop purpose column

2. **Critical sections never compressed** — Given sections with priority `:critical` (`critical-rules`, `current-step`, `output-rules`), when compression is applied, then these sections are NEVER modified

3. **All tags preserved** — Given compressed output, when inspected, then all section XML tags are still present (just shorter content)

4. **No compression under budget** — Given a context with total estimated size ≤ 6000 tokens, when ContextRenderer renders sections, then no compression is applied — full content preserved

## Tasks / Subtasks

- [x] Task 1: Add token estimation to ContextRenderer (AC: #4)
  - [x] Add `TOKEN_BUDGET = 6000` constant
  - [x] Implement `estimate_tokens(sections)` → `sections.sum { |s| s.content.length } / 4`
  - [x] Check budget before rendering: if under budget, render normally
- [x] Task 2: Implement compression pipeline (AC: #1, #2, #3)
  - [x] Create compression steps as ordered array of lambdas/objects
  - [x] Step 1: Compress `previous-steps` — truncate notes to 100 chars, remove data lines
  - [x] Step 2: Compress board comments — reduce limit indicator in content
  - [x] Step 3: Compress tool descriptions — strip parameter details
  - [x] Step 4: Compress skills section — keep names only
  - [x] Step 5: Compress repository section — drop purpose details
  - [x] Apply steps sequentially, re-check budget after each step
  - [x] NEVER compress sections with priority `:critical`
  - [x] Preserve all XML tags (only modify inner content)
- [x] Task 3: Write tests (AC: #1-#4)
  - [x] Test no compression when under budget
  - [x] Test compression applied when over budget
  - [x] Test critical sections never compressed
  - [x] Test all section tags preserved after compression
  - [x] Test progressive compression (stop when under budget)

## Dev Notes

### Architecture Patterns

- **ContextRenderer extension:** Compression logic added to `ContextRenderer.render` — checks token budget before final rendering.
- **Progressive compression:** Apply steps one at a time, re-estimate after each. Stop as soon as under budget.
- **Section identity by tag:** Compression steps identify sections by their `tag` field (e.g., `"previous-steps"`, `"custom-tools"`).
- **Immutability consideration:** ContextSection is frozen. Compression must create new ContextSection instances with modified content, not mutate existing ones.

### Implementation Details

- Token estimation: `content.length / 4` (rough: 1 token ≈ 4 chars for English text)
- Budget constant: `TOKEN_BUDGET = 6000` — easy to tune
- Compression modifies section content by creating new ContextSection instances (originals are frozen)
- Each compression step: `compress_step(sections) → sections` — returns modified array
- Critical sections identified by `section.priority == :critical`
- Section tags for targeting: `"previous-steps"`, `"board-context"`, `"custom-tools"`, `"available-resources"`, `"repositories"`

### Existing Code Context

- `ContextRenderer.render(sections)` — current implementation just sorts and renders, no compression
- `ContextSection` is frozen (immutable) — compression must create new instances
- Sections have `tag`, `priority`, `content`, `position_hint`, `builder_name` attributes
- Design doc §9 describes token budget approach

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_renderer_test.rb`

### Project Structure Notes

- Modified file: `app/services/context_renderer.rb`
- May add: `app/services/context_compressor.rb` (optional — could be inline in renderer)
- Test file: `test/services/context_renderer_test.rb` (add compression tests)

### References

- [Source: ai/session-context-constructor.md#9 Token Budget] — Design specification
- [Source: ai/epics/epic-28-context-optimization-cleanup.md#Story 28.1] — Acceptance criteria
- [Source: app/services/context_renderer.rb] — Current renderer (no compression)
- [Source: app/services/context_section.rb] — Frozen value object

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — all tests passed on first run.

### Completion Notes List
- Added `TOKEN_BUDGET = 6000` and `CHARS_PER_TOKEN = 4` constants to ContextRenderer
- Implemented progressive compression pipeline with 5 ordered steps: previous-steps, board-comments, tool-descriptions, skills, repositories
- Critical sections (`priority == :critical`) are never compressed — enforced via `replace_section` guard
- Compression creates new ContextSection instances (originals are frozen/immutable)
- Pipeline stops early when budget is satisfied
- All XML tags preserved — only inner content modified
- 6 new tests, 13 total, 46 assertions — all passing

### File List
- app/services/context_renderer.rb (modified — token budget + compression pipeline)
- test/services/context_renderer_test.rb (modified — 6 new compression tests)
