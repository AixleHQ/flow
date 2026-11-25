# Tool Attachment: a session gets only the tools attached to it

**Status:** Design (task #290)
**Scope:** Which tools a session is served, and how the platform stops granting tools that nobody attached.

## 1. Overview

**The rule (Alex, 2026-11-25).** Access to tools is strictly regulated. A session gets a tool only when its workflow, its step or the session itself attached it. A connected integration, an attached repository or a tracker trigger does not grant tools.

Today `TerminalSession#available_tools` serves attached tools **plus** everything the code-only `inject_when` rules (`Tools::InjectionRules`) match, **plus** a fallback that hands a session with no custom tool every enabled custom tool of the project. A QA workflow with no Coder tools attached ran `coder_ssh_exec` on a Coder workspace because a Coder integration existed.

Tools served without an attachment today:

| # | Source | Tools |
|---|---|---|
| 1 | `coder_integration_connected` | 5 `coder_*` |
| 2 | `azure_integration_connected` | `azure_devops_list_builds`, `azure_devops_list_connections` |
| 3 | `workflow_step_session` | 14 `board_*`, 4 `chat_*`, `share_asset`, `promote_asset`, `list_sub_steps`, `mark_sub_step` |
| 4 | `azure_repositories_attached` | 15 `azure_devops_*` pull request tools |
| 5 | `tracker_run` | 15 `tracker_*` |
| 6 | `github_repositories_attached` | `refresh_github_token` |
| 7 | `config_items_attached` | `get_config_item` |
| 8 | `container_tools_present`, `non_interactive_session` | `read_tool_result`, `finish_session`, `fail_session` |
| 9 | custom-tool fallback in `available_tools` | every enabled custom (`db`) tool of the project |

This design:
1. fixes the **plumbing list**, the only tools that stay automatic;
2. removes every other grant, including the fallback;
3. migrates existing workflows so each keeps the tools it uses, attached explicitly;
4. makes every formerly injected tool attachable in the pickers, the API and the MCP tools;
5. adds a test that fails when a non-plumbing tool reaches a session that did not attach it.

## 2. Approach

### 2.1 Plumbing list

Plumbing is a tool a session needs to work at all, or one that follows an attachment and grants no capability the attachment did not already grant.

| Tool | Stays automatic when | Why it is plumbing |
|---|---|---|
| `finish_session`, `fail_session` | the session is non-interactive | The only way a non-interactive session ends. Without them the session hangs. |
| `list_sub_steps`, `mark_sub_step` | the session is a workflow step | Progress contract of the step; reads and writes only that step's own sub-steps. |
| `read_tool_result` | the session's attached tools include a container tool | Only way to poll the result of a tool the session attached. |
| `refresh_github_token` | a GitHub repository is attached | Repairs the clone's own expiring token. Grants nothing new. |
| `get_config_item` | a config item is attached (`SessionConfigResolver#resolve_config_item_ids`) | Reads only items already attached. |

Seven tools. This is the full list. Every other tool, including all `board_*`, `chat_*`, `coder_*`, `azure_devops_*`, `tracker_*`, `share_asset` and `promote_asset`, is served only when attached.

Three of the seven are conditional on an attachment (`read_tool_result`, `refresh_github_token`, `get_config_item`). A session that attached nothing gets at most the four unconditional ones for its mode and type: `finish_session`/`fail_session` (non-interactive) and `list_sub_steps`/`mark_sub_step` (workflow step). This is what the acceptance test asserts.

### 2.2 Mechanism

The `inject_when` DSL and `Tools::InjectionRules` stay, narrowed to plumbing. They are the only place a session predicate is evaluated, and the five remaining rules already exist.

- Add `Tools::Plumbing::NAMES` (frozen, the seven names above) in `app/services/tools/plumbing.rb`.
- `Tools::DefinitionDSL::Builder#inject_when` raises `ArgumentError` at class load when the tool's name is not in `Plumbing::NAMES`. A new tool cannot be made automatic without editing the plumbing list, which the test in §6 pins.
- Delete the rules `coder_integration_connected`, `azure_integration_connected`, `azure_repositories_attached` and `tracker_run` from `InjectionRules::RULES`, and the `inject_when` lines of the tools that used them.
- Narrow `workflow_step_session`: it stays only on `list_sub_steps` and `mark_sub_step`. Remove it from the 14 `board_*`, 4 `chat_*`, `share_asset` and `promote_asset`.
- `TerminalSession#available_tools` becomes: attached tools (tenant-owned, enabled, not deleted) plus plumbing tools whose rule matches. Delete the `Tool.for_project(project)` fallback (`base.none?(&:db_source?)`).

Alternatives considered:
- **A per-tool `plumbing true` flag replacing `inject_when`.** Rejected: the conditions differ per tool (non-interactive, workflow step, container tools present), so the predicates would move without being removed.
- **Keep injection, gate on a workflow setting such as "allow integration tools".** Rejected: a switch that grants a group of tools is the same ambient grant under another name.

### 2.3 Attaching what used to be injected

- **Azure DevOps (17 tools).** Set `user_attachable true` (remove `user_attachable false`) and make `:azure_devops` `ui_visible: true` in `Tools::TagCatalog`, with the comment explaining the old "injected, not picked" choice removed. The picker shows one **Azure DevOps** section. The `requires_integration :azure_devops` gate still hides the section until the connection exists. Repository tools still refuse a call for a repository that is not attached to the session (`AzureDevopsContext`); attaching a repository does not attach the tools, and attaching the tools does not attach a repository. `Tools::RegistryTest` currently asserts "Azure tools must not be offered in the picker" and must be rewritten (§6).
- **Coder, board, chat, tracker, assets.** Already `user_attachable` and in visible tag groups. No change.
- **`share_asset`, `promote_asset`** are tagged `:assets`, a visible group. No change.
- **Custom (`db`) tools.** Already attachable. Only the fallback goes.
- **API and MCP.** `tool_ids` / `base_tool_ids` on workflow and step endpoints, `PersonalTools::{Create,Update}Workflow*`, and `validate_workflow` already resolve against `Tool.visible_for_project`, which filters `user_attachable: true`. Making the Azure tools attachable is therefore the whole change there. `list_project_tools` returns them with no change. Update its description and `Tools::PersonalMCPGuides` text ("the platform injects those automatically", line ~443) and `ContextBuilders::AixleBuilder` to say plumbing only is automatic and every other tool, including board and chat, must be attached.
- **Picker UI.** `ToolPicker` renders groups from `Registry.ui_groups` / `PickerGroups`, so the Azure section appears with no frontend code. Add one frontend test for the section (§6).

### 2.4 `inherit_all_project_resources` stays

A workflow with `inherit_all_project_resources` already gets every `Tool.visible_for_project` tool (`SessionConfigResolver#project_tool_ids`). This is a workflow-level opt-in shown in the builder, so it counts as an attachment by the workflow, and this design leaves it unchanged. See Decision D5.

## 3. Data Model Changes

No schema change. One data migration (§5). Tool rows already exist for every code tool through `Tools::Reconciler`; the migration reads them like `AttachPullRequestToolsToWorkflows` did.

## 4. API / Interface Changes

- No new endpoints and no new parameters.
- Behavior: MCP `tools/list` and `tools/call` for a session serve only attached tools plus plumbing. A `tools/call` on a tool that is not attached is "not entitled" (existing `Tools::MCPRequestHandler` path).
- Azure tools become visible in `GET`/MCP tool catalogs and accepted in `tool_ids`.
- Release note: workflows created after this change (through the builder, the API, the MCP tools or a template install) must attach their tools.

## 5. Migration of existing data

File: `db/migrate/<ts>_attach_formerly_injected_tools.rb`. Follow `20261124112933_attach_pull_request_tools_to_workflows.rb`: self-contained inline models (`workflows`, `steps`, `workflow_resource_links`, `step_resource_links`), no dependency on app classes, `down` is a documented no-op, runs before the new code serves (an extra link is harmless to the old code).

### 5.1 Why not "everything the old rules would have served"

Nothing records which app tool a session called (`ToolResult` exists only for container tools; telemetry is not stored). Attaching every formerly injectable tool to every workflow keeps workflows working but grants the 22 workflow tools to all of them, which is the thing this task removes. The migration therefore attaches a tool only with evidence the workflow uses it.

### 5.2 Rule

For each non-deleted, non-System workflow and each of its non-deleted steps, a tool T from the **migrated set** is attached to the **step** (`step_resource_links`) when both hold:

1. **Reachability (R).** The old rule would have served T to a session of this step:
   - `workflow_step_session` tools: always.
   - `coder_*`, `azure_devops_list_builds`, `azure_devops_list_connections`: an active `integrations` row of that provider for the workflow's company, company-wide or for the workflow's project (same predicate as `Tools::Context#connected_providers`).
   - `azure_devops_*` pull request tools: the old rule needed an attached Azure repository; R holds when the step's resolved repositories (workflow base plus step, or every project repository under `inherit_all_project_resources`) include one whose integration provider is `azure_devops`.
   - `tracker_*`: the workflow has a `trigger_bindings` row with a `project_tracker_id`.
   - `chat_*`: an active Slack or Teams integration for the company or project.
2. **Evidence (E).** At least one holds:
   - The tool name or `{{tool:<id>}}` appears in the text the step's session is given: step `instructions`, its sub-steps' instructions, the step agent's instructions, the bodies of skills attached to the step or the workflow base.
   - **Structural.** The workflow has a tracker trigger binding (`project_tracker_id` set) and T is a `tracker_*` tool, or a chat trigger binding (`chat_conversation_id` set) and T is a `chat_*` tool. The trigger is the declaration that the run talks to that system.
   - **Working-set closure.** For `coder_*` and `azure_devops_*` only, evidence for one tool attaches the whole tag group, because the tag catalog documents that half a working set (allocate without release, open a pull request without answering its threads) is a failure mode.

The same rule handles the custom-tool fallback (#9): a step whose resolved tool set holds no custom tool (and that is not under `inherit_all_project_resources`) gets each enabled custom tool of its project whose name or `{{tool:<id>}}` appears in the step's text.

**Granularity is the step**, not the workflow base. A base link would grant the tool to every step of the workflow, which is more than the step that mentions it uses.

### 5.3 Report, not guess

R true and E false is the case where a workflow may have used a tool without naming it. The migration does not attach it. It `say`s one line per workflow id and tool name (ids only, no names of customers or projects), so the operator who deploys sees the list of tools no longer served. The release note tells operators to review it. Missing a tool fails loudly (the agent reports "tool not available"); granting it silently would not.

### 5.4 Templates and workflows created through API / MCP

- **Installed templates and workflows made through the API, builder or MCP tools** are rows in `workflows`/`steps` by the time the migration runs, so §5.2 covers them.
- **Catalog templates** (`catalog_templates.definition`, synced from the separate templates repository by `Templates::CatalogSync`) are package files naming tools by `platform:` key (`Templates::Installer#create_tools`). Packages written for injection list no platform tools. They need a package change in that repository, adding `platform` tool entries to the steps that use board, chat, coder, tracker, asset or Azure tools. That change cannot be made in this repository. The implementation PR delivers: a list of affected packages (produced by a one-off script that runs the §5.2 evidence rule over each package's step text), and the `Templates::RepositoryValidator` warning below. Until the packages are updated, a template installed from the catalog installs a workflow with no platform tools.
- Add to `Templates::RepositoryValidator` a **warning** (not an error) when a step's text names a platform tool the step does not list. The check is the E rule, so it is cheap and shares code with the one-off script (`Tools::LegacyInjection::Evidence`, §7).

## 6. Testing Approach

Tests follow `docs/testing.md`; model and service tests under `test/`, one frontend test.

1. **The guard (new, `test/services/tools/plumbing_test.rb`).**
   - Static: every definition in `Tools::Registry.definitions` that is not in `Tools::Plumbing::NAMES` has empty `inject_rules`; every plumbing name has a rule; `Plumbing::NAMES` equals the seven names.
   - Dynamic, **in a project with every integration connected** (Coder, Azure DevOps, Slack, Teams, GitHub, a usable tracker), a tracker-started run, an attached Azure repository, an attached GitHub repository, an attached config item and an attached container tool: for a workflow-step session, a non-interactive agent session and an interactive agent session that attach nothing else, `available_tools` names are a subset of `Plumbing::NAMES`. This is the test that fails when a rule grants a tool.
   - A session that attaches tool X gets X and no other non-plumbing tool.
2. **`DefinitionDSLTest`:** `inject_when` on a non-plumbing tool name raises.
3. **Rewrite** `TerminalSessionAvailableToolsTest`: the cases asserting injection (`board_*`/`chat_post_message` for workflow steps, Coder, Azure, tracker run, the custom-tool fallback) now assert the opposite without an attachment and the tool with one. Keep the plumbing cases (`finish_session`, `fail_session`, `refresh_github_token`, `get_config_item`, `read_tool_result`).
4. **Rewrite** `Tools::RegistryTest` (`injectable covers…` expects the 5 plumbing rules; `grouping axes` counts: 2 workflow-step rules, 3 lifecycle/async; Azure tools attachable with no inject rules, 17 tools) and `TagCatalogTest`/`PickerGroupsTest` (Azure DevOps group visible).
5. **MCP:** `McpControllerTest` / `Tools::MCPRequestHandler`: `tools/list` of a Coder-connected project's session without attached Coder tools lists no `coder_*`; `tools/call coder_ssh_exec` is refused as not entitled.
6. **Existing tests that rely on injection** (`get_config_item_test`, `pull_request_tools_test`, `internal_tools/*_test`, `personal_mcp_test`, `integration/mcp_controller_test`): fix by attaching the tool in setup. Find them with `rg "session_type: \"workflow_step\"|available_tools"` under `test/`.
7. **Migration test** (`test/migrations/` if the suite has the convention, else a service test of an extracted `Tools::LegacyInjection` class that the migration inlines): a workflow whose step names `coder_ssh_exec` with a Coder integration gets all five `coder_*`; a step that names nothing gets nothing and is reported; a tracker-bound workflow gets `tracker_*`; a step with no custom tool and a mention of one gets that one; a System workflow is untouched; running twice adds no duplicate link.
8. **Frontend:** `ToolPicker.test.tsx`: the Azure DevOps section renders when the project has the connection.

## 7. Implementation Steps

1. `Tools::Plumbing` and the DSL check; remove the four rules and the `inject_when` lines; narrow `workflow_step_session` to the two sub-step tools (`app/services/tools/{plumbing,injection_rules,definition_dsl}.rb`, `app/services/internal_tools/*`).
2. `TerminalSession#available_tools`: drop the fallback; update the method comment.
3. Azure tools: `user_attachable` on, `TagCatalog` entry visible with a new comment. Check `Tool.visible_for_project` and `PickerGroups` show the group.
4. Fix the existing tests (§6.3–6.6) and add the guard (§6.1–6.2).
5. Data migration (§5) and the evidence helper, in one class so the migration, the templates validator and the package-listing script share it. The migration inlines a copy, as the precedent does, so it stays valid when app classes change.
6. Builder and MCP guide text (`context_builders/aixle_builder.rb`, `tools/personal_mcp_guides.rb`, `personal_tools/list_project_tools.rb`).
7. Docs (§8).
8. `CHANGELOG.md` entry and release note describing the behavior change and the migration report.
9. Open the follow-up in the templates repository (§5.4).

## 8. Docs to change

- `docs/design/tool-execution.md`: §9 "Adding a New Tool" says what `inject_when` is for (plumbing only) and links this document.
- `docs/project/context.md`: the **Workflow Tool** glossary row and the "Auto-injected internal tools" and "Integration-gated tools" bullets (lines ~459–469): only plumbing is automatic; `requires_integration` only hides a tool until the integration exists.
- `docs/architecture/workflows.md`: internal tools section (~727–745) and the `share_asset` mention (~1041).
- `docs/user-guide/mcp.md` line 25 (progress tools stay automatic; board tools do not), `docs/user-guide/workflows.md` (attach tools to steps).
- Integration designs that rely on injection, each gets a note pointing here: `azure-devops-integration.md` (§ "injected, not picked", ~368–381), `task-tracker-integrations.md` §7.3, `teams-integration.md` (~772), and `github-user-identity.md` D8 needs no change.
- In-app docs under `app/frontend/pages/Docs/data/pages/`: `trackers.md` ("A run a tracker event started has all of them", ~377), `coder.md` (the project "has the `coder_*` tools", line 5, and the picker group, line 81), `azure-devops.md` (tools are attached).

## 9. Edge Cases & Risks

- **Sessions in flight at deploy.** A workflow step session copies its resolved tools into `session.tools` at creation. A session started before the migration lacks the attached links, and the new code stops serving its injected tools mid-run. Deploy outside active runs or accept that those sessions fail on the next such call.
- **Standalone sessions** (personal, API) carry their tool list in the creation request and persist no template, so nothing is migrated for them. People who relied on injection attach tools in the session form.
- **Evidence misses.** A workflow that used a tool without naming it loses it (§5.3). The report lists it. Re-attaching is one picker click.
- **Evidence over-grants.** A name mentioned in a "never call X" instruction attaches X. Accepted: the grant is bounded by the step and visible in the builder.
- **Tool without a shadow row.** The migration skips tools with no `tools` row (`source = 'code'`), as the precedent does; the reconciler creates rows at boot and on first use, so a fresh install has nothing to migrate.
- **Rolling deploy.** Old pods still run the injection rules while new pods run without. The migration only adds links, so both behave correctly.
- **Chat reply path.** A chat-triggered run answers through `chat_post_message`; the structural evidence keeps that working. A chat-triggered workflow that is not bound by a trigger binding relies on §5.3.
- **`inherit_all_project_resources`** remains an ambient grant of every attachable platform tool (D5).
- **Security regression.** The §6.1 dynamic test is the control: adding a rule or a handler `inject_when` that serves a non-plumbing tool fails CI.

## 10. Decisions & Assumptions

| ID | Decision | Source |
|---|---|---|
| D1 | Plumbing is exactly seven tools (§2.1). `refresh_github_token` and `get_config_item` stay because they only follow an attachment. | Task description candidates; code of `InjectionRules` |
| D2 | The `inject_when` mechanism stays, restricted to plumbing at class load. | Reuse of the existing DSL and `Registry.injectable` |
| D3 | Azure tools become attachable and visible; picker section gated by `requires_integration`. | Task: "The Azure tools are hidden from the picker today" |
| D4 | Migration grants by reachability **and** evidence, at step granularity, and reports the rest. | Task: "without granting more than the workflow uses"; no call log exists |
| D5 | `inherit_all_project_resources` is an explicit workflow-level attachment and is unchanged. | It is not in the task's list of injection places; changing it would break workflows that opted in |
| D6 | Catalog template packages are fixed in the templates repository, not here. | `Templates::CatalogSync` reads them from a separate repository |
| D7 | No production identifiers appear in this document, the migration output or the PR. | Alex's comment of 2026-11-25 |

## 11. Deferred Questions

- **Should `inherit_all_project_resources` stop covering platform tools?** It is the last ambient path. Narrowing it needs its own migration and a product decision on what "inherit all" means. Deferred to a follow-up task.
- **A recorded call log for app tools** would make the migration exact. Not needed once the migration has run; out of scope.
- **Per-tool permission levels** (read versus write board tools in the picker). Not asked for.
- **Updating the catalog template packages** (§5.4) is a task in the templates repository.
