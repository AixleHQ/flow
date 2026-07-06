# Workflow System

> Full details: [Workflow Architecture](../workflow-architecture.md)

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Agent** | LLM configuration (persona, system prompt). Not tied to workflow |
| **Workflow** | Process definition: steps, inputs, outputs. **Polymorphic scope** (Company or Project) — same pattern as Agent/Tool/Skill |
| **Step** | Single step within workflow with instructions |
| **SubStep** | Unit of work within a step |
| **WorkflowRun** | Specific workflow execution, always project-scoped (even for company workflows) |
| **StepRun** | Single step execution (= one terminal session) |
| **SubStepRun** | Tracked execution of one sub-step |
| **WorkflowRunAsset** | Intermediate file shared between steps |
| **Asset** | Project-level versioned file/document |

## Scope Decision (2026-02-22)

Workflow uses polymorphic `scope` (Company | Project) with `merged_for_project(project)`.
Company defines standard workflows available in all projects. Projects can create specific or override by name.
WorkflowRun always `belongs_to :project` — execution is project-scoped.

## Workspace Structure

```
/workspace/
├── input/              # READONLY — input artifacts
└── output/             # COLLECT — agent outputs
```

## Implementation Phases

| Phase | Scope |
|-------|-------|
| 0 | Secrets Management |
| 1 | Agents (CRUD, selection) |
| 2 | Tools (Docker execution) |
| 3 | MCP Servers |
| 4 | Unified Container Execution |
| 4+ | Session Context (per-CLI config) |
| 4++ | Agent Sessions Core |
| 5-6 | Workflows + Artifacts |
| 7 | Billing & Integrations |

## Dependency Graph

```
WORKFLOWS → SESSION CONTEXT → MCP SERVERS → TOOLS → AGENTS → SECRETS
```

---
