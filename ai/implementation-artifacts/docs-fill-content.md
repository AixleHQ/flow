# Story: Fill In-App Documentation Content

**Story ID:** docs-fill-content  
**Status:** review  
**Created:** 2026-06-15  
**Source:** GitHub Issue [#167](https://github.com/palad-ai/palad-app/issues/167) + PR [#173 changes](https://github.com/palad-ai/palad-app/pull/173/changes)

---

## User Story

As a **new user or contributor** landing on `/docs`,  
I want to **read accurate, complete documentation for every page** instead of "Coming soon" stubs,  
so that I can **understand the product, set it up, and use it without external help**.

---

## Context & Background

### What exists today (the gap)

PR #173 (`feature/167-open-source-docs`, not yet merged to `develop`) delivered a full GitHub-flavored documentation set under `docs/` (quickstart, user-guide/*, reference/*). That content was written against the real codebase and validated against the code.

In parallel, commit `ad8670b7` (`feat: implement public documentation portal at /docs`) shipped a live in-app docs portal at `/docs` (merged to `develop`). The portal has:

- A three-column layout (sidebar nav, content area, TOC)
- MDX-like content pipeline (`DocsMdxContent`, callout blocks, syntax-highlighted code)
- A search modal (⌘K)
- Navigation structure in `navStructure.ts` with **16 pages** defined

**But only 3 of those 16 pages have real content** (loaded as `.md?raw` imports in `index.ts`):
- `what-is-aixle` — placeholder / demo content (mentions `aixle.config.ts` which does not exist in the product)
- `quick-start` — placeholder content (references a non-existent `aixle` CLI)
- `agents` — placeholder content (references config file-based agent definitions that don't match the real product)

The remaining 13 pages all render `STUB_CONTENT` = _"This page is under development."_

### What PR #173 contains (the source material)

The branch `origin/feature/167-open-source-docs` contains validated, production-ready markdown for **all tiers**:

| PR file | Maps to in-app page(s) |
|---|---|
| `docs/quickstart.md` | `quick-start` |
| `docs/user-guide/board.md` | (no current page — needs adding as `board`) |
| `docs/user-guide/workflows.md` | (no current page — needs adding as `workflows`) |
| `docs/user-guide/agents.md` | `agents` |
| `docs/user-guide/runtimes.md` | (no current page — needs adding as `runtimes`) |
| `docs/user-guide/tools.md` | (no current page — needs adding as `tools`) |
| `docs/user-guide/mcp.md` | (no current page — needs adding as `mcp`) |
| `docs/user-guide/integrations.md` | `integrations` |
| `docs/user-guide/configuration.md` | `configuration` (Getting Started child) |
| `docs/reference/cli.md` | `cli-ref` |
| `docs/reference/api.md` | `api-guide` |
| `docs/reference/configuration.md` | `config-schema` |

Pages in the current nav that have **no clear match in PR #173**:
- `install-guide` — PR quickstart covers Docker setup; can reuse/adapt
- `self-hosting` — PR quickstart covers self-hosting; can reuse/adapt
- `cli` — "CLI setup" (Getting Started) — distinct from `cli-ref` reference; stub OK for now
- `tasks-overview` / `tasks` — tasks/card concepts; `board.md` covers this partially
- `permissions` — not covered in PR #173; stub OK for now
- `deploy` — not covered in PR #173; stub OK for now
- `advanced` — not covered in PR #173; stub OK for now

---

## Hierarchy of Work

```
TIER 1 — Direct port from PR #173 (highest priority, validated content)
  ├── quick-start           ← replace placeholder with docs/quickstart.md content
  ├── agents                ← replace placeholder with docs/user-guide/agents.md content
  ├── integrations          ← fill stub with docs/user-guide/integrations.md content
  ├── configuration         ← fill stub with docs/user-guide/configuration.md content
  ├── cli-ref               ← fill stub with docs/reference/cli.md content
  ├── api-guide             ← fill stub with docs/reference/api.md content
  └── config-schema         ← fill stub with docs/reference/configuration.md content

TIER 2 — New pages: add md files + register in navStructure + index.ts
  ├── board                 ← docs/user-guide/board.md
  ├── workflows             ← docs/user-guide/workflows.md
  ├── runtimes              ← docs/user-guide/runtimes.md
  ├── tools                 ← docs/user-guide/tools.md
  └── mcp                   ← docs/user-guide/mcp.md

TIER 3 — Rewrite existing placeholder pages
  ├── what-is-aixle         ← rewrite: current content is wrong (CLI-based product description)
  └── install-guide         ← rewrite using PR quickstart's Docker prerequisites section

Pages without content yet (self-hosting, cli, tasks-overview/tasks, permissions, deploy, advanced)
are NOT added to the nav until their content is ready. New pages are added as they are written.
```

---

## Acceptance Criteria

```gherkin
Given I open /docs in a browser
When I navigate to "Quick start"
Then I see Docker-based setup instructions (not an npm CLI reference)
And the "3-command quickstart" matches: git clone, cp .env.example, make setup

Given I navigate to "Agents"
Then I see real product concepts: persona, runtime, container layout (/workspace/outputs/, /workspace/assets/)
And no mention of "aixle.config.ts" or fake tool names like "read_file / write_file"

Given I navigate to any TIER 1, TIER 2, or TIER 3 page
Then I do NOT see "This page is under development."

Given I open /docs/self-hosting (or any page not yet created)
Then I see a 404 / "Page not found" message (the nav does not link to pages without content)

Given I use the search modal (⌘K)
Then searching "board" finds the Board page
And searching "workflow" finds the Workflows page
And searching "runtime" finds the Runtimes page

Given I navigate to "What is Aixle"
Then the page correctly describes Aixle Flow as a Kanban + AI workflow product
And does NOT describe it as a CLI-only tool
```

---

## Technical Implementation Guide

### File locations

All documentation markdown lives at:
```
app/frontend/pages/Docs/data/pages/
├── index.ts              ← registers pages, maps slug → md import + metadata
├── what-is-aixle.md
├── quick-start.md
├── agents.md
└── (new files to add)
```

Navigation is declared in:
```
app/frontend/pages/Docs/data/navStructure.ts   ← NAV_STRUCTURE constant
```

Search index is in:
```
app/frontend/pages/Docs/data/searchIndex.ts    ← SEARCH_INDEX array
```

### Step-by-step implementation

#### Step 1 — Get PR #173 content

The branch `feature/167-open-source-docs` is available at `origin/feature/167-open-source-docs`. Fetch and read the source files:

```bash
git fetch origin feature/167-open-source-docs
git show origin/feature/167-open-source-docs:docs/quickstart.md
git show origin/feature/167-open-source-docs:docs/user-guide/agents.md
# ... etc
```

#### Step 2 — Replace existing placeholder .md files

For each TIER 1 page that already exists as a `.md` file:
1. Read the corresponding file from the PR branch (see mapping table above)
2. Adapt it for in-app display — the PR docs are GitHub-flavored markdown with relative links like `[Runtimes](runtimes.md)`. For in-app use, links between pages don't render as actual navigation, so either:
   - Convert relative links to slug references, OR
   - Remove or plain-text them
3. Overwrite the existing `.md` file in `app/frontend/pages/Docs/data/pages/`

The callout syntax in the existing pages (`> **info** **Title.** Body`) is already handled by `DocsMdxContent` — **keep this format** for callouts.

#### Step 3 — Add new .md files (TIER 2)

For each new page (board, workflows, runtimes, tools, mcp):
1. Create `app/frontend/pages/Docs/data/pages/{slug}.md` with the content from the PR branch
2. In `index.ts`, add the import and register the page in `DOC_PAGES`
3. In `navStructure.ts`, add the page to the appropriate section in `NAV_STRUCTURE`
4. In `searchIndex.ts`, add an entry to `SEARCH_INDEX`

#### Step 4 — Rewrite what-is-aixle.md

Current content is wrong. It describes Aixle as a CLI-driven automation platform (`aixle.config.ts`, `defineConfig`). The real product is a Kanban board where column bindings trigger AI agent workflow runs in containers.

Write a new `what-is-aixle.md` based on the mental model from `docs/user-guide/index.md` (from the PR branch):

> A Company owns shared resources. Inside it, Projects each have one Board. A Board has ordered Columns; each column can be bound to a Workflow. Drop a card into the column and the workflow starts. A Workflow is a DAG of Steps; each Step is one Agent session running in an isolated container.

The page uses the `DocsHeroBlock` and `DocsConceptCards` components injected via `DocsPage.tsx` (at the `## How it works` heading split point). Preserve that heading.

#### Step 5 — Wire nav for new pages

`navStructure.ts` currently has pages that don't have real content yet (self-hosting, cli, tasks-overview, tasks, permissions, deploy, advanced). **Remove all nav items that have no content.** Pages are added to the nav only when their markdown file is ready.

After this story the nav should look like:

```typescript
export const NAV_STRUCTURE: NavSection[] = [
  {
    label: 'Getting started',
    items: [
      { slug: 'what-is-aixle', label: 'What is Aixle' },
      { slug: 'quick-start', label: 'Quick start' },
      { slug: 'install-guide', label: 'Installation guide' },
      { slug: 'configuration', label: 'Configuration' },
    ],
  },
  {
    label: 'Core concepts',
    items: [
      { slug: 'agents', label: 'Agents' },
      { slug: 'runtimes', label: 'Runtimes' },
      { slug: 'tools', label: 'Tools' },
      { slug: 'mcp', label: 'MCP servers' },
      { slug: 'board', label: 'Board' },
      { slug: 'workflows', label: 'Workflows' },
      { slug: 'integrations', label: 'Integrations' },
    ],
  },
  {
    label: 'Reference',
    items: [
      { slug: 'cli-ref', label: 'CLI reference' },
      { slug: 'api-guide', label: 'API' },
      { slug: 'config-schema', label: 'Configuration reference' },
    ],
  },
];
```

The nested `children` pattern (install-guide with self-hosting/cli children, tasks-overview with tasks/permissions children, advanced with cli-ref/config-schema children) is removed — no stubs in the nav.

#### Step 6 — Update searchIndex.ts

Add entries for: board, workflows, runtimes, tools, mcp.
Update existing entries for agents and integrations to reflect real product descriptions (not placeholder descriptions).
Remove entries for pages being removed from the nav (self-hosting, cli, tasks, permissions, deploy, advanced, config-schema → rename to configuration-reference).

---

## Critical Constraints

### DO NOT change the rendering pipeline
`DocsMdxContent.tsx`, `DocsLayout.tsx`, `DocsPage.tsx`, `navStructure.ts` types — these are working and tested. Content changes only.

### DO NOT invent product facts
All content must come from either:
1. The PR #173 branch files (validated against the codebase), OR
2. Things observable in the actual codebase

The existing placeholder pages in the app contain **fabricated product details** (e.g. `aixle run "..."` CLI, `defineConfig` pattern, `claude-opus-4-5` model name). Do not carry these over.

### Callout format
The `DocsMdxContent` component parses callouts from markdown as:
```markdown
> **info** **Title.** Body text
> **warning** **Title.** Body text
> **tip** **Title.** Body text
> **danger** **Title.** Body text
```
Use this syntax for all callout blocks. Do not use GitHub-style `> [!NOTE]` syntax.

### Relative links
The PR docs use relative markdown links (`[Board](board.md)`). These do not resolve in the in-app portal. Either:
- Remove them, or
- Replace with plain text references like "see the Board page"

---

## Source Content Access

All source content is on the remote branch `origin/feature/167-open-source-docs`.

Relevant files to fetch:

```bash
git fetch origin feature/167-open-source-docs

# TIER 1 replacements
git show origin/feature/167-open-source-docs:docs/quickstart.md
git show origin/feature/167-open-source-docs:docs/user-guide/agents.md
git show origin/feature/167-open-source-docs:docs/user-guide/integrations.md
git show origin/feature/167-open-source-docs:docs/user-guide/configuration.md
git show origin/feature/167-open-source-docs:docs/reference/cli.md
git show origin/feature/167-open-source-docs:docs/reference/api.md
git show origin/feature/167-open-source-docs:docs/reference/configuration.md

# TIER 2 new pages
git show origin/feature/167-open-source-docs:docs/user-guide/board.md
git show origin/feature/167-open-source-docs:docs/user-guide/workflows.md
git show origin/feature/167-open-source-docs:docs/user-guide/runtimes.md
git show origin/feature/167-open-source-docs:docs/user-guide/tools.md
git show origin/feature/167-open-source-docs:docs/user-guide/mcp.md

# Mental model reference
git show origin/feature/167-open-source-docs:docs/user-guide/index.md
```

---

## Files to Create / Modify

### New files
```
app/frontend/pages/Docs/data/pages/board.md
app/frontend/pages/Docs/data/pages/workflows.md
app/frontend/pages/Docs/data/pages/runtimes.md
app/frontend/pages/Docs/data/pages/tools.md
app/frontend/pages/Docs/data/pages/mcp.md
```

### Modified files
```
app/frontend/pages/Docs/data/pages/what-is-aixle.md     ← full rewrite
app/frontend/pages/Docs/data/pages/quick-start.md       ← replace placeholder
app/frontend/pages/Docs/data/pages/agents.md            ← replace placeholder
app/frontend/pages/Docs/data/pages/index.ts             ← add 5 new imports + DOC_PAGES entries
app/frontend/pages/Docs/data/navStructure.ts            ← add 5 new nav items to Core concepts
app/frontend/pages/Docs/data/searchIndex.ts             ← add 5 new entries, update 2 existing
```

Stubs filled (TIER 1, already in `index.ts`, just need their `.md` files to replace `STUB_CONTENT`):
```
app/frontend/pages/Docs/data/pages/integrations.md      ← new file (currently uses STUB_CONTENT inline)
app/frontend/pages/Docs/data/pages/configuration.md     ← new file (currently uses STUB_CONTENT inline)
app/frontend/pages/Docs/data/pages/cli-ref.md           ← new file (currently uses STUB_CONTENT inline)
app/frontend/pages/Docs/data/pages/api-guide.md         ← new file (currently uses STUB_CONTENT inline)
app/frontend/pages/Docs/data/pages/config-schema.md     ← new file (currently uses STUB_CONTENT inline)
```

> Note: For stubs that currently use `STUB_CONTENT` inline (not imported from a file), you need to both create the `.md` file AND update `index.ts` to import it as `?raw`.

---

## Dev Notes

- `yarn tsc` must pass after changes (no TypeScript errors).
- No Rails changes needed — docs are entirely frontend.
- No new npm packages needed — all rendering is already wired.
- Run `yarn lint` and check for no ESLint errors.
- To preview: the dev server runs at `http://localhost:4000/docs`. Use `make up` + `make worker` (or just `make up` for frontend-only dev).

---

## Dev Agent Record

### Completion Notes

Implemented 2026-06-15. All TIER 1, TIER 2, and TIER 3 work is complete.

**What was done:**

- **TIER 1 — Direct port from PR #173:** Replaced all placeholder `.md` files for `quick-start`, `agents`, `integrations`, `configuration`, `cli-ref`, `api-guide`, `config-schema` with content from `origin/feature/167-open-source-docs`. All relative markdown links converted to plain text cross-references.
- **TIER 2 — New pages:** Created five new `.md` files (`board`, `workflows`, `runtimes`, `tools`, `mcp`) from PR branch content. Registered all five in `index.ts`, `navStructure.ts`, and `searchIndex.ts`.
- **TIER 3 — Rewrites:** Rewrote `what-is-aixle.md` to correctly describe Aixle Flow as a Kanban + AI workflow product (removed all CLI/`defineConfig` fabrications). Created `install-guide.md` from the Docker prerequisites section of the PR quickstart.
- **`index.ts`:** Replaced `STUB_CONTENT` usage entirely. All 14 pages now imported as `?raw` markdown. Removed stubs for `self-hosting`, `cli`, `tasks-overview`, `tasks`, `permissions`, `deploy`, `advanced`.
- **`navStructure.ts`:** Flattened to three sections (Getting started, Core concepts, Reference) with no `children`. All stub-only nav entries removed.
- **`searchIndex.ts`:** Rebuilt with 14 real entries matching the new nav. Descriptions use actual product facts.

**Validation:** `yarn tsc` — 0 errors. `yarn lint` — 0 errors (11 pre-existing warnings, unrelated).

### File List

**New files:**
- `app/frontend/pages/Docs/data/pages/board.md`
- `app/frontend/pages/Docs/data/pages/workflows.md`
- `app/frontend/pages/Docs/data/pages/runtimes.md`
- `app/frontend/pages/Docs/data/pages/tools.md`
- `app/frontend/pages/Docs/data/pages/mcp.md`
- `app/frontend/pages/Docs/data/pages/install-guide.md`
- `app/frontend/pages/Docs/data/pages/integrations.md`
- `app/frontend/pages/Docs/data/pages/configuration.md`
- `app/frontend/pages/Docs/data/pages/cli-ref.md`
- `app/frontend/pages/Docs/data/pages/api-guide.md`
- `app/frontend/pages/Docs/data/pages/config-schema.md`

**Modified files:**
- `app/frontend/pages/Docs/data/pages/what-is-aixle.md` (full rewrite)
- `app/frontend/pages/Docs/data/pages/quick-start.md` (replaced placeholder)
- `app/frontend/pages/Docs/data/pages/agents.md` (replaced placeholder)
- `app/frontend/pages/Docs/data/pages/index.ts` (all imports, removed STUB_CONTENT)
- `app/frontend/pages/Docs/data/navStructure.ts` (rebuilt to final shape)
- `app/frontend/pages/Docs/data/searchIndex.ts` (rebuilt with real entries)

### Change Log

- 2026-06-15: Filled all in-app documentation content from PR #173 source material. 11 new `.md` files, 3 rewrites, `index.ts`/`navStructure.ts`/`searchIndex.ts` rebuilt.
