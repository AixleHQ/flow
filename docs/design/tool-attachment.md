# Tool Attachment: a session gets only the tools attached to it

**Status:** Design (task #290), updated with the decisions of 2026-11-26 (no feature flag, one migration, templates pull request)
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
2. removes every other grant, including the fallback, unconditionally (no feature flag, §2.5);
3. migrates existing workflows with one data migration, so each step keeps every tool the old rules served, attached explicitly;
4. makes every formerly injected tool attachable in the pickers, the API and the MCP tools;
5. adds a test that fails when a non-plumbing tool reaches a session that did not attach it.

## 2. Approach

### 2.1 Plumbing list

Plumbing is a tool a session needs to work at all, or one that follows an attachment and grants no capability the attachment did not already grant. Alex settled it (task comments 115113 and 115133).

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

`refresh_github_token` becomes attachable, so it joins that set.

### 2.5 No feature flag

Alex decided (comment 115244) that the new behavior is unconditional. The earlier draft's `attached_tools_only` flag, `InjectionRules::LEGACY`, the two flag read points and the per-company backfill are not part of this design. The legacy rules, their `inject_when` lines and the fallback are deleted in this change, not in a follow-up. The safety for existing workflows comes from the migration (§5), which must run before the new code serves, and from the templates pull request (§5.2), which must be merged before the release.

## 3. Data Model Changes

No schema change. One data migration (§5). Tool rows already exist for every code tool through `Tools::Reconciler`; the migration reads them like `AttachPullRequestToolsToWorkflows` did.

## 4. API / Interface Changes

- No new endpoints and no new parameters.
- Behavior: MCP `tools/list` and `tools/call` for a session serve only attached tools plus plumbing. A `tools/call` on a tool that is not attached is "not entitled" (existing `Tools::MCPRequestHandler` path).
- Azure tools become visible in `GET`/MCP tool catalogs and accepted in `tool_ids`. `refresh_github_token` becomes visible and accepted too.
- Release note: workflows created through the builder, the API, the MCP tools or a template install must attach their tools. Sessions running at deploy lose injected tools (§9).

## 5. Migration of existing data

Existing workflows must keep working after the release (hard requirement, Alex 2026-11-26). Everything an old rule served to a step becomes an explicit attachment on that step, visible in the builder and removable there (D4).

**One migration**, `db/migrate/<ts>_attach_formerly_injected_tools.rb`, for all companies. It follows `20261124112933_attach_pull_request_tools_to_workflows.rb`: self-contained inline models (`workflows`, `steps`, `workflow_resource_links`, `step_resource_links`, plus read-only models for the integration, repository and trigger-binding tables it reads), no app classes, a documented no-op `down`. It runs in the deploy's migrate phase, before the new code serves: an extra link is harmless to the old code, so the old pods keep working while it runs. There is no service object and no rake task (D10 of the previous draft is dropped). The migration is idempotent.

### 5.1 Rule

For each non-deleted, non-System workflow and each of its non-deleted steps, a tool T is attached to the **step** (`step_resource_links`) when the old rules would have served T to a session of that step (reachability). There is no evidence test: the grants are everything the old rules served, at step granularity.

| Formerly injected tool(s) | Attached to the step when |
|---|---|
| 14 `board_*`, `share_asset`, `promote_asset` | always (old `workflow_step_session`) |
| 4 `chat_*` | an active Slack or Teams integration exists for the workflow's company, company-wide or for its project (same predicate as `Tools::Context#connected_providers`; the tools are hidden otherwise through `requires_integration`) |
| 5 `coder_*` | an active Coder integration, same predicate |
| `azure_devops_list_builds`, `azure_devops_list_connections` | an active Azure DevOps integration, same predicate |
| 15 `azure_devops_*` pull request tools | the step's resolved repositories (workflow base plus step, or every project repository under `inherit_all_project_resources`) include one whose integration provider is `azure_devops` |
| 15 `tracker_*` | the workflow has a `trigger_bindings` row with a `project_tracker_id` (the only way a tracker event starts a run) |
| `refresh_github_token` | the step's resolved repositories include a GitHub one |

Not migrated, because still plumbing: `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step`, `read_tool_result`, `get_config_item`.

**Custom-tool fallback.** A step whose resolved tool set holds no custom (`db`) tool, and whose workflow is not under `inherit_all_project_resources`, gets every enabled custom tool of its project.

**`inherit_all_project_resources` workflows** already reach every attachable tool, so the migration adds no platform links to them (they also get the newly attachable Azure and `refresh_github_token` tools by that path, as for any attachable tool).

**Idempotent.** A link that exists is not added again. Tools with no `tools` row (`source = 'code'`) are skipped, as in the precedent.

**Output.** One summary line per run: counts of links added per tool name and number of workflows touched. No workflow, project or customer names. The migration keeps its own copy of the old predicates (they are deleted from the app), which is why it is tested against a test-only oracle (§6.7).

### 5.2 Templates and workflows created through API / MCP

- **Installed templates and workflows made through the API, builder or MCP tools** are rows in `workflows`/`steps` by the time the migration runs, so §5.1 covers them.
- **Catalog templates** are package files in `AixleHQ/flow-templates` (`templates/aixle/<slug>/template.yaml`), which `Templates::RepositoryClient` syncs from `main` into every installation, and `Templates::CatalogSync` turns into `catalog_templates.definition`. A package names platform tools in a top-level `tools:` list (`key`, `platform`) and in each step's `tools:` list. A template installed after the release that lists no platform tools would install a workflow with no tools, because the migration has run already.
- **The templates change is a second pull request in this task** (D6, Alex 2026-11-26, comment 115147), opened by the implementation developer against `AixleHQ/flow-templates` `main`. Scope:
  - For each of the six packages (`cve-scan-daily`, `dev-pipeline`, `ga4-weekly-report`, `hello-flow`, `prd-discovery`, `security-audit`), compare every step's text, sub-step text and agent instructions with its `tools:` list. Add a top-level `platform` entry and a step-level reference for each board, chat, Coder, tracker, asset or Azure tool the step uses and does not list. Do not add a tool the step does not use. Most packages already list board and asset tools; `ga4-weekly-report` and `prd-discovery` list only one or two, so expect gaps there.
  - Increase each changed package's `version` by one (`CONTRIBUTING.md` rule 4) and run `bin/validate`.
  - **Flow version check.** `Templates::Planner#resolve_platform_tools!` looks platform tools up by name among the code tools, with no integration check, so a package that lists Coder tools still installs where Coder is not connected. A package that names a tool that an older supported Flow version lacks becomes `NotInstallable` there. The template format has no required-Flow-version field, so the developer checks that every name added exists in `Tools::Registry` on the oldest supported release, and does not add a tool introduced after it. All tool names in the task's list exist today, so no new name is expected to fail.
- **Two pull requests.** The task description lists both, one line each: `**Pull request:** <flow url>` and `**Pull request (templates):** <flow-templates url>`. Code Review, Fix Tests and Fix Review cover both.
- **Merge order.** `flow-templates` has no staging branch, and a merge to `main` is a release of the catalog to every installation, production included. Staging Deployment never merges the templates pull request. Release merges it **before** the flow pull request. Merging it earlier is safe: a package that lists platform tools works on the current platform too.
- Add to `Templates::RepositoryValidator` (flow) a **warning** (not an error) when a step's text names a platform tool the step does not list. The check is a case-insensitive match of tool names and `{{tool:<id>}}` references in step, sub-step and agent instructions. This is in the flow pull request.

## 6. Testing Approach

Tests follow `docs/testing.md`; model and service tests under `test/`, one frontend test. There is no flag, so no test switches a mode.

1. **The guard (new, `test/services/tools/plumbing_test.rb`).**
   - Static: the names of the definitions in `Tools::Registry.definitions` that have any `inject_when` rule are exactly `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step`, `read_tool_result`, `get_config_item`.
   - Dynamic, in a project with every integration connected (Coder, Azure DevOps, Slack, Teams, GitHub, a usable tracker), a tracker-started run, an attached Azure repository, an attached GitHub repository and custom tools in the project: for a workflow-step session, a non-interactive agent session and an interactive agent session that attach nothing, `available_tools` is exactly the four unconditional plumbing names. With a config item attached it adds `get_config_item`, with a container tool `read_tool_result`, and nothing else. This is the acceptance test, and it fails when a rule grants a tool.
   - A session that attaches tool X gets X and no other non-plumbing tool.
2. **`DefinitionDSLTest` / `InjectionRules`:** the deleted rules are gone from `RULES`; each remaining rule has a test.
3. **Rewrite** `TerminalSessionAvailableToolsTest`: each case that asserted injection (`board_*`/`chat_post_message` for workflow steps, Coder, Azure, tracker run, `refresh_github_token`, the custom-tool fallback) now asserts the tool is not served without an attachment and is served with one. Keep the plumbing cases (`finish_session`/`fail_session` now in interactive sessions too, `get_config_item`, `read_tool_result`).
4. **Rewrite** `Tools::RegistryTest` (`injectable covers…`; `grouping axes` counts; "Azure tools must not be offered in the picker" becomes the opposite, 17 attachable tools) and `TagCatalogTest`/`PickerGroupsTest` (Azure DevOps group visible). Add `user_attachable` for `refresh_github_token`.
5. **Handlers:** `finish_session`/`fail_session` tests drop the "only non-interactive" refusal case and cover an interactive session.
6. **MCP:** `McpControllerTest` / `Tools::MCPRequestHandler`: `tools/list` of a Coder-connected project's session without attached Coder tools lists no `coder_*`; `tools/call coder_ssh_exec` is refused as not entitled.
7. **Migration (acceptance proof).** `test/migrations/` if the suite has the convention, else a test that loads the migration class and runs `up`.
   - **Equivalence test.** A test-only oracle (`test/support/legacy_injection_oracle.rb`) encodes the old rules and the fallback as they were before this change. On fixtures covering each row of §5.1 (a workflow with a Coder integration, one with an Azure repository, one tracker-bound, one with a GitHub repository, one with no custom tool, one with a custom tool attached, one under `inherit_all_project_resources`), the oracle computes the tool names each step session would have been served. After `up`, the new `available_tools` names of the same step sessions equal that set. This is the proof that existing workflows keep working.
   - A step that is not reachable gets nothing; a System workflow is untouched; running twice adds no duplicate link.
8. **Existing tests that rely on injection** (`get_config_item_test`, `pull_request_tools_test`, `internal_tools/*_test`, `personal_mcp_test`, `integration/mcp_controller_test`): update them to attach the tool in setup. Find them with `rg "session_type: \"workflow_step\"|available_tools"` under `test/`.
9. **Frontend:** `ToolPicker.test.tsx`: the Azure DevOps section renders when the project has the connection.
10. **Templates repository:** `bin/validate` passes for every changed package.

## 7. Implementation Steps

Flow pull request:
1. Rules: add `any_session`, delete the seven rules in §2.2 and their `inject_when` lines in all tool files; switch `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step` to `any_session` (`app/services/tools/injection_rules.rb`, `app/services/internal_tools/*.rb`, the tool classes of the removed rules).
2. `TerminalSession#available_tools`: delete the fallback; update the method comment.
3. `finish_session` / `fail_session`: drop the interactive refusal and fix descriptions.
4. Azure tools and `refresh_github_token`: `user_attachable` on; `TagCatalog` Azure entry visible with a new comment (§2.3).
5. The migration (§5).
6. `Templates::RepositoryValidator` warning (§5.2).
7. Tests (§6).
8. Builder and MCP guide text (`context_builders/aixle_builder.rb`, `tools/personal_mcp_guides.rb`, `personal_tools/list_project_tools.rb`): attach every tool the workflow needs.
9. Docs (§8), `CHANGELOG.md` entry and release note.

Templates pull request (§5.2), opened in the same task.

**Release order:** merge the templates pull request; deploy flow (the migration runs in the migrate phase before the new code serves).

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
- **Catalog installs before the templates merge.** If the flow release went first, a template installed afterwards that lists no platform tools would have no tools. The release order (templates first) prevents it.
- **Over-grant by migration.** Attaching everything the old rules served gives each step more tools than it may use. That is today's access, now explicit, visible and removable in the builder (D4). It is not a regression.
- **Standalone sessions** (personal, API) carry their tool list in the creation request and persist no template, so nothing is migrated for them. People who relied on injection attach tools in the session form.
- **Tool without a shadow row.** The migration skips tools with no `tools` row; the reconciler creates rows at boot and on first use, so a fresh install has nothing to migrate.
- **Chat reply path.** A chat-triggered run answers through `chat_post_message`. The migration attaches `chat_*` to every reachable step, so the reply path survives.
- **Interactive `finish_session`.** An agent can now end an interactive session by itself. This is the requested behavior; verify the session-end path in §2.1.
- **`inherit_all_project_resources`** remains an ambient grant of every attachable platform tool (D5).
- **Templates repository rule "one template per pull request".** `CONTRIBUTING.md` asks for one template per pull request; this task changes up to six packages in one, as Alex decided. Maintainers may ask to split it.
- **Security regression.** The §6.1 dynamic test is the control: a rule that serves a non-plumbing tool fails CI.

## 10. Decisions & Assumptions

| ID | Decision | Source |
|---|---|---|
| D1 | Plumbing is six tools: `finish_session`, `fail_session`, `list_sub_steps`, `mark_sub_step` for every session, `read_tool_result` and `get_config_item` only with an attachment. `refresh_github_token` is attachable and not plumbing. | Alex, comments 115113 and 115133 |
| D2 | The `inject_when` mechanism stays and is the only plumbing list; no `Plumbing::NAMES`. A static test compares the names to the six. | Alex, comment 115079 |
| D3 | Azure tools become attachable and visible; picker section gated by `requires_integration`. | Task: "The Azure tools are hidden from the picker today" |
| D4 | Migration attaches every tool the old rules would have served to the step (reachability only), including the custom-tool fallback. Granularity is the step. | Alex, comment 115079 |
| D5 | `inherit_all_project_resources` is an explicit workflow-level attachment and is unchanged. | Alex, comment 115079 |
| D6 | The catalog templates change is a pull request in this task against `flow-templates`, merged by Release before the flow pull request. The validator warning stays. | Alex, comments 115079 and 115147 |
| D7 | No production identifiers appear in this document, the migration output or the PR. | Alex, comment of 2026-11-25 |
| D8 | Sessions running at deploy lose injected tools; no compatibility layer. | Alex, comment 115079 |
| D9 | No feature flag: the new behavior is unconditional, and the legacy rules and fallback are deleted in this change. | Alex, comment 115244 (replaces 115133) |
| D10 | One migration at deploy attaches the formerly injected tools; no rake task and no backfill service. | Alex, comment 115244 |

## 11. Deferred Questions

- **Should `inherit_all_project_resources` stop covering platform tools?** It is the last ambient path. Narrowing it needs its own migration and a product decision on what "inherit all" means. Deferred to a follow-up task.
- **A recorded call log for app tools** would let a later cleanup trim the migrated grants to what is used. Out of scope.
- **Per-tool permission levels** (read versus write board tools in the picker). Not asked for.
