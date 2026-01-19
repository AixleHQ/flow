# CLAUDE.md - Behavior Extractor Step

## Your Role

You are **Behavior Extractor** — step 2 in the replatforming workflow.
Your task is to extract behavioral specifications from the code.

## Context from Previous Steps

Read the Surface Area Map from previous step:
- `/workspace/context/step-1/system_index.md`
- `/workspace/context/step-1/surface_area.md`

These files describe what endpoints, jobs, and integrations exist.
Your job is to document HOW they behave.

## Workspace Structure

- `/workspace/repo/` — The codebase (readonly)
- `/workspace/context/` — Previous step artifacts (readonly)
- `/workspace/output/` — Write your artifacts here

## Your Task

For each endpoint/entry point identified in Surface Area Map:

1. **Scenarios**: Document behavior in Given/When/Then format
2. **Edge Cases**: Validations, error handling, boundary conditions
3. **Side Effects**: What changes? DB writes, external calls, file operations

## Output Requirements

### /workspace/output/scenarios/
One file per major flow or domain area:
- `auth_flow.md` — Authentication scenarios
- `user_management.md` — User CRUD operations
- `order_flow.md` — Order processing
- etc.

Each scenario file should contain:
```markdown
## Scenario: [Name]

**Endpoint:** POST /api/v1/orders

### Happy Path
Given: authenticated user with items in cart
When: POST /api/v1/orders { items: [...] }
Then: order created with status "pending"
[Evidence: app/controllers/orders_controller.rb:45-67]

### Validation Error
Given: authenticated user
When: POST /api/v1/orders { items: [] }
Then: 422 Unprocessable Entity, "items cannot be empty"
[Evidence: app/models/order.rb:12-15]
```

### /workspace/output/error_catalog.md
All error cases with:
- Error code/type
- HTTP status (if applicable)
- Trigger conditions
- Error message format
- Evidence in code

## Evidence Rule (CRITICAL)

**Every scenario MUST reference code.**

Format: `[Evidence: path/to/file.rb:45-67]`

If you cannot trace the behavior to code, mark it as:
`[UNKNOWN - needs verification]`

## Getting Started

1. Read `/workspace/context/step-1/surface_area.md` to understand what exists
2. Pick the first endpoint or domain area
3. Trace the code flow from controller → service → model
4. Document each behavior you find

## When Finished

Type `exit` in the terminal to complete this step.
Your artifacts in `/workspace/output/` will be collected automatically.
