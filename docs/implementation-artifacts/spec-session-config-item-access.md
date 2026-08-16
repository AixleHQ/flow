---
title: 'Config items as an attachable session resource + `get_config_item` over the session MCP'
type: 'feature'
created: '2026-08-17'
status: 'implemented'
baseline_commit: '8af92c3e'
review_loop_iteration: 0
context:
  - '{project-root}/docs/design/session-config-and-context.md'
  - '{project-root}/docs/research/technical-agent-session-log-access-and-control-research-2026-08-10.md'
  - '{project-root}/docs/implementation-artifacts/spec-session-observability-mcp-tools.md'
  - '{project-root}/docs/testing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A `ConfigItem` can reach a container through exactly two channels today, and neither
serves an agent session:

1. MCP server `env`/`headers`, via a `config_item:NAME` reference resolved in
   `SessionContextService#resolve_embedded_references` (`session_context_service.rb:429`).
2. A custom tool's container env, via `Tool#required_config_items`
   (`custom_tool_strategy.rb:92-111`).

Both exist because their consumer is a *process that cannot ask* — a spawned stdio MCP server, or a
user script inside a tool container. Neither gives an **agent** a credential it needs mid-session.

A third channel was written and never wired: `session_config["env_vars"]` with `config_item:NAME`
resolution (`session_context_service.rb:191`, `terminal_session.rb:155`). It shipped in `4179ec1f`
(2026-02-21) as one of a batch of sibling injectors (config files, env vars, MCP config, skills,
context file). Every sibling acquired a writer; this one did not. No controller ever permitted it —
`git log -S 'env_vars:' -- app/controllers` is empty across all branches — and
`SessionConfigResolver` does not know the key exists. It is dead code, with zero users to migrate.

The consequence in the product: there is no way to hand a session a credential, and no picker for
config items on **any** screen — not session start, not workflow base resources, not the step editor.
Teams have started pasting secrets into workflow step instructions, where they are stored in plaintext,
copied by `WorkflowDuplicator`, and rendered into every context file.

**Approach:** Two halves.

1. **`ConfigItem` becomes a first-class attachable resource**, alongside tools / skills / MCP servers /
   assets / repositories, at all three cascade levels (session, workflow base, step) with the same
   additive resolution and the same `inherit_all_project_resources` behaviour.
2. **One session-MCP tool, `get_config_item`**, that returns a decrypted value *only* for items
   attached to the calling session. Delivery is MCP-only: no env injection, no file drop. The dead
   `env_vars` path is deleted in the same change so there is never a second apparent channel.

Because the value enters the model context, it necessarily reaches every log sink downstream of the
context. A redaction pipeline over the persisted sinks is therefore part of the feature, not a
follow-up — together with an explicit, documented statement of the one sink it cannot reach.

## Boundaries & Constraints

**Always:**

- **Attachment gates on project access only.** Any member who can reach the project can attach any of
  its config items, secret or variable — `Web::Company::Projects::ConfigItemsPolicy#index?`. There is
  no separate right to attach a secret. (Product decision, 2026-08-17.) The consequence is explicit and
  accepted: anyone who can start a session in a project can read any secret in that project. The
  project **is** the trust boundary, which is precisely why the audit trail below is mandatory and not
  optional.
- **`get_config_item` resolves against the attached set, never the project.** The candidate set is
  `SessionConfigResolver#resolve_config_item_ids` for the calling session. Never
  `ConfigItem.effective_for_project` and never `project.config_items` — those turn the tool into a
  general-purpose decryptor for the whole project and erase the audit meaning of an attachment.
- **Project scope only.** `ConfigItem.visible_for_project`. Company-scoped items were removed in
  `20260724000001_restrict_resource_scopes_to_project` and stay removed.
- **Inherit like every other resource.** Additive cascade — project (`inherit_all_project_resources`) +
  workflow base + step — mirroring `SessionConfigResolver#resolve_tool_ids` (`:118`). Config items are
  *not* modelled on repositories (explicit-pick-wins).
- **Every successful fetch writes an audit row**, carrying session, config item, actor and timestamp,
  and **never the value**. This is the only record that a secret left the vault.
- **Redact secret values from every persisted sink before it is stored or served** (see the sink table
  in Design Notes). One redactor, built from the session's attached `secret` items, applied at
  `SessionLog` creation and at live-log read.
- **Names and metadata are public within the project; values are not.** Pickers, Inertia props and
  resources carry `id`/`name`/`item_type`/`description` only. `ConfigItemResource` keeps emitting
  `display_value` (the mask).
- **Delete the dead env path** (`SessionContextService.resolve_env_vars`, `TerminalSession#env_vars`,
  the `env_vars` key in `TerminalSessionResource`) in this change. Leaving it in place presents a
  second, apparently legitimate channel that this spec has decided against.
- Tests follow `docs/testing.md`: the container seam is `stub_container_runtime` +
  `ContainerRuntime::FakeRuntime`; no `any_instance`; never stub the class under test.

**Ask First:**

- Any delivery of a secret value that is not the MCP tool result — container env, a file written into
  the container, a context-file section containing values. All three were considered and rejected for
  v1 (see Design Notes).
- Restoring company-scoped config items.
- Suppressing the `> /proc/1/fd/1` sink in `docker/base/entrypoint.sh:123` for secret-bearing sessions.
  Deferred by product decision on 2026-08-17 — losing cluster-side visibility of a session's log is
  worse than the leak it would close.
- Raising the returned-value size cap, or returning more than one item per call.

**Never:**

- Never return a value for a config item that is not attached to the calling session — not even to the
  item's own author, not even with an explicit `project_id`.
- Never write a value to `Rails.logger`, to the audit row, to `ToolResult`, to `session.metadata`, or to
  `context_metadata`. `get_config_item` is an `app` execution-mode tool precisely so no `ToolResult`
  row is created (`CallExecutor.execute:15-40`).
- Never expose a decrypted value through an Inertia prop, an Alba resource, or a picker payload.
- Never surface `get_config_item` in the tool picker (`user_attachable false`) or serve it to a session
  with no attached config items — the tool exists only where an attachment already authorized it.
- Never state, in the UI or in docs, that an attached secret stays out of logs. It stays out of the
  *persisted* logs this feature redacts. It does not stay out of pod stdout, and it is fully visible in
  the live terminal to anyone who may watch the session. (The picker says nothing about exposure at
  all — see the 2026-08-17 change-log entry. Silence is fine; a false reassurance is not.)

## I/O & Edge-Case Matrix

### `get_config_item`

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Attached variable | `name: "API_BASE"`, item attached, `item_type: variable` | plaintext value + `item_type` | — |
| Attached secret | `name: "STRIPE_KEY"`, attached, `item_type: secret` | decrypted value + a one-line warning that the value is visible in this session's live terminal | audit row written before the value is returned |
| Not attached, exists in project | item exists, not in the resolved set | in-band error naming the item and how to attach it; **no** value | never distinguishable in wording from "does not exist"? — it is: the item is nameable because names are project-public |
| Unknown name | no such item in project | in-band error "Config item NAME is not available to this session" | — |
| Rotated/failed decryption | `decrypted_value` returns `nil` (`config_item.rb:118`) | in-band error naming the item and pointing at the key-rotation state | never an empty string, which reads as a legitimately empty secret |
| Session has no attached items | resolved set empty | tool is not served at all (`inject_when :config_items_attached`) | a `tools/call` on it falls through to the protocol's not-found |
| Case | `name: "stripe_key"` | matches — `ConfigItem#name=` upcases on write, so lookups upcase too | — |
| Value over the size cap | value > `MAX_VALUE_BYTES` | in-band error; a multi-megabyte "secret" is a misuse of the store | — |
| Workflow step session | attached via workflow base or step | same behaviour; the resolved set comes from the cascade | — |

### Attachment surfaces

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Session start | picker on `SessionNewForm` | `config_item_ids` persisted through the join table | ids outside the project are rejected by the controller scope |
| Workflow base | `BaseResourcesTab` | `workflow.config["base_config_item_ids"]` | — |
| Step | `SessionEditorPanel` | `steps.config_item_ids` jsonb | — |
| `inherit_all_project_resources` on | workflow flag set | every project config item joins the resolved set | — |
| Item deleted after attachment | id present, row gone | skipped with a warning, exactly as `resolve_skills` does (`session_context_service.rb:457`) | never a hard failure at session start |
| Workflow copied between projects | `WorkflowDuplicator` | attachment ids are **not** carried over unless the target project has an item of the same name — resolve by name, drop what is missing, and report it | never copy a `ConfigItem` row |

### Redaction

| Scenario | Input / State | Expected Output |
|---|---|---|
| Secret printed in the agent pane | value appears in `/tmp/terminal_output.log` | the stored `SessionLog` carries the fingerprint form, not the bytes |
| Secret in an LLM request body | value in `/var/log/mitm/http.log` | same |
| Live tail | `LiveLogReader#tail`, `PersonalTools::GetSessionLog` | redacted before it leaves the process |
| Short secret | value shorter than `ContextLog::MIN_REDACT_LEN` (6) | still redacted — the length floor exists to avoid masking `"json"`/`"true"` in the context log and must not apply to a known config-item value |
| Value that is a substring of another | two attached secrets, one a prefix of the other | longest-first replacement, as `ContextLog#scrub_secrets` already does (`:85-90`) |
| No attached secrets | session with only variables | redactor is a no-op; no cost on the collection path |

</frozen-after-approval>

## Code Map

**New**

- `db/migrate/*_create_session_config_items.rb` — HABTM join, mirroring `session_mcp_servers`
- `db/migrate/*_add_config_item_ids_to_steps.rb` — `jsonb, default: [], null: false`
- `app/services/internal_tools/get_config_item.rb` — `audience :session`, `read_only`,
  `user_attachable false`, `inject_when :config_items_attached`
- `app/services/sessions/secret_redactor.rb` — builds the value set from a session's attached `secret`
  items; wraps the fingerprint substitution extracted from `ContextLog#scrub_secrets`
- `app/models/config_item_access.rb` + migration — audit rows (session, config item, user, timestamp;
  no value)
- `app/services/context_builders/config_items.rb` — an `<available-config-items>` section listing name,
  type and description, and telling the agent to call `get_config_item`
- Tests: `test/services/internal_tools/get_config_item_test.rb`,
  `test/services/sessions/secret_redactor_test.rb`, plus the resolver/controller/frontend tests named
  in Tasks

**Changed — cascade & resolution**

- `app/models/terminal_session.rb:28-32` — `has_and_belongs_to_many :config_items`
- `app/models/terminal_session.rb:155` — **delete** `#env_vars`
- `app/models/step.rb` — `config_item_ids` accessor semantics alongside `mcp_server_ids`
- `app/models/workflow.rb:16-17, :92` — `base_config_item_ids` in `CONFIG_KEYS` + reader
- `app/services/session_config_resolver.rb:25, :138-146, :201-220` — `resolve_config_item_ids` +
  breakdown entry
- `app/services/session_context_service.rb:191-208` — **delete** `resolve_env_vars`;
  `:116` — feed attached secret values into `ContextLog#redact`
- `app/services/container_strategies/agent_session_strategy.rb:39-40` — drop the `resolve_env_vars`
  merge

**Changed — tool plumbing**

- `app/services/tools/injection_rules.rb:8` — add `config_items_attached`
- `app/services/session_context_constructor.rb:4-16` — register `ContextBuilders::ConfigItems`

**Changed — API & controllers**

- `app/controllers/api/v1/terminal_sessions_controller.rb:127` — permit `config_item_ids: []`
- `app/controllers/api/v1/projects/workflows/application_controller.rb:21` — step params
- workflows controller — `base_config_item_ids`
- `app/controllers/web/company/projects/sessions_controller.rb:24-46` — `config_items` prop
  (id/name/item_type/description only)
- workflow builder controller — same prop for base + step pickers
- `app/resources/{terminal_session,step,workflow}_resource.rb` — id attributes;
  `terminal_session_resource.rb:123-127` — drop `env_vars` from the typelized `session_config` shape;
  regenerate `app/frontend/types/generated`

**Changed — redaction sinks**

- `app/services/container_strategies/agent_session_strategy.rb:162` — redact `terminal_output.log`
  before `SessionLog.create!`
- `app/services/container_strategies/agent_session_strategy.rb:190` — redact each collected log
  (covers `http.log` and `context.log`)
- `app/services/sessions/live_log_reader.rb#tail` — redact before returning
- `app/services/personal_tools/get_session_log.rb` — inherits the redaction from `LiveLogReader`;
  verify the stored-log branch is covered too

**Changed — meta tools (agents authoring workflows)**

- `app/services/internal_tools/meta_link_resource_to_step.rb` — new `config_item` resource kind
- `app/services/internal_tools/meta_{create,update}_step.rb`
- `app/services/personal_tools/{create,update}_workflow_step.rb`, `update_project_settings.rb`
- `app/services/workflow_duplicator/dependency_copier.rb` — resolve attachments by name in the target
  project; never copy `ConfigItem` rows

**Changed — frontend**

- `app/frontend/shared/components/SessionNewForm.tsx:126-130, 192-196, 372-420` — state, payload,
  picker
- `app/frontend/pages/Projects/Sessions/NewPage.tsx` — prop pass-through
- `app/frontend/pages/Projects/Workflows/BaseResourcesTab.tsx:16-20, 142-188`
- `app/frontend/pages/Projects/Workflows/SessionEditorPanel.tsx:49-53, 434-509`
- `app/controllers/web/company/projects/aixle_builder_controller.rb:34-45` — builder sessions create
  `TerminalSession` in code; decide explicitly whether they attach anything (default: no)

**Not changed, deliberately**

- `docker/base/entrypoint.sh:123` — the `> /proc/1/fd/1` dual sink stays. See Design Notes.
- `app/services/container_strategies/custom_tool_strategy.rb` — the custom-tool env channel is
  correct and stays.
- MCP `config_item:NAME` references in `env`/`headers` — correct and stay.

## Tasks & Acceptance

**Phase 1 — cascade (no tool yet)**

1. Migrations: join table + `steps.config_item_ids`. Schema dumped from the test DB only.
2. Model + resolver: HABTM, `base_config_item_ids`, `resolve_config_item_ids`, breakdown entry.
   *Accept:* `SessionConfigResolver` test proves the additive cascade and the
   `inherit_all_project_resources` path, matching the existing tool/skill cases.
3. Controllers + resources + regenerated types.
   *Accept:* an attachment survives session create → resolve → `session.config_items`; an id from
   another project is rejected.
4. Delete the dead env path. *Accept:* `grep -r env_vars app/` returns only container-strategy env
   plumbing unrelated to config items.

**Phase 2 — the tool**

5. `get_config_item` + `config_items_attached` injection rule + audit model.
   *Accept:* the I/O matrix above, case by case. Explicitly: an unattached item returns an error and
   writes no audit row; a successful fetch writes exactly one row and no value anywhere.
6. `ContextBuilders::ConfigItems`. *Accept:* the section lists names and no values; absent when nothing
   is attached.

**Phase 3 — redaction**

7. `Sessions::SecretRedactor`; extract the substitution out of `ContextLog#scrub_secrets` so both use
   one implementation. *Accept:* short values redact; longest-first ordering holds; a session with no
   secrets is a no-op.
8. Wire the four sinks. *Accept:* a test that plants a secret value in a fake container's
   `terminal_output.log` and `http.log` and asserts the persisted `SessionLog` bytes contain the
   fingerprint and not the value.

**Phase 4 — UI**

9. Pickers on the three screens. A `secret` is labelled as such in the option list, so attaching one
   reads differently from attaching a variable; there is no exposure warning (see the change log).
   *Accept:* Vitest coverage per `docs/testing.md`; the picker payload carries no values.

**Phase 5 — meta tools & duplication**

10. `meta_link_resource_to_step` kind, step meta tools, personal-MCP step tools.
11. `WorkflowDuplicator` name-resolution + a report of dropped attachments.

## Spec Change Log

- **2026-08-17 — created.** Product decisions taken during design, all by the human:
  attachment gates on project access alone; project scope only; inheritance identical to other
  resources; MCP-only delivery (no env, no file); the pod-stdout sink stays.

- **2026-08-17 — implemented.** Five deviations/additions found while building, none of them
  changing the intent above:

  1. **Scope validation was added on three models, not just the tool.** `tool_ids`, `skill_ids` and
     `mcp_server_ids` are taken on trust from the request today. For config items that is an
     escalation path — post another project's id and the session may decrypt it — so
     `TerminalSession#config_items_belong_to_project`, `Step#config_item_ids_belong_to_project` and
     `Workflow#base_config_item_ids_belong_to_project` reject ids outside the owning project. On
     the model rather than in a controller, so the API, the meta tools and a console are all
     covered.
  2. **`Api::V1::TerminalSessionsController#create` now answers 422 on a failed save.** It
     serialized the returned record unconditionally, and an unsaved `TerminalSession` raises on its
     Global ID — so any validation failure was a 500. Pre-existing, but this feature ships the
     first validation a user can trip from the UI.
  3. **`scrub_conflicting_auth_env` is kept, and its tests were rewritten.** Deleting the
     `env_vars` channel removed the only source of arbitrary env, so the two Bedrock tests that
     drove it through a stubbed `resolve_env_vars` no longer had a reachable path. They are
     replaced by real ones on the Grok path (`default_env_vars` is the remaining producer) plus a
     test asserting no config-item value reaches container env at all. Per-adapter key lists stay
     covered in the adapter tests. The scrub itself stays as the net for `default_env_vars`.
  4. **`WorkflowDuplicator` resolves attachments by name** (`DependencyCopier#map_config_item_ids`)
     and reports what it dropped through the existing `summary[:needs_setup]`. Ids are never
     carried across a project boundary and `ConfigItem` rows are still never copied.
  5. **No exposure warning in the UI.** The first cut shipped a `SecretExposureNotice` alert on all
     three pickers, spelling out the sink table above. Removed at the human's request: it was not part
     of the brief, and a paragraph about pod stdout is not what someone attaching a credential needs to
     read. What remains is the `(secret)` suffix on the option label, so attaching a secret still reads
     differently from attaching a variable. The limitation itself is unchanged and stays documented
     here — the rule against *claiming* logs are clean still stands, and silence satisfies it.
  6. **Eager loading**, because `TerminalSessionResource` serializes `config_item_ids`:
     `:config_items` added to the session scopes in the two sessions controllers, the Aixle Builder
     and the profile page. The Aixle Builder N+1 budget moves 19 → 20 for the one constant preload.

## Design Notes

### Why MCP-only, and why not a file

An earlier draft offered `deliver: "file"` — write the value into the container at `/run/secrets/NAME`,
return only the path, keep the bytes out of the model context entirely. It was rejected, and the reason
matters for anyone tempted to re-add it: **the agent has `Read` and `Bash`.** It will `cat` the file —
to check it, or simply because that is the shorter path — and the value lands in context anyway. A file
inside a container the agent fully controls is a convention, not a boundary. (The commonly cited
objection, that `curl` would leak it, is not the reason: `MITM_TRACKED_DOMAINS` is a single provider
host per runtime — `claude_code_adapter.rb:784` — so a request to a third-party API traverses the proxy
unlogged, and `$(cat …)` in a command line prints the substitution, not the value.)

Container env was rejected for a different reason: it is a second delivery channel with different
exposure properties, and two channels means two mental models for the same question. MCP-only keeps one
answer — and, unlike env, it produces an audit row.

### The sink table

Once a value is in the model's context it is in the request body to the provider, which the MITM logger
captures in full (`mitm_logger.py:19` — `MAX_BODY` defaults to `0`, unlimited). So "in context but not
in logs" is achievable only as value-level redaction at each sink, never as "do not log this tool".

| Sink | Where | Closed by this spec |
|---|---|---|
| `SessionLog` — `terminal_output.log` | `agent_session_strategy.rb:151-172`, S3 + UI replay | yes |
| `SessionLog` — `http.log` | `agent_session_strategy.rb:174-200` | yes |
| `SessionLog` — `context.log` | already partly redacted, `ContextLog#redact` (`:116`) | yes, extended |
| `LiveLogReader` → UI, `get_session_log` | `sessions/live_log_reader.rb` | yes |
| **pod stdout → Alloy/Loki** | `docker/base/entrypoint.sh:123`, `tee … > /proc/1/fd/1` | **no** |
| live ttyd stream | browser, gated by `TerminalSession#visible_to?` | no, by nature |
| `ToolResult` | app-mode tools create no row (`CallExecutor.execute:15-40`) | n/a |
| CLI transcript in the container | not in `session_log_paths`; dies with the pod | n/a |

The pod-stdout sink is the one redaction cannot reach: the dual sink writes at print time, minutes
before the collector runs, and Loki holds a copy we do not own. Closing it means dropping
`> /proc/1/fd/1` for secret-bearing sessions, which costs cluster-side visibility of exactly the
sessions most worth watching — see `research/technical-agent-session-log-access-and-control-2026-08-10`
for what that sink is for. **Product decision 2026-08-17: keep the sink, state the limitation here.**
This table is that statement; the UI does not repeat it (see the change log).

### Renegotiated: log redaction

`spec-session-observability-mcp-tools.md` froze "Return log content **unredacted**: no secret
filtering" and listed "Redacting or masking log content" under *Ask First* (product decision,
2026-08-10). This spec renegotiates that, narrowly: redaction applies to **values of `secret` config
items attached to the session**, which are a known, enumerable set — not to a heuristic scan for
things that look secret. Everything else in a log is still returned verbatim. That earlier spec's
change log records the renegotiation.

### Why the audit trail is load-bearing

With attachment gated on project access alone, the vault's boundary is the project and nothing narrower.
`config_item_accesses` is then the only artifact that can answer "which session read `STRIPE_KEY`, and
who was driving it" — worth building in Phase 2 rather than deferring, because the rows cannot be
reconstructed later.

## Verification

```bash
docker compose exec -T web make check_all
```

Manual, in a project with one `secret` and one `variable`:

1. Start a session with both attached. Confirm the context file lists names only.
2. Call `get_config_item` for each; confirm values return and two audit rows exist with no values.
3. Call it for an unattached item; confirm the error and that no audit row is written.
4. Let the session finish. Download the stored `terminal_output.log` and `http.log`; confirm the secret
   appears only in fingerprint form, and the variable's value is untouched.
5. Confirm a session with nothing attached is not served `get_config_item` at all.

## Suggested Review Order

1. `session_config_resolver.rb` — the cascade is the load-bearing part; everything else reads from it.
2. `internal_tools/get_config_item.rb` — the attached-set-not-project-set rule.
3. `sessions/secret_redactor.rb` + the four sink call sites.
4. Controllers and resources — that no value crosses into a prop.
5. Frontend pickers and the warning copy.
