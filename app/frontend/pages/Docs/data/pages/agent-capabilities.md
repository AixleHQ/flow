# Wrappers, Skills & Connectors

Three ways to give agents more than their own reasoning. They are easy to
confuse, so start here:

| | It gives the agent | Use when |
| --- | --- | --- |
| **Wrappers** | An action *you* define — a script or API turned into a callable tool | You have an internal service with no ready-made integration |
| **Skills** | Know-how — packaged instructions loaded during a session | The same expertise keeps being retyped into prompts |
| **Connectors** | Tools from an external server, ready-made | The agent must act on a system someone else built |

## Wrappers

The **Wrappers** page lists the project's custom tools. Each row shows how it
runs — a container image you specify, or one of Flow's built-ins — and the list
filters by name.

Define a wrapper once, attach it to the steps that need it, and it becomes a
capability the agent can call during a run. Deleting one asks for confirmation
first, because a step that expects it will notice.

## Skills

The **Skills** page has two ways in:

- **Catalog** — browse what is published, install what fits. Each entry shows
  how many times it has been installed.
- **Write one by hand** — the authoring form from the page header, for
  know-how that is specific to your team: "how we write migrations", "our
  review checklist", "our commit conventions".

Installed skills are listed with their install counts. Attach a skill where it
should apply, and agents follow it when the work matches.

## Connectors

The **Connectors** page manages external tool servers. Add one from the
catalog, or by hand when you know the server you want. Servers you added
yourself can be edited; the list filters by name.

Credentials belong in [Secrets & Variables](/docs/secrets), not in the
connector's own fields or in a task description — that is what keeps them out
of prompts and logs.

> tip If you are unsure which of the three you need: it is a **connector** if
> someone else already runs it, a **wrapper** if you have to write it, and a
> **skill** if there is nothing to call at all — only knowledge to apply.
