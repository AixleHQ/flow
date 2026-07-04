WINNER: A

SCORES: {
 "A": {
  "dev_ergonomics": 8,
  "migration_safety": 9,
  "runtime_correctness": 8,
  "security": 6,
  "ecosystem_alignment": 5,
  "simplicity": 7
 },
 "B": {
  "dev_ergonomics": 9,
  "migration_safety": 5,
  "runtime_correctness": 5,
  "security": 7,
  "ecosystem_alignment": 9,
  "simplicity": 6
 },
 "C": {
  "dev_ergonomics": 7,
  "migration_safety": 9,
  "runtime_correctness": 8,
  "security": 9,
  "ecosystem_alignment": 8,
  "simplicity": 5
 }
}

RATIONALE:
Weighing migration_safety and runtime_correctness heaviest, A wins narrowly over C, with B clearly third. A touches zero FKs forever (verified: tool_results.tool_id is null:false with a RESTRICT-style FK, and steps.tool_ids/workflows base_tool_ids are integer jsonb refs — exactly the data B's Stages 4-5 must migrate and delete irreversibly), keeps rows bit-compatible with old code at every stage by writing legacy kind through Stage 3, and puts an env-flag kill switch on the highest-traffic path change (available_tools). Its evidence quality is also highest: it found the real, verified Builder bug (controller queries kind: :workflow after migration 20260627000002 moved meta_* to :meta) and schedules it as Stage 0. Runtime-wise, A and C both avoid CurrentAttributes and actionmcp's non-thread-safe registry with reload-safe frozen memos; A additionally closes the dev-vs-prod 'forgot the deploy rake' gap via boot reconcile + lazy shadow_for, where C's deploy-only reconcile leaves new tools un-attachable until a task runs — a classic works-in-dev/breaks-in-prod asymmetry. C beats A on security (structural anti-shadowing, mcp__ CHECK, digest pinning) and ecosystem (dropping the monkey-patch), but pays in concept count and two new pageable failure modes (fail-closed digest vanishing tools, transport canary). B is punished on exactly the axes the brief weights: a big-bang 52-class port, a self-declared irreversible Stage 5 (platform rows deleted, session_tools dropped, table renamed), a CurrentAttributes-memoized IntegrationSet it itself flags as leaking across Temporal/SSE threads, and a serving swap sketched against unpinned mcp-gem 0.22 APIs. A's known debts (monkey-patch retention, actionmcp deferral) are scheduled and contained in gem-agnostic Tools::* modules — and its 'pin exactly' demand is validated by the actual Gemfile, which today carries a loose ~> 0.100 that would admit a breaking 0.111 bump.

GRAFT IDEAS:
- From C: add the DB CHECK constraint banning mcp__% names on tools (additive migration) so the managed-server namespace is structurally unreachable by custom rows, not just app-validated
- From C: make call-time resolution order structural (managed namespace -> platform registry -> custom row) inside the patched send_tools_call, so grandfathered duplicate-name custom rows can never shadow a platform tool even before manual cleanup
- From C: ship the Stage 0 ops-hardening bundle alongside A's Stage 0 hotfix — Slack tokens_revoked/app_uninstalled consumers (without them the availability predicate serves dead Slack tools indefinitely), Temporal heartbeats + docker-kill-on-cancel, read_tool_result output truncation/paging, and a tool_invocations audit table
- From C: route custom-tool writes through a single Publisher with definition_digest + docker image digest pinning as an incremental follow-up — fail-closed rug-pull defense with alerting, orthogonal to A's staging
- From C: run tools:check not just in CI but as a scheduled prod drift task (db:abort_if_pending_migrations-style), since A leans on it for legacy name-collision cleanup and rename-orphan detection
- From B: adopt the param DSL that compiles to JSON Schema (param :text, type: :string, ...) instead of raw verbatim schema hashes in the tool blocks — reduces transcription errors during the 50-tool port and makes definitions greppable; keep input_schema(raw) as the escape hatch
- From B/C: add tool_results.tool_key (and tool_source) as an additive backfilled column now — provenance that survives row churn, decouples analytics from integer ids, and keeps the door open to retiring shadow rows later without another schema change
- From B: add MCP behavior annotations (readOnlyHint/destructiveHint/idempotentHint/openWorldHint) to the DSL and serialize them on the wire — cheap, spec-aligned, and useful for client confirmation policies
- From B: reject the mcp__ prefix in the custom-tool name validation immediately (the current name regex permits it), independent of the CHECK constraint