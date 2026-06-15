# Reference

Complete surface area, organized by what you reach for:

- **CLI** — every `make` target and what it does.
- **API** — REST endpoints, webhooks, the OpenAPI explorer.
- **Configuration** — every environment variable.

For conceptual explanations of *why* a thing exists, see the User Guide. Reference docs assume you already know what you're looking for.

## Domain model — one-page schema

```
Company
├── Users (roles: employee, admin, super_admin)
├── Agents, Tools, Skills, MCP Servers, Workflows  (company-scoped, inherited by all projects)
├── Repositories, ConfigItems
└── Projects
    ├── Board (1:1)
    │   ├── BoardColumns
    │   │   └── ColumnWorkflowBinding (0..1)
    │   ├── BoardTasks
    │   │   ├── TaskComments, TaskAssets, TaskWaits, ColumnTransitions
    │   │   └── WorkflowRuns
    │   ├── BoardActivities (immutable log)
    │   └── BoardViewPresets
    ├── Agents, Tools, Skills, MCP Servers, Workflows  (project-scoped)
    │   └── Workflows → Steps → SubSteps
    │                  └── WorkflowRuns → StepRuns → SubStepRuns
    │                                     └── WorkflowRunAssets
    ├── Assets, Repositories
    └── TerminalSessions
```

All major entities use **polymorphic scoping** — `scope_type` is
`Company` or `Project`, `scope_id` is the parent. Visibility resolution
returns *both* project-scoped *and* company-scoped entities for a given
project.
