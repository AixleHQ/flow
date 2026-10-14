# Effective workflows with less repeated context

Spec-driven development adds planning work. It saves overall work only when that
planning replaces repeated discovery or prevents implementation and review cycles.
Use BMAD's existing spec/build paths before adding another framework or another
planning pipeline to the same task.

## Choose the process by the change

| Change | Suggested workflow | What must survive the handoff |
| --- | --- | --- |
| Small, clear fix | One session: mini-spec, implement, test | Intended behavior, regression test, result |
| Medium feature | Canonical spec, build/tests, review | Accepted spec, constraints, diff, test evidence |
| Large or sensitive change | Add architecture and targeted independent review | Shared invariants, interfaces, migration/recovery conditions |

One step is a fresh agent session. Use sub-steps for a checklist inside a session;
split steps when a separate deliverable, approval, resource set, or independent
review justifies the extra session. BMAD build skills already include review:
an additional review step should have a distinct purpose, such as security or
acceptance verification, rather than repeating the same generic review.

For unattended BMAD implementation, use `bmad-build-auto` and follow the installed
version's headless constraints. `bmad-build` can wait for human input. Enabling
BMAD installs files; it does not put all their contents into the model's prompt.

## Keep one contract and narrow the inputs

Keep one canonical specification per change. Record the behavior, boundaries,
constraints, acceptance criteria and how to verify them. Put large supporting
research in referenced files. Update the contract when requirements change;
do not maintain competing copies in the card, instructions and review prompt.

Pass the spec's path with an `@` output/asset reference. Tell the build step which
contract to read and what to deliver, without pasting the spec into its starting
instructions. Tell the review step to compare the change and test evidence against
the same acceptance criteria. A short prompt is useful only if the agent still
reads the complete applicable contract and constraints.

Attach the tools, skills, MCP servers and repositories each step needs. Workflow
base resources reach every step; `inherit_all_project_resources` adds the project's
tools, skills and MCP servers to them. Leave that setting off when those resources
are not all needed. Model choice can reduce cost without reducing token counts;
judge it by accepted results, including corrections, rather than price alone.

Outputs of transitive dependencies remain available as files. Initial previous-step
summaries include only completed/skipped dependency steps, with the latest qualifying
attempt for each. Independent branches do not enter that summary. Make a dependency
explicit when a step must consume another step's evidence.

## Understand the context budget

`CONTEXT_TOKEN_BUDGET` defaults to `6000`. It is a **soft budget for Flow's generated
context file**, estimated as one token per four characters, rounded up. It includes
the rendered XML wrappers and separators. It excludes the starting prompt, tool
schemas, repository instruction files, skills loaded by the runtime, file reads,
tool results and subsequent conversation. It is not a provider tokenizer or a cap
on the entire session.

When that file exceeds the budget, the renderer shortens the previous-steps
section in two ways: every sub-step `→ data:` line is **dropped**, whatever its
size, and any other `→` note longer than 100 characters is cut to 100. No data line
is kept selectively; a data line is kept only while the file is within budget.
Critical instructions, ordinary step notes, resource paths and specification files
are not touched. If the file still exceeds the budget, the renderer retains it and
records the excess; lowering the setting cannot force a large contract into a small
prompt.

The session's existing `context_metadata` includes a `rendering` object:

| Field | Meaning |
| --- | --- |
| `original_rendered_content_length` | Characters in the uncompressed context, including wrappers |
| `rendered_content_length` | Characters in the exact generated context file |
| `estimated_tokens_before` | Estimated tokens before compression |
| `estimated_tokens_after` | Estimated tokens in the generated file |
| `token_budget` | Configured soft budget |
| `over_budget` | Whether the final estimate exceeds that budget |
| `compressed_tags` | Sections whose content actually changed during compression |

Existing section lengths and `total_content_length` continue to describe the
original builder content. The new rendering metrics describe the file after
compression. Metadata contains counts and section tags, not a copy of prompt text.

## Measure savings without losing effectiveness

Compare similar changes using the same runtime/model and comparable complexity.
Tag baseline and spec-first cohorts separately. Include planning, all build/review
sessions and retries, including workflows restarted as new runs for the same task.

Track tokens, cost and elapsed time **per accepted task**, plus acceptance failures,
requested corrections and defects found after delivery. Keep input, output, cache
reads and cache writes separate: fewer total tokens and a lower bill are different
outcomes. Kiro can report credit-based cost without token counts; zero reported
tokens there does not mean free execution. Missing usage is not zero usage.

Use the context metrics to explain initial-context reductions and the existing
session/workflow usage analytics to evaluate total cost. Start with a small cohort,
then expand only if acceptance quality holds. No production savings percentage is
claimed by the context changes themselves.
