# Templates

Ready-made setups you can install instead of building from scratch: a single
agent, skill or connector, a board layout, a workflow, or a whole project with
its board, agents and workflows. Every template is reviewed by the Flow maintainers before
it appears in the catalog.

## Browsing

Open **Templates** in the sidebar, or go to `/templates` on your installation.
The catalog is readable without signing in, so you can share a link to a
template with someone who has no account yet.

Every template belongs to a **publisher** (its namespace), shown on the card —
with a check mark for publishers the Flow maintainers have verified. Filter the
catalog by publisher to see one vendor's templates. Two publishers can each
have a template with the same name; a template's full name is
`publisher/template`, as in `aixle/code-reviewer-agent`.

Each template page shows what it creates, what it needs from you, and what it
does **not** bring along: cards, comments, runs, secret values, integrations and
repositories never travel in a template.

## Installing

Press **Install** on the template page (you are asked to sign in first if you
are not). Then:

- **Where it goes.** A whole-project template always installs as a new project
  that you own. Any other kind — an agent, a skill, a connector, a board, a
  workflow — can go into a project you already have, or into a new one.
- **Settings.** A template can ask for a few values, such as a branch name or a
  language. Secrets it needs can be pasted here or added later.
- **What happens.** A table lists every resource and whether it is created, an
  existing one is used, or it conflicts. A conflict means the project already
  has something with the same name but different content: choose **Install as
  copy** (it gets a `(2)` or `_2` suffix) or **Use existing**.

Installing the same template twice with nothing changed reuses what is already
there instead of duplicating it. Adding columns to an existing board needs the
project owner; for anyone else the board part is skipped and noted.

## After installing: the setup checklist

The install ends on a checklist of what is left before the template runs on its
own:

- **Secrets** — paste the value; it is attached to every step that needs it.
- **Integrations** — connect GitHub, Slack or another provider; the item
  resolves by itself once it is connected.
- **Repositories** — pick one of the project's repositories to attach.
- **Sign-ins** — MCP servers that use OAuth need one sign-in from the project's
  MCP servers page.
- **Triggers** — every trigger is installed **inactive**, so nothing fires
  before the setup is done. Press **Activate** when you are ready. A trigger that
  runs unattended (schedule, Slack, webhook) still needs auto-run enabled on
  every step, and the checklist tells you which steps are missing it.

You can come back to the checklist at any time; items completed elsewhere are
ticked off the next time you open it.

## Publishing your own

Templates are published as pull requests to the public
[AixleHQ/flow-templates](https://github.com/AixleHQ/flow-templates) repository,
under a namespace you own. A new namespace is registered in the same pull
request, in the repository's `namespaces.yaml`; the maintainers approve it, and
from then on only its owners can change its templates.
The easiest way is to let your own agent do it: connect it to Flow's
[personal MCP server](/docs/mcp) and run the `publish_template` prompt on a
project that works. It exports the project, helps you turn project-specific
values into install settings, and opens the pull request. Flow never stores
your template or holds access to the repository.

Anything that cannot be carried safely stops the export with a reason — for
example a literal value in an MCP header, which has to become a
[secret](/docs/secrets) first.

## For operators

- Every installation mirrors the same public repository and shows only what it
  has mirrored; installs never fetch anything live.
- The mirror syncs every hour. **Admin → Catalog syncs → Sync template catalog**
  runs it immediately.
- A template the maintainers withdraw disappears from the catalog and can no
  longer be installed. Projects that already installed it are not changed.
