# Epic 28: Context Optimization & Legacy Cleanup

> Token budget compression for large contexts and removal of orphaned/duplicated context assembly code.

**Phase:** 16 (Depends on: Epic 25, Epic 26)

**Design Document:** [Session Context Constructor — §9 Token Budget, §8.3 Migration Phase 6](../session-context-constructor.md)

**User Outcome:** Agents maintain instruction adherence even with large contexts (many tools, repos, long workflow histories). Codebase is cleaner with no dead code. Context assembly is maintainable and extensible for future builders.

**FRs Covered:** FR-SCC9

---

## Problem

As the number of context sections grows (tools, repos, skills, workflow history, board comments), the total context can exceed the optimal window for LLM instruction adherence (~6000 tokens). Without compression, low-priority sections dilute critical instructions.

Additionally, after Epic 25 and 26 are complete, legacy code remains: `WorkflowContextAssembler` (never used) and the old context-building methods that were extracted into builders. This dead code adds maintenance burden and confusion.

---

## Stories

### Story 28.1: Token Budget Compression

**As a** system,
**I want** the ContextRenderer to compress low-priority sections when total context exceeds the token budget,
**So that** critical instructions are never diluted by verbose reference material.

**Acceptance Criteria:**

**Given** a context with total estimated size > 6000 tokens
**When** ContextRenderer renders sections
**Then** compression is applied in order (each step checked before proceeding):
  1. `previous-steps` — truncate notes, drop data fields
  2. Board comments — limit to 3 most recent (from 5)
  3. Tool descriptions — drop parameter details, keep tool names and one-line descriptions only
  4. Skills — omit content, keep names only
  5. Repository section — drop purpose column
**And** sections with priority `:critical` are NEVER compressed (`critical-rules`, `current-step`, `output-rules`)
**And** the compressed output still contains all section tags (just shorter content)

**Given** a context with total estimated size ≤ 6000 tokens
**When** ContextRenderer renders sections
**Then** no compression is applied — full content preserved

**Technical notes:**
- Token estimation: `content.length / 4` (rough approximation, 1 token ≈ 4 chars for English)
- Compression is applied to the section content before final rendering
- Each compression step can define a `compress(content)` method, or the Renderer can have a `CompressionPipeline`
- Threshold (6000 tokens) should be a constant, easy to tune

---

### Story 28.2: Delete WorkflowContextAssembler

**As a** developer,
**I want** the orphaned `WorkflowContextAssembler` class removed,
**So that** there's no confusion about which code assembles workflow context.

**Acceptance Criteria:**

**Given** `WorkflowContextAssembler` exists in the codebase
**When** this story is complete
**Then** the class file is deleted
**And** any references to it (requires, specs) are removed
**And** no other code depends on it (verify with `rg WorkflowContextAssembler`)

**Technical notes:**
- This class was built but never wired into any execution path — safe to delete
- Verify with grep before deleting to catch any indirect references

---

### Story 28.3: Clean Up WorkflowStepStrategy Residual Methods

**As a** developer,
**I want** residual context-building methods in `WorkflowStepStrategy` cleaned up after workflow context was moved to the builder,
**So that** the strategy only handles container lifecycle concerns, not context assembly.

**Acceptance Criteria:**

**Given** `WorkflowStepStrategy` after Epic 26 Story 26.5 simplified AGENT_PROMPT
**When** this story is complete
**Then** any remaining helper methods that built workflow prompt content (repos descriptions, asset descriptions, MCP descriptions within the strategy) are removed
**And** the strategy's `build_env_vars` only sets `AGENT_PROMPT` to `step.instructions`
**And** all workflow execution tests pass

**Technical notes:**
- Review `WorkflowStepStrategy` for methods that overlap with what builders now produce
- The strategy should be thin: lifecycle hooks + env vars + image resolution, no content generation
- Run `make check` to verify nothing breaks

---

## Dependency Graph

```
Story 28.1 (Token budget compression) ← independent, can start after Epic 25

Story 28.2 (Delete WorkflowContextAssembler) ← after Epic 26 (workflow context moved)

Story 28.3 (Clean up WorkflowStepStrategy) ← after Epic 26 Story 26.5
```

---

## Implementation Notes

- Token budget compression is a quality-of-life optimization — not blocking for core functionality
- The compression threshold (6000 tokens) is conservative; can be tuned based on real-world context sizes
- Deletion stories (28.2, 28.3) are safe cleanup — verify with grep and tests before removing code
- After this epic, the context assembly path is clean: `SessionContextConstructor` → builders → `ContextRenderer` → context file
