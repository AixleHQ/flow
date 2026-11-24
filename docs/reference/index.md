# Reference

Complete surface area, organized by what you reach for:

- **[CLI](cli.md)** — every `make` target and what it does.
- **[API](api.md)** — REST endpoints, webhooks, the OpenAPI explorer.
- **[Configuration](configuration.md)** — every environment variable.

For conceptual explanations of *why* a thing exists, see the
[User Guide](../user-guide/). Reference docs assume you already know
*what* you're looking for.

## Domain model — one-page schema

```
Company
├── Memberships → Users (roles: admin, employee, viewer; a user can belong to several companies)
├── Assets, Folders  (company-wide: every project of the company sees them)
└── Projects
    ├── Board (1:1)
    │   ├── BoardColumns
    │   │   └── ColumnWorkflowBinding (0..1)
    │   ├── BoardTasks
    │   │   ├── TaskComments, TaskAssets, Gates, ColumnTransitions
    │   │   └── WorkflowRuns
    │   ├── BoardActivities (immutable log)
    │   └── BoardViewPresets
    ├── Agents, Tools, Skills, MCP Servers, Workflows  (project-scoped)
    │   └── Workflows → Steps → SubSteps
    │                  └── WorkflowRuns → StepRuns → SubStepRuns
    │                                     └── WorkflowRunAssets
    ├── ProjectTeams → members (a BoardTask's assignee or a trigger's Runs as; each run goes to one member)
    ├── Assets, Folders, Repositories, ConfigItems
    └── TerminalSessions
```

Agents, tools, skills, MCP servers, repositories, config items and workflows
belong to one project: `scope_type` is `Project` and `scope_id` is the
project, and no other project sees them. Only assets and folders can also be
company-wide (`scope_type` `Company`), and a project sees its own and its
company's. Platform tools and built-in MCP servers have no scope at all; the
Aixle Builder's own workflows are `System`-scoped and belong to no project.
