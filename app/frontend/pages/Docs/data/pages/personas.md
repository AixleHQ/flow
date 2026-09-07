# Agent Personas

**Agents** in the sidebar is not a list of running agents — it is the personas
your team has defined. A persona says *who* the agent is: how it works, what
tone it takes, what rules it must follow.

## Why personas exist

Without them, every workflow step carries its own copy of "review this code
carefully, be strict about tests, comment in English". Personas let you say it
once: "our reviewer", "our implementer", "our release writer". Change the
persona, and every workflow step that references it changes with it.

## A persona is not a product

A persona is independent of the runtime. The same "our reviewer" can run on
Claude Code today and on Codex tomorrow — the step's Execution section decides
that, not the persona.

## Working with them

- **Create** a persona, give it a name and its instructions.
- **Search** the list by name.
- Each persona carries a **scope badge**: defined in this project, or shared
  from the company.
- Pick one in a workflow step's Resources section.

> info A persona describes behaviour, not permission. What an agent can reach —
> repositories, connectors, secrets — comes from the step's resources, and the
> credential it runs under comes from the person who connected it in
> [Profile](/docs/getting-started).
