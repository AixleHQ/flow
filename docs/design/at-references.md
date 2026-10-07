# `@` references and one data-flow check

Flow task #1855 (GitHub palad-ai/palad-app#611). Status: implemented.

A session's instructions can now name an asset, another session, a declared output or an
MCP server with `@`. The editor stores a token that carries a stable id, shows it as a pill,
and binds whatever the token needs to work. The runtime replaces each token with the path or
name the agent can use. A single check, `DataFlow::Check`, reads the same graph and
reports what would fail at run time, while the author is still editing.

## 1. Why the two belong together

Before this change a file reached a session only when four things agreed, and nothing compared
them:

| Mechanism | What it decided | When it was checked |
|---|---|---|
| Run after | scheduling, plus which outputs are copied in (direct dependencies only) | save (cycles only) |
| Input spec (a name) | the step fails before starting if no file has that exact name | run time only |
| Output spec (a name or regex) | the step fails after finishing if it did not write it | run time only |
| The instructions text | where the agent looks | never |

Two failures were reported from the field and both are confirmed by the code:

- **Files reached only direct dependents.** A session that runs after Session 2, which runs
  after Session 1, did not get Session 1's files. Notes reached every later session, files did
  not (`PrepareStepActivity#collect_available_input_names`,
  `WorkflowStepStrategy#inject_prior_step_outputs`). The authoring UI never said so.
- **A path in a spec name failed silently.** Names are compared to the bare asset name or the
  path relative to `/workspace/outputs`. The input placeholder suggested `tasks/report.md` and the
  help text pointed at `/workspace/assets/…`, so authors wrote paths. Nothing checked them before
  a run.

A production survey (2026-10-07) added three facts: relative names such as
`intake/context-brief.md` are the norm in the busiest projects, globs (`analysis/**`) are written
into `name`, and two projects still hold specs as a JSON-encoded string from an older shape.

A reference is a statement about the same graph ("this session reads Session 1's
`summary.md`"). Inserting one is therefore the natural moment to bind it, and the check that
validates references is the same check that validates specs.

## 2. Token grammar

Instructions remain plain text. A reference is a token:

| Token | Names | The agent receives |
|---|---|---|
| `{{asset:123}}` | an `Asset` by id | `` `/workspace/assets/<folder>/<name>` `` |
| `{{output:45:summary.md}}` | output spec `summary.md` of step 45 | `` `/workspace/outputs/summary.md` `` in step 45 itself, `` `/workspace/assets/summary.md` `` in any later step |
| `{{step:45}}` | step 45 of the same workflow | `session "Collect sources"` |
| `{{mcp:7}}` | an `MCPServer` by id | `the "GitHub" MCP server` |
| `{{tool:9}}` | a `Tool` by id | `` the `post_summary` tool `` (the name it is called by) |
| `{{skill:4}}` | a `Skill` by id | `` the "House style" skill (`house-style`) `` |
| `{{config_item:3}}` | a `ConfigItem` by id | `` the `SLACK_TOKEN` config item (read it with `get_config_item`) `` — the name only; a value never enters the text |

- One scanner finds tokens: `/\{\{(asset|output|step|mcp|tool|skill|config_item):([^{}\n]+?)\}\}/`. The body is
  parsed per type. An id is a positive integer. A body that does not parse is a broken reference,
  not plain text.
- Any other `{{…}}` (`{{artifact_name}}`, `{{Sub-step name}}`) is left alone and reported as a
  warning: nothing substitutes it.
- **Draft steps.** The builder gives unsaved steps negative ids and sends them under the key
  `new-<n>`. A token may name a draft step as `{{step:new-3}}` or `{{output:new-3:x.md}}`.
  `WorkflowStepSync` rewrites these to real ids in the same transaction that creates the steps.
  Draft keys never persist.
- **Why outputs are by name.** Output specs are rows of a jsonb array with no id of their own,
  and the file name *is* the contract between producer and consumer. Specs are edited only in the
  builder, which saves the whole workflow at once, so renaming a spec rewrites every token that
  names it in the same draft.
- **Why `mcp` and not `connection`.** When other integrations become referenceable they get
  their own prefix; one prefix over ids from different tables would be ambiguous.

Out of scope: references in agent persona (an agent is not bound to a workflow and its persona
is already in context), references to sub-steps (they have no artifacts and no id the agent
could act on), agents and board objects. Tools, skills and config items were added after the first
release, on the same rules as MCP servers.

## 3. Inserting a reference binds it

Typing `@` opens a grouped picker for the session being edited:

| Group | Rows |
|---|---|
| Assets | assets attached to the session, workflow base assets, other project and company assets; this session's declared outputs; other sessions' declared outputs |
| Sessions | every other session of the workflow |
| Connections | MCP servers attached to the session, to the workflow base, inherited from the project, and the project's other servers |
| Tools | tools the project can attach (platform and project tools), attached ones first |
| Skills | the project's skills, attached ones first |
| Config items | the project's secrets and variables, by name and type |

Choosing a row inserts the token and makes it work:

- an asset not yet available to the session is added to the session's assets;
- an MCP server, tool, skill or config item not yet available is added to the session's own list
  (`mcp_server_ids`, `tool_ids`, `skill_ids`, `config_item_ids`);
- another session's output, when that session is not upstream, adds it to **Run after**. A row
  that would create a cycle is disabled ("runs after this session");
- a session reference binds nothing. If that session is not upstream the check warns.

Removing a pill does not detach anything: the attachment may serve another purpose and an extra
one is harmless. Detaching while a token still names the resource is reported (`ref_not_attached`).

Outputs with a glob name or a legacy `name_pattern` are not offered: there is no single path to
give the agent.

## 4. Runtime

- **One renderer**, `InstructionReferences::Renderer`, runs where the agent receives instructions:
  the CLI prompt (`WorkflowStepStrategy#agent_prompt`), the context file's `current-step`
  section, and the session's stored `initial_prompt` (so the run view shows what the agent saw).
  Lookups are scoped: assets by `Asset.accessible_from_project`, servers by
  `MCPServer.visible_for_project`, steps by the step's own workflow. An id that does not resolve
  inside those scopes renders as `[missing reference]`; it never reaches another tenant's row.
- **Fail fast.** `PrepareStepActivity` checks the step's references before the session starts,
  next to the input check, and fails the step with `Reference check failed: …`. It runs only for
  steps whose instructions hold a reference, so workflows without one take the old path.
- **Outputs reach every downstream session.** `Step#upstream_step_ids` is the transitive closure
  of Run after. Injection copies outputs from all of them, farthest first, so when two upstream
  sessions wrote the same name the nearest one wins. The input check counts the same set.
- **The context file lists the files** copied in from earlier sessions, with their paths
  (section `earlier-files`).

## 5. Specs

`DataFlow::AssetSpec` is the one reader of `input_asset_specs` and `output_asset_specs`:

- accepts the current shape (`name`, `required`, `asset_type`, `name_pattern`), a missing
  `required` key (required), and the legacy JSON-encoded string;
- a `name` is a path relative to `/workspace/outputs` (or an asset's name). On save a leading
  `/workspace/assets/`, `/workspace/outputs/` or `workspace/…/` is stripped;
- a `name` containing `*`, `?` or `[` is a glob (`File.fnmatch` with `FNM_PATHNAME | FNM_EXTGLOB`;
  `**` crosses directories). `name_pattern` stays a Ruby regex for the rows that already use it;
- `InputValidator`, `OutputValidator` and `StepSkipEvaluator` all match through it, so
  "required" and glob semantics no longer differ between them;
- the input check counts only active assets, as injection does.

The output validator stays: it fails the producing session where the cause is, instead of three
sessions later. The input check stays for what the graph cannot promise (a skipped producer, an
optional output, a deleted asset, a run input that was not picked). Input specs written by hand
are now needed only for files picked when the run starts; a referenced output or asset is
checked without one.

## 6. `DataFlow::Check`

One Ruby service over a graph built either from the saved workflow or from the builder's
unsaved payload. It returns issues:

```json
{ "severity": "error", "code": "output_not_upstream", "stepKey": "45", "field": "instructions",
  "message": "Report reads summary.md from Collect, which does not run before it.",
  "fix": { "kind": "add_dependency", "stepKey": "12" } }
```

| Code | Severity | Rule | Fix |
|---|---|---|---|
| `ref_missing` | error | a token names nothing in scope (deleted, archived, disabled, other project, malformed) | — |
| `ref_not_attached` | error | a token names a resource the session will not receive | `attach_asset` / `attach_mcp_server` / `attach_tool` / `attach_skill` / `attach_config_item` |
| `output_not_upstream` | error | an output token names a session that does not run before this one | `add_dependency` |
| `output_undeclared` | error | an output token names a spec the session no longer declares | — |
| `spec_name_invalid` | error | blank, absolute, or contains `..` | — |
| `name_pattern_invalid` | error | `name_pattern` is not a valid regex | — |
| `input_unsatisfied` | warning (error at run start) | a required input that no upstream output, attached asset or run input can satisfy | — |
| `output_collision` | warning | two upstream sessions declare the same output | — |
| `step_not_upstream` | warning | a session token names a session that does not run before this one | `add_dependency` |
| `unknown_braces` | warning | `{{…}}` that is not a reference | — |

Where it runs:

- **Builder**: `POST …/workflows/:id/aggregate/check` with the unsaved payload, debounced while
  editing; the save response carries the same issues. Save is never blocked by them. The check is
  a POST, so it is a project write (viewers cannot edit the workflow anyway).
- **Run start**: `WorkflowService.enqueue` refuses a run with errors, counting the picked run
  inputs. A check that raises is logged and does not block (fail open).
- **`validate_workflow`** (personal MCP) appends the issues to its errors and warnings.

## 7. Copies keep their references

Instructions used to be copied verbatim. Now:

- `WorkflowDuplicator` rewrites step and output tokens through its step id map; MCP server, tool,
  skill and config item tokens through `DependencyCopier` (config items by name, as their ids are);
  asset tokens through the same carry rule as asset ids.
- `Templates::Exporter` rewrites ids to package keys (`{{asset:brand_guide}}`,
  `{{step:collect}}`, `{{skill:house_style}}`; config items by name, `{{config_item:SENTRY_ORG}}`);
  `Templates::Installer` maps keys back to the new ids after the steps exist.
- A token that cannot be carried becomes its name as plain text, so the copy reads sensibly and
  the author can re-insert it. It never keeps an id that points into the source project.
- Version revert needs nothing: steps are soft-deleted, so ids in a snapshot stay valid.

On save, a token must name a resource owned by the workflow's project (the same rule as the id
columns), so an id cannot be planted from outside.

## 8. Editor

CodeMirror 6, already in the bundle for the tool file editor:

- the document *is* the stored string, so there is no DOM-to-text serializer to get wrong;
- tokens are replaced by pill widgets (`Decoration.replace`), and `EditorView.atomicRanges`
  makes Backspace and Delete remove a token whole;
- a token pasted as text becomes a pill; undo, IME and selection behave as in any editor;
- `@codemirror/autocomplete` drives the picker (sections for groups, our own substring filter);
- `hoverTooltip` shows type, name and id, plus Replace / Remove in edit mode;
- read-only (`EditorView.editable.of(false)`) still renders pills.

Pills resolve against the picker catalog. While the catalog's deferred props are loading, pills
show a neutral loading state, never "broken".

The builder was editable for project viewers (only company scope set `read_only`); it now also
honours `canExecute`.

## 9. Not changed

Sub-step instructions keep a plain textarea. Agent persona keeps its textarea. Interactive
sessions, Aixle Builder generation and template authoring do not insert references; the Builder
is told the syntax so it preserves tokens it reads back.
