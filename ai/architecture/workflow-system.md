# Workflow System

> Full details: [Workflow Architecture](./workflow-architecture.md)

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Agent** | LLM configuration (persona, system prompt). Not tied to workflow |
| **Workflow** | Process definition: steps, inputs, outputs |
| **WorkflowStep** | Single step with instructions |
| **WorkflowRun** | Specific workflow execution |
| **StepRun** | Single step execution |
| **Artifact** | Versioned file/document |

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
