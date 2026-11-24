# Workflow drafts: change a workflow in use without breaking it

**Status:** Built (first phase: workflows)
**Date:** 2026-11-23
**Baseline:** `develop` @ `3d398aa2`
**Related:** [entity-versioning.md](./entity-versioning.md) (D1 and D4 there: the live row is the current version, runtime reads live rows)

---

## 1. Problem

A Save in the workflow builder goes straight into production. Every trigger and
board column bound to the workflow runs the new version from that moment, and a
run already in progress picks the change up in the steps it has not started yet.
There was no way to try a change on a workflow that is in use without exposing
everything that starts it.

Entity versioning (#329) made changes visible and revertable, but deliberately
kept "no draft/publish": pinning a run to a version would have meant moving the
~20 places runtime reads live rows onto snapshots.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | **A draft is a hidden copy of the workflow** (a `workflows` row with `draft_of_id`), in the same project. It is edited with the same endpoints and tools as any workflow and run by the unchanged runtime. Nothing in the ~20 runtime read points changes. |
| D2 | **One open draft per workflow**, shared by everyone who can edit it (a partial unique index). Several drafts would be branches that need merging, and Apply replaces the live workflow wholesale. |
| D3 | **Apply writes the draft onto the original through the builder's own Save** (`WorkflowAggregateSave` inside `Versions.save!`): one new version of the original, metadata `applied_from_draft_id`. Step and sub-step rows of the original are updated in place, so ids, run history and version diffs stay continuous. |
| D4 | **Direct editing stays.** A draft is opt-in. Saving a workflow that triggers or board columns start asks first: *Save to live* or *Save as draft*. |
| D5 | **Apply refuses when the live workflow changed after the draft was made** (its version moved past `draft_base_version`) and applies only when told to overwrite. There is no merge. |
| D6 | **Apply and Discard close the draft** by archiving it (a version event `archived` on the draft). It stays, hidden, with its test runs; the next draft is made fresh from the live workflow. Closing does not wait for a running test run: it keeps reading the draft's rows. |
| D7 | **A draft is never a target**: no trigger, column binding, catalog publish, template export, duplicate or chat run picker reaches it. It is reached only through its live workflow (`/workflows/:id/draft`) or by its id in the tools that edit and run a workflow. |
| D8 | **A draft's test run does not start live workflows from the board**: a card its agent moves into an auto-bound column moves without starting that column's workflow. |
| D9 | **Agents, skills, tools and MCP servers are not drafted** in this phase. A draft's steps point at the same rows as the live workflow, so editing an agent still affects both. |

## 3. Data model

| Column | Meaning |
|---|---|
| `workflows.draft_of_id` | the workflow this row is a draft of; FK `on_delete: cascade` |
| `workflows.draft_base_version` | the original's `current_version_number` when the draft was made |
| `steps.origin_step_id` | on a draft's step: the original's step it was copied from; FK `on_delete: nullify` |
| `sub_steps.origin_sub_step_id` | the same for sub-steps |

Indexes: `index_workflows_on_open_draft` (unique `draft_of_id` where not deleted)
and the name index `index_workflows_on_scope_and_name_unique`, now limited to
non-drafts, because a draft keeps its original's name. The model's name
validation skips drafts for the same reason.

The four columns are system state: the workflow snapshot excludes them
(`Versions::Snapshots::Workflow`).

## 4. Lifecycle

`WorkflowDrafts` (`app/services/workflow_drafts.rb`) is the only writer.

- **`open!(workflow, actor:, aggregate: nil)`** returns the open draft, or makes
  one: the original's snapshot is synced into a new row by `WorkflowStepSync`
  with `keep_origins: true`, so each copied step and sub-step records its origin.
  With `aggregate` (the builder's unsaved Save, in the original's step ids) the
  new draft takes it as its first change; refused when a draft is already open.
- **Editing**: the builder saves the draft through the ordinary aggregate
  endpoint, by the draft's id; the personal MCP tools take the draft's id as
  `workflow_id`. The draft has its own version history.
- **Test run**: an ordinary manual run of the draft (`WorkflowService.start`).
  `WorkflowRun#workflow` is the draft, so the run page and the feed can say so
  (`WorkflowRunResource#draft_test`).
- **`changes(draft)`**: the live snapshot and the draft's snapshot written in
  the original's step ids, plus the names of what they reference — the two sides
  of the existing `VersionDiff`. A step the draft added carries `new-<id>`.
- **`apply!(draft, actor:, overwrite: false)`**: checks D5, translates the
  draft into a Save payload for the original, validates it, saves it as one
  version, closes the draft.
- **`discard!(draft, actor:)`**: closes the draft.

### 4.1 Translating step ids

`WorkflowDrafts::Translation` rewrites step specs from one workflow's step ids
to another's: the step ids, `depends_on_step_ids`, and the `{{step:…}}` /
`{{output:…}}` references in step and sub-step instructions. A step with a
counterpart takes its id; one without becomes a new step keyed `new-<id>`, which
`WorkflowStepSync` already resolves for dependencies and references once the
row exists. The same class serves the three directions:

| Direction | Map | Used by |
|---|---|---|
| original → new draft | empty: every step new, origin recorded | `open!` |
| original's ids → draft's ids | `origin_step_id` → draft step | `open!` with `aggregate` |
| draft → original | draft step → `origin_step_id`, only for origins still live | `apply!`, `changes` |

A step deleted on the original after the draft was made has no live counterpart
and comes back as a new step. A sub-step maps only within the step its step maps
to.

## 5. Where drafts are hidden

`Workflow.visible_for_project` and `belonging_to_company` leave drafts out, which
covers the workflow lists, the session run drawer, the Aixle Builder snapshot, the
company catalog, `list_workflows` and both binding validations.
`Workflow.editable_for_project` keeps them, for the paths that open, edit and run
a workflow by id: the builder API (`show`), the manual run, and the personal
tools' `find_workflow!`. Call sites that bypass the scopes exclude drafts with
`not_drafts`: the archived list, the board's binding picker, the triggers page,
the chat run catalog, template export, publish, and the workflow counts. Entity
versions' "where used" names a draft as "Name (draft)".

Bindings refuse a draft with their own message ("is a draft: triggers start the
live workflow"), and the personal `delete_workflow` / `duplicate_workflow` point
at the draft tools instead.

## 6. Test-run side effects

`InternalTools::BoardMoveTask` passes `start_column_workflow: false` to
`TaskService.move` when its session runs a draft, and says so in its result. The
column trigger is the one path by which a run's own board writes start other
workflows; tracker and pull-request triggers already ignore Aixle's own changes by
default (`aixle_changes`).

What a test run does outside Flow (pushes, pull requests, messages) is real: its
agent holds the same credentials as any run. The draft banner says the run is
real, and the custom run mode (each step started by hand) is the way to stop
between steps.

## 7. Surfaces

**Builder** (`/company/:company_slug/projects/:project_id/workflows/:id/builder`):
- props `draft` (the open draft: id, last change, by whom), `draft_of` (on the
  draft page: the live workflow's id, name, current and base version) and
  `active_trigger_count` (enabled triggers + bound columns);
- live page: *Edit in draft*, or a banner with *Open draft* when one is open; a
  Save with `active_trigger_count > 0` asks *Save to live* / *Save as draft*;
- draft page (`/company/:company_slug/projects/:project_id/workflows/:id/draft`, the live id):
  banner, *Test run*, *What will change*, *Apply* (with *Apply anyway* on a
  conflict), *Discard draft*; no Triggers tab. The builder URL of a draft's own
  id redirects here.

**JSON API** (`/api/v1/projects/:project_id/workflows/:workflow_id/draft`, the
live id): `POST` (open, optional `aggregate`), `GET changes`, `POST apply`
(`overwrite`; 409 with `baseVersionNumber`/`liveVersionNumber`), `DELETE`.
Project write permission for all four.

**Personal MCP**: `create_workflow_draft`, `get_workflow_draft_diff`,
`apply_workflow_draft`, `discard_workflow_draft`; `get_workflow` returns
`draft_workflow_id` / `draft_of_workflow_id`. Existing tools keep editing the
live workflow unless given the draft's id. The `build_workflow` prompt and the
system reference describe the flow.

## 8. Later phases

1. **Draft agents, skills, tools and MCP servers with the workflow** (D9): an
   edit of a shared resource inside a draft forks it for the draft; Apply writes
   the fork back with `Versions.save!`. Until then, a cheap guard: the resource
   forms say how many workflows and active triggers use the resource before Save.
2. **Pin a run to the version it started with.** Drafts make live changes rare
   and deliberate (one Apply instead of every Save), but a run in progress still
   picks up an Apply in its later steps. `step_runs.workflow_version_id` is
   already recorded.
3. **Sandbox projects** for changes whose side effects cannot be contained by a
   test run: a project installed from the template of the real one, with its own
   repositories and channels.
