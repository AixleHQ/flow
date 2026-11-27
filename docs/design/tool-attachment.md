# Tool Attachment: a session gets only the tools attached to it

**Status:** Design (task #290), round 5, with the review decisions (no feature flag, one migration, no templates change, no migration tests, AI Builder text, tracker and repository reachability)
**Scope:** Which tools a session is served, and how the platform stops granting tools that nobody attached.

## 1. Overview

**The rule (Alex).** Access to tools is strictly regulated. A session gets a tool only when its workflow, its step or the session itself attached it. A connected integration, an attached repository or a tracker trigger does not grant tools.

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
2. removes every other grant, including the fallback, unconditionally (no feature flag, §2.5);
3. migrates existing workflows with one data migration, so each step keeps every tool the old rules served, attached explicitly;
4. makes every formerly injected tool attachable in the pickers, the API and the MCP tools;
5. adds a test that fails when a non-plumbing tool reaches a session that did not attach it.

## 2. Approach

### 2.1 Plumbing list

Plumbing is a tool a session needs to work at all, or one that follows an attachment and grants no capability the attachment did not already grant. Alex settled it.

| Tool | Served when | Why it is plumbing |
|---|---|---|
| `finish_session`, `fail_session` | every session, interactive too | The way a session ends. A person can tell an interactive session "when you are done, finish the session" and close the terminal. |
| `list_sub_steps`, `mark_sub_step` | every session | Progress contract of a workflow step. Outside a workflow step they answer with their existing "only available during workflow execution" error. |
| `read_tool_result` | a container tool is attached | Only way to poll the result of a container tool the session attached. |
| `get_config_item` | a config item is attached (`SessionConfigResolver#resolve_config_item_ids`) | Reads only items already attached. |

Six tools. `refresh_github_token` is **not** plumbing: it becomes attachable (`user_attachable true`) and is served only when attached. A GitHub repository can be given to an agent without it (for example read-only). The git credential helper (`GitCredentials::SessionGitSetup`) already fetches a fresh token on every fetch and push, and the tool only repairs a clone made before the helper existed.

A session that attached nothing gets exactly four tools: `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step`. Every other tool, including all `board_*`, `chat_*`, `coder_*`, `azure_devops_*`, `tracker_*`, `share_asset`, `promote_asset` and `refresh_github_token`, is served only when attached.

`finish_session` and `fail_session`: remove the `session.mode == "non_interactive"` refusal in their handlers (`app/services/internal_tools/{finish,fail}_session.rb`) and update their descriptions. `Sessions::Lifecycle.finish` already ends an interactive session through the same path as the Finish button; the implementation verifies that `fail_session` in an interactive session reaches `Sessions::Lifecycle.fail` with the same result, and that `finish_session` writes the step note only when a step run exists (it already guards on `step_run.present?`).

### 2.2 Mechanism

The `inject_when` DSL and `Tools::InjectionRules` stay. The plumbing decision is the `inject_when` lines of the tools that stay automatic (D2): there is no second list.

Rules after the change:

| Rule | Tools |
|---|---|
| `any_session` (new, always true) | `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step` |
| `container_tools_present` | `read_tool_result` |
| `config_items_attached` | `get_config_item` |

Deleted in this change, with their `inject_when` lines: `workflow_step_session`, `coder_integration_connected`, `azure_integration_connected`, `azure_repositories_attached`, `tracker_run`, `github_repositories_attached`, `non_interactive_session`. There is no legacy set and no flag.

`TerminalSession#available_tools` becomes: attached tools (tenant-owned, enabled, not deleted) plus tools whose rules match. The `Tool.for_project(project)` fallback (`base.none?(&:db_source?)`) is deleted, and the method comment says so.

Alternatives considered:
- **A per-tool `plumbing true` flag replacing `inject_when`.** Rejected: the conditions differ per tool (container tools present, config items attached), so the predicates would move without being removed.
- **Keep injection, gate on a workflow setting such as "allow integration tools".** Rejected: a switch that grants a group of tools is the same ambient grant under another name.
- **A separate `Tools::Plumbing::NAMES` list with a class-load check.** Rejected (D2): a second list to keep in step with the `inject_when` lines. The static test (§6) pins the names instead.

### 2.3 Attaching what used to be injected

- **Azure DevOps (17 tools).** Set `user_attachable true` (remove `user_attachable false`) and make `:azure_devops` `ui_visible: true` in `Tools::TagCatalog`, with the comment explaining the old "injected, not picked" choice removed. The picker shows one **Azure DevOps** section. The `requires_integration :azure_devops` gate still hides the section until the connection exists. Repository tools still refuse a call for a repository that is not attached to the session (`AzureDevopsContext`); attaching a repository does not attach the tools, and attaching the tools does not attach a repository. `Tools::RegistryTest` currently asserts "Azure tools must not be offered in the picker" and must be rewritten (§6).
- **Coder, board, chat, tracker, assets.** Already `user_attachable` and in visible tag groups. No change.
- **`share_asset`, `promote_asset`** are tagged `:assets`, a visible group. No change.
- **Custom (`db`) tools.** Already attachable. Only the fallback goes.
- **API and MCP.** `tool_ids` / `base_tool_ids` on workflow and step endpoints, `PersonalTools::{Create,Update}Workflow*`, and `validate_workflow` already resolve against `Tool.visible_for_project`, which filters `user_attachable: true`. Making the Azure tools attachable is therefore the whole change there. `list_project_tools` returns them with no change. Update its description and `Tools::PersonalMCPGuides` text ("the platform injects those automatically", line ~443) and `ContextBuilders::AixleBuilder` to say plumbing only is automatic and every other tool, including board and chat, must be attached.
- **Picker UI.** `ToolPicker` renders groups from `Registry.ui_groups` / `PickerGroups`, so the Azure section appears with no frontend code. Add one frontend test for the section (§6).

### 2.4 `inherit_all_project_resources` stays

A workflow with `inherit_all_project_resources` already gets every `Tool.visible_for_project` tool (`SessionConfigResolver#project_tool_ids`). This is a workflow-level opt-in shown in the builder, so it counts as an attachment by the workflow, and this design leaves it unchanged (D5, accepted). The migration skips those workflows' platform links: they already reach every attachable tool (§5.2).

`refresh_github_token` and the 17 Azure DevOps tools become attachable, so they join that set. This adds no capability: the Azure DevOps tools are hidden without an Azure DevOps connection (`requires_integration`), the pull request tools refuse a repository that is not attached to the session, `refresh_github_token` acts only on attached GitHub repositories, and the two build tools were already served wherever the connection exists. Narrowing `inherit_all_project_resources` itself stays in §11.

### 2.5 No feature flag

Alex decided that the new behavior is unconditional. The earlier draft's `attached_tools_only` flag, `InjectionRules::LEGACY`, the two flag read points and the per-company backfill are not part of this design. The legacy rules, their `inject_when` lines and the fallback are deleted in this change, not in a follow-up. The safety for existing workflows comes from the migration (§5), which must run before the new code serves. Catalog templates already list their tools (§5.2).

## 3. Data Model Changes

No schema change. One data migration (§5). Tool rows already exist for every code tool through `Tools::Reconciler`; the migration reads them like `AttachPullRequestToolsToWorkflows` did.

## 4. API / Interface Changes

- No new endpoints and no new parameters.
- Behavior: MCP `tools/list` and `tools/call` for a session serve only attached tools plus plumbing. A `tools/call` on a tool that is not attached is "not entitled" (existing `Tools::MCPRequestHandler` path).
- Azure tools become visible in `GET`/MCP tool catalogs and accepted in `tool_ids`. `refresh_github_token` becomes visible and accepted too.
- Release note: workflows created through the builder, the API, the MCP tools or a template install must attach their tools. Sessions running at deploy lose injected tools (§9).

## 5. Migration of existing data

Existing workflows must keep working after the release (hard requirement, Alex). Everything an old rule served to a step becomes an explicit attachment on that step, visible in the builder and removable there (D4).

**One migration**, `db/migrate/<ts>_attach_formerly_injected_tools.rb`, for all companies. It follows `20261124112933_attach_pull_request_tools_to_workflows.rb`: self-contained inline models (`workflows`, `steps`, `workflow_resource_links`, `step_resource_links`, plus read-only models for the integration, repository and trigger-binding tables it reads), no app classes, a documented no-op `down`. It runs in the deploy's migrate phase, before the new code serves: an extra link is harmless to the old code, so the old pods keep working while it runs. There is no service object and no rake task (D10 of the previous draft is dropped). The migration is idempotent.

### 5.1 Rule

For each non-deleted, non-System workflow and each of its non-deleted steps, a tool T is attached to the **step** (`step_resource_links`) when the old rules would have served T to a session of that step (reachability). There is no evidence test: the grants are everything the old rules served, at step granularity.

| Formerly injected tool(s) | Attached to the step when |
|---|---|
| 14 `board_*`, `share_asset`, `promote_asset` | always (old `workflow_step_session`) |
| 4 `chat_*` | an active Slack or Teams integration exists for the workflow's company, company-wide or for its project (same predicate as `Tools::Context#connected_providers`; the tools are hidden otherwise through `requires_integration`) |
| 5 `coder_*` | an active Coder integration, same predicate |
| `azure_devops_list_builds`, `azure_devops_list_connections` | an active Azure DevOps integration, same predicate |
| 15 `azure_devops_*` pull request tools | the workflow's project sees an Azure DevOps repository (`Repository.visible_for_project`), for every step |
| 15 `tracker_*` | the workflow has a `trigger_bindings` row whose `event_type` starts with `TriggerBinding::TRACKER_EVENT_PREFIX`, with or without `project_tracker_id` (an unscoped binding matches any tracker of the project), enabled or not, for every step |
| `refresh_github_token` | the workflow's project sees a GitHub repository (`Repository.visible_for_project`), for every step |

Not migrated, because still plumbing: `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step`, `read_tool_result`, `get_config_item`.

**Repositories chosen at run start.** The Run form can give a run repositories that the workflow does not list (`workflow_run.repository_ids`), and the migration cannot see them. The two repository rows therefore use project visibility, not the step's repository list. This over-grants a step in a project that has such a repository and adds no capability, because these tools act only on repositories attached to the session (Alex's review decision).

**Custom-tool fallback.** A step whose resolved tool set holds no custom (`db`) tool, and whose workflow is not under `inherit_all_project_resources`, gets every enabled custom tool of its project.

**`inherit_all_project_resources` workflows** already reach every attachable tool, so the migration adds no platform links to them (§2.4).

**Idempotent.** A link that exists is not added again. Tools with no `tools` row (`source = 'code'`) are skipped, as in the precedent.

**Output.** One summary line per run: counts of links added per tool name and number of workflows touched. No workflow, project or customer names. The migration keeps its own copy of the old predicates, because they are deleted from the app. It has no automated test and is checked by hand (§6.7).

### 5.2 Templates and workflows created through API / MCP

- **Installed templates and workflows made through the API, builder or MCP tools** are rows in `workflows`/`steps` by the time the migration runs, so §5.1 covers them. This includes workflows installed from a template before the release: they get every formerly injected tool on every step from the migration. A new install gets only the template's list. Accepted (Alex).
- **Catalog templates need no change and there is no templates pull request** (Alex). A template already says which tools each step gets: a workflow's `base.tools` apply to every step and a step's `tools:` apply to that step. `Templates::Installer` turns them into `base_tool_ids` and `tool_ids`, the same attachments the builder sets. After this change a template's step gets exactly what is listed.
- **Checked against `flow-templates` `main`:** all six packages, 58 steps. Every board, chat, asset, Coder, tracker or Azure tool named in a step's text, sub-steps, agent or skills is listed on the step or its workflow. The only unlisted names appear in prohibitions ("Do not call `promote_asset`", "You do not have `board_move_task`"). Steps that list no board tools say "never call board tools". No package has a tracker trigger or uses Coder or Azure, so no template relied on those rules.
- Add to `Templates::RepositoryValidator` (flow) a **warning** (not an error) when a step's text names a platform tool the step does not list. The check is a case-insensitive match of tool names and `{{tool:<id>}}` references in step, sub-step and agent instructions. It may also warn on a prohibition that names a tool; that is acceptable for a warning. This is in the flow pull request.
- `flow-templates` is detached from the Tech Design, Implementation, Fix Tests, Fix Review, Code Review and Release workflows. The task has one pull request, and the release order has no templates step.

## 6. Testing Approach

Tests follow `docs/testing.md`; model and service tests under `test/`, one frontend test. There is no flag, so no test switches a mode.

Automated tests cover the new behavior only: items 1 to 6 and 8 to 9. There is no oracle and no equivalence test.
1. **The guard (new, `test/services/tools/plumbing_test.rb`).**
   - Static: the names of the definitions in `Tools::Registry.definitions` that have any `inject_when` rule are exactly `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step`, `read_tool_result`, `get_config_item`.
   - Dynamic, in a project with every integration connected (Coder, Azure DevOps, Slack, Teams, GitHub, a usable tracker), a tracker-started run, an attached Azure repository, an attached GitHub repository and custom tools in the project: for a workflow-step session, a non-interactive agent session and an interactive agent session that attach nothing, `available_tools` is exactly the four unconditional plumbing names. With a config item attached it adds `get_config_item`, with a container tool `read_tool_result`, and nothing else. This is the acceptance test, and it fails when a rule grants a tool.
   - A session that attaches tool X gets X and no other non-plumbing tool.
2. **`DefinitionDSLTest` / `InjectionRules`:** the deleted rules are gone from `RULES`; each remaining rule has a test.
3. **Rewrite** `TerminalSessionAvailableToolsTest`: each case that asserted injection (`board_*`/`chat_post_message` for workflow steps, Coder, Azure, tracker run, `refresh_github_token`, the custom-tool fallback) now asserts the tool is not served without an attachment and is served with one. Keep the plumbing cases (`finish_session`/`fail_session` now in interactive sessions too, `get_config_item`, `read_tool_result`).
4. **Rewrite** `Tools::RegistryTest` (`injectable covers…`; `grouping axes` counts; "Azure tools must not be offered in the picker" becomes the opposite, 17 attachable tools) and `TagCatalogTest`/`PickerGroupsTest` (Azure DevOps group visible). Add `user_attachable` for `refresh_github_token`.
5. **Handlers:** `finish_session`/`fail_session` tests drop the "only non-interactive" refusal case and cover an interactive session.
6. **MCP:** `McpControllerTest` / `Tools::MCPRequestHandler`: `tools/list` of a Coder-connected project's session without attached Coder tools lists no `coder_*`; `tools/call coder_ssh_exec` is refused as not entitled.
7. **Migration: no automated test** (Alex). This includes the small cases (running twice, a System workflow, an unreachable step). It is checked by hand, in two places: on staging after Staging Deployment, and on a stack brought up on a Coder workspace.
   - **Before the migration runs**, set up one workflow per kind of step in §5.1, with the integration or repository that kind needs: a plain step (board and asset tools), a chat-triggered one (Slack or Teams connected), one in a Coder-connected project, one with an Azure DevOps repository, one with a tracker trigger binding for a specific tracker, one with a tracker trigger binding for any tracker of the project, one with no repositories that is run with an Azure DevOps repository picked in the Run form, one with a GitHub repository, one in a project with enabled custom tools and none attached, one with a custom tool attached, and one under `inherit_all_project_resources`. Write down each step's served tool names with the old code (the session's tool list in the builder or `tools/list`).
   - **After the migration**, check for each step that the formerly injected tools are attachments visible in the builder, that a step with a custom tool attached got no extra custom tools, that a System workflow has no new links, and that a run of each workflow still does its work (comments, moves the card, calls Coder or Azure, answers in chat).
   - **AI Builder case (staging).** Build a small workflow through the AI Builder whose step comments on its board task and moves it. Check that the builder attached the board tools the step needs, and that a run comments and moves the card (Alex).
8. **Existing tests that rely on injection** (`get_config_item_test`, `pull_request_tools_test`, `internal_tools/*_test`, `personal_mcp_test`, `integration/mcp_controller_test`): update them to attach the tool in setup. Find them with `rg "session_type: \"workflow_step\"|available_tools"` under `test/`.
9. **Frontend:** `ToolPicker.test.tsx`: the Azure DevOps section renders when the project has the connection.
10. **Validator:** a `Templates::RepositoryValidator` test for the new warning (a step names an unlisted tool; a listed one gives none).

## 7. Implementation Steps

Flow pull request:
1. Rules: add `any_session`, delete the seven rules in §2.2 and their `inject_when` lines in all tool files; switch `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step` to `any_session` (`app/services/tools/injection_rules.rb`, `app/services/internal_tools/*.rb`, the tool classes of the removed rules).
2. `TerminalSession#available_tools`: delete the fallback; update the method comment.
3. `finish_session` / `fail_session`: drop the interactive refusal and fix descriptions.
4. Azure tools and `refresh_github_token`: `user_attachable` on; `TagCatalog` Azure entry visible with a new comment (§2.3).
5. The migration (§5).
6. `Templates::RepositoryValidator` warning (§5.2).
7. Tests (§6).
8. Builder and MCP text that assumes a tool arrives by itself (`rg -n "inject|automatically|NOT mounted" app/services/context_builders app/services/tools app/services/personal_tools` finds any more). The replacement says: only the plumbing tools are automatic; the board, chat, tracker, Coder and Azure tools a step uses must be attached to that step, or to the workflow base when every step uses them. Concrete places:
   - `ContextBuilders::AixleBuilder`, "How a step gets what it needs": "Files attached to a board task are NOT mounted — the step agent reads them with its board tools" becomes "... with board tools attached to the step (`board_get_task_assets`)".
   - `ContextBuilders::AixleBuilder`, trigger guidance: "Moving the issue on is the workflow's job, with the tracker_* tools" gains "attach the tracker tools the step needs; a tracker trigger does not grant them". The same applies to the chat trigger paragraph (attach `chat_post_message` for a reply).
   - `Tools::PersonalMCPGuides#author_step`: "Do NOT restate … which tools are available. The platform injects those automatically" becomes "Do NOT restate … sub-step tracking. Session completion, sub-step tools and file layout are automatic; every other tool must be attached, so do not list tools in the instructions but attach them to the step".
   - `PersonalTools::ListProjectTools` description: says tools returned are the ones to attach, and that board, chat, tracker, Coder and Azure tools are never served otherwise.
   - The builder's own tools (`Tools::BuilderToolset`, personal MCP tools pinned to the project) are untouched.
9. Docs (§8), `CHANGELOG.md` entry and release note.

**Release:** one pull request. The migration runs in the deploy's migrate phase before the new code serves. Staging Deployment runs the manual checks of §6.7.

## 8. Docs to change

- `docs/design/tool-execution.md`: §9 "Adding a New Tool" says what `inject_when` is for (plumbing only) and links this document.
- `docs/project/context.md`: the **Workflow Tool** glossary row and the "Auto-injected internal tools" and "Integration-gated tools" bullets (lines ~459–469): only plumbing is automatic; `requires_integration` only hides a tool until the integration exists. 
- `docs/architecture/workflows.md`: internal tools section (~727–745) and the `share_asset` mention (~1041).
- `docs/user-guide/mcp.md` line 25 (progress tools stay automatic; board tools do not), `docs/user-guide/workflows.md` (attach tools to steps).
- Integration designs that rely on injection, each gets a note pointing here: `azure-devops-integration.md` (§ "injected, not picked", ~368–381), `task-tracker-integrations.md` §7.3, `teams-integration.md` (~772). `github-user-identity.md` D8 needs no change.
- In-app docs under `app/frontend/pages/Docs/data/pages/`: `trackers.md` ("A run a tracker event started has all of them", ~377), `coder.md` (the project "has the `coder_*` tools", line 5, and the picker group, line 81), `azure-devops.md` (tools are attached).

## 9. Edge Cases & Risks

- **Sessions in flight at deploy.** Running sessions lose the injected tools once the new code serves them (the implementation checks whether a session's tool list is fixed at creation or resolved per call, and states the result in the pull request). Accepted (Alex, D8), with no compatibility layer.
- **Window between the migration and the new code.** A workflow created by an old pod in that window relies on injection and gets no links. The window is the length of a rolling deploy. Accepted, no mitigation; the builder shows the missing tools and they can be attached.
- **AI Builder session.** It is an interactive agent session flagged `metadata.aixle_builder`, not a run of the System workflow, so the migration skips it. It stops getting `coder_*`, the two Azure tools and every custom tool of the project without an attachment, and gets the plumbing tools. Accepted (Alex).
- **Over-grant by migration.** Attaching everything the old rules served gives each step more tools than it may use. That is today's access, now explicit, visible and removable in the builder (D4). It is not a regression.
- **Standalone sessions** (personal, API) carry their tool list in the creation request and persist no template, so nothing is migrated for them. People who relied on injection attach tools in the session form.
- **Tool without a shadow row.** The migration skips tools with no `tools` row; the reconciler creates rows at boot and on first use, so a fresh install has nothing to migrate.
- **Chat reply path.** A chat-triggered run answers through `chat_post_message`. The migration attaches `chat_*` to every reachable step, so the reply path survives.
- **Interactive `finish_session`.** An agent can now end an interactive session by itself. This is the requested behavior; verify the session-end path in §2.1.
- **`inherit_all_project_resources`** remains an ambient grant of every attachable platform tool (D5).
- **Templates installed before the release** carry every formerly injected tool on every step; later installs carry only the template's list (§5.2).
- **Security regression.** The §6.1 dynamic test is the control: a rule that serves a non-plumbing tool fails CI.

## 10. Decisions & Assumptions

| ID | Decision | Source |
|---|---|---|
| D1 | Plumbing is six tools: `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step` for every session, `read_tool_result` and `get_config_item` only with an attachment. `refresh_github_token` is attachable and not plumbing. | Alex's review decision |
| D2 | The `inject_when` mechanism stays and is the only plumbing list; no `Plumbing::NAMES`. A static test compares the names to the six. | Alex's review decision |
| D3 | Azure tools become attachable and visible; picker section gated by `requires_integration`. | Task: "The Azure tools are hidden from the picker today" |
| D4 | Migration attaches every tool the old rules would have served to the step (reachability only), including the custom-tool fallback. Granularity is the step. | Alex's review decision |
| D5 | `inherit_all_project_resources` is an explicit workflow-level attachment and is unchanged. | Alex's review decision |
| D6 | No templates pull request: the six packages already list the tools their steps use (checked against `flow-templates` `main`). The validator warning stays. | Alex's review decision |
| D7 | No production identifiers appear in this document, the migration output or the PR. | Alex's task decision |
| D8 | Sessions running at deploy lose injected tools; no compatibility layer. | Alex's review decision |
| D9 | No feature flag: the new behavior is unconditional, and the legacy rules and fallback are deleted in this change. | Alex's review decision |
| D11 | No automated migration test and no oracle; the migration is checked by hand on staging and on a Coder stack (§6.7). | Alex's review decision |
| D12 | The AI Builder session loses its un-attached tools and gets plumbing only; builder and guide text changes as in §7 item 8. A QA case covers it. | Alex's review decision |
| D10 | One migration at deploy attaches the formerly injected tools; no rake task and no backfill service. | Alex's review decision |

## 11. Deferred Questions

- **Should `inherit_all_project_resources` stop covering platform tools?** It is the last ambient path. Narrowing it needs its own migration and a product decision on what "inherit all" means. Deferred to a follow-up task.
- **A recorded call log for app tools** would let a later cleanup trim the migrated grants to what is used. Out of scope.
- **Per-tool permission levels** (read versus write board tools in the picker). Not asked for.
