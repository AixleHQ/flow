WINNER: C

SCORES: {
 "A": {
  "dev_ergonomics": 9,
  "migration_safety": 9,
  "runtime_correctness": 8,
  "security": 6,
  "ecosystem_alignment": 6,
  "simplicity": 8
 },
 "B": {
  "dev_ergonomics": 8,
  "migration_safety": 5,
  "runtime_correctness": 7,
  "security": 7,
  "ecosystem_alignment": 9,
  "simplicity": 7
 },
 "C": {
  "dev_ergonomics": 7,
  "migration_safety": 8,
  "runtime_correctness": 8,
  "security": 9,
  "ecosystem_alignment": 9,
  "simplicity": 6
 }
}

RATIONALE:
Security is weighted heaviest, and C is the only design where the multi-tenant trust boundary is structural rather than validation-dependent — verified against the actual code, this matters: the current name regex (/\A[a-z][a-z0-9_]*\z/ in app/models/tool.rb) permits tenant-created mcp__-prefixed names today, and the NULLs-distinct unique index (db/schema.rb:727) means a tenant row can already collide with a platform name. C neutralizes both structurally: a DB CHECK bans the managed namespace (survives console bypass), call-resolution order (managed → platform → DB) makes shadowing physically impossible, anchor rows are definition-free so a poisoned row is inert because serving never reads it, and publisher-pinned definition_digest makes DB rug-pulls fail closed. A's defenses for the same threats are a creation-time validation and a report-mode rake task — both bypassable — and A leaves the platform/custom collision case with no specified resolution order while serving tenant-authored descriptions from the same table. B gets structural reference separation via key prefixes but pays for it with the riskiest migration on the table: an irreversible Stage 5 that deletes platform rows and rewrites opaque tenant JSONB tool_ids, plus a self-flagged CurrentAttributes leak hazard on non-Rack paths (Temporal/SSE) that it uses anyway. C also matches B on ecosystem alignment (official mcp gem, stateless per-request lists, canaried dual-mount transport swap) while refusing the JSONB migration entirely — anchors keep every FK and workflow config valid forever. C's costs are real (highest concept count, publisher ceremony, deploy-only reconciler leaving new tools briefly un-attachable) but they buy defenses against attacks the research shows are actively exploited, and its worst failure modes fail closed rather than open. A is the safest to ship and would win under a pure migration-risk lens, but it evolves the muddled trust model in place rather than fixing it.

GRAFT IDEAS:
- From A: boot-time self-heal reconcile under a pg advisory xact lock plus a lazy Tool.shadow_for-style anchor materialization fallback — this directly closes C's self-declared gap where a brand-new platform tool is listable but not id-attachable until the deploy rake task runs (guard with column-existence check, ENV kill switch, and rescue-log on DB outage as A specifies)
- From A: exact-pin actionmcp to = 0.104.1 immediately as a Stage 0 item — the Gemfile currently says ~> 0.100, so an accidental bundle update can jump past the 4-arg send_tools_call signature and break production before C's Stage 4 transport swap ever lands
- From A: keep writing the legacy kind column from the reconciler through the taxonomy cutover stage so every rollback lands on rows the previous release fully understands, and gate the seeds deletion on a row-for-row parity fixture test generated from the current Seeds::PlatformTools output (A's parity gate is more concrete than C's drift task for the initial port)
- From A: ship the aixle_builder kind: :workflow vs :meta hotfix as an independent Stage 0 deploy with regression tests, rather than waiting for C's taxonomy stage to fix it structurally — it is a live bug today
- From B: the ManagedAlias SimpleDelegator pattern that materializes namespaced coder tools directly into the per-request tools array once on the official mcp gem — it deletes the ManagedNamespace.parse dispatch branch from C's resolution path, shrinking the code at the most security-sensitive choke point
- From B: accept string tool keys (platform:<name>/custom:<id>) in NEW workflow/step configs going forward (dual-read ids and keys) without migrating existing JSONB — captures B's WorkflowDuplicator win (platform keys stable across companies, killing an id-remapping bug class) at zero migration risk, and gives C a gradual exit path from anchors