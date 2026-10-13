# Project memory pilot

Project memory reuses reviewed discoveries between runs. It complements BMAD,
specifications and workflow artifacts. Current code and specifications remain
authoritative; retrieved findings are reference data, not executable instructions.

## Start the private service

The optional overlay builds Engram **3.4.0** from its versioned Go module, verified
through the Go checksum database. It puts SQLite in the `engram_data` volume and
keeps the REST service off the agent network and host ports. Cloud/git sync is off.

```sh
docker compose -f docker-compose.yml -f docker-compose.engram.yml up -d --build engram
docker compose exec -T web bin/rails db:migrate
docker compose -f docker-compose.yml -f docker-compose.engram.yml up -d web worker
```

The overlay supplies `ENGRAM_URL=http://engram:7437` to web and worker. For another
deployment, supply a private operator-controlled origin and, if configured on the
server, `ENGRAM_HTTP_TOKEN`. Do not expose the upstream API directly to agents:
its project/scope selectors do not replace Flow authorization. Kubernetes needs
equivalent private service networking and persistent storage; this overlay does
not deploy Kubernetes resources.

Under **Project Settings**, an owner or company admin can enable **Project memory
(pilot)**. It is off by default. A session can independently opt out with
`metadata.memory_disabled=true`; this also removes its memory tools. Disabling a
project prevents retrieval/capture but preserves records for authorized cleanup.

## What sessions can do

- `memory_search`: focused keywords; compact previews of up to three reusable findings.
- `memory_get`: a bounded detail view for a Flow memory ID, rechecking authorization and sources.
- `memory_capture`: propose a concise finding. Proposals are always **pending**;
  the agent cannot approve, modify or delete validated findings through MCP.

The trusted gateway derives company/project from the authenticated session. It
filters index candidates through Flow-owned records and never returns index text
as an authoritative finding. Read/write access is checked again on each call.

Per session, the pilot allows five retrieval calls, approximately 2,000 retrieved
tokens in total, and ten proposals. Searches return 200-character previews;
details return at most 1,800 content characters. Findings are at most 2,000
characters, titles 120, topic keys 100, and source lists three entries. Counts are
serialized under database locks and retained across requests. Token estimates
include serialized result metadata and use four characters/token; provider bills
also include schemas, tool calls and other context.

Use stable topic keys such as `pattern/transactions` and the project's configured
artifacts language for shared findings. Keep the finding short and link sources;
do not copy specifications. Common credential patterns and transcript forms are
rejected before persistence, but pattern matching cannot detect every secret.
Human review must check the content before approval.

## Review and source freshness

The pilot verifies **GitHub** source files against their latest file-changing
commit on each repository's configured source branch. `revision` means that full
40-character file commit SHA, not a branch name or an unrelated HEAD commit.
Source repositories must belong to the project; proposals can reference only
repositories attached to their session. GitLab/Azure sources cannot yet be
approved. Unsupported, changed or unavailable sources are withheld from reuse.
Local uncommitted changes still require the agent to recheck its working tree.

Review is an operator command acting as an explicit owner/admin, including after
the originating session ends. List metadata without dumping findings:

```sh
docker compose exec -T -e PROJECT_ID=123 -e REVIEWER_ID=456 web bin/rails project_memory:list
```

Prepare an access-controlled JSON file inside the web container, for example
`/app/tmp/memory-review.json`:

```json
{
  "evidence": "Reviewed the specification and passing transaction regression test.",
  "sources": [{"repository_id": 789, "path": "docs/spec.md", "revision": "0123456789012345678901234567890123456789"}]
}
```

Replace the sample IDs/SHA with actual verified sources. Approve with the exact
proposal revision from `list`:

```sh
docker compose exec -T -e PROJECT_ID=123 -e REVIEWER_ID=456 -e MEMORY_ID=42 -e REVISION=proposal-uuid -e REVIEW_FILE=/app/tmp/memory-review.json web bin/rails project_memory:validate
```

Approval records evidence and reviewer identity, verifies sources, and indexes
the finding. Review expires after 30 days. Proposals remember their accepted base
revision so a competing approval cannot silently overwrite an intervening
decision. Revalidation of a previously validated finding creates a new revision;
earlier sources and retrieval snapshots retain their provenance.

## Correction, deletion and retention

Use `project_memory:obsolete` or `project_memory:purge` with `PROJECT_ID`,
`REVIEWER_ID`, `MEMORY_ID` and `REVISION`. Obsolete findings leave ordinary
retrieval; purge removes the finding and associated snapshots. Supersession,
source invalidation and model/project destruction enqueue scoped index cleanup.
Cleanup retries on service outages; monitor failed `EngramCleanupJob` jobs and
retry them after restoring the service. Deletion from live stores does not erase
historical backups; apply backup retention and access policy separately.

Schedule authorized `project_memory:prune_snapshots` per pilot project to remove
snapshots older than 30 days. `project_memory:prune_findings` purges up to 100
pending/obsolete findings untouched for 90 days; repeat for larger backlogs.
These are explicit maintenance tasks, not automatically enabled schedules.
Validated findings remain retained until reviewed, superseded or explicitly removed.

`project_memory:manifest` additionally takes `SESSION_ID` and exports that
project session's exact retrieved payloads and revisions. Treat the output as
project data. It supports auditing/reconstructing memory input within retention;
it does not make the agent/model execution deterministic or automatically replay
an entire run. Memory-disabled runs remain available for comparison.

## Service lifecycle checks

The container supervises Engram and its private-network proxy. If either exits,
the container exits with an error so Compose's restart policy can recover it;
shutdown forwards termination to both processes.

After building the image, run the isolated lifecycle regression from the host:

```sh
sh docker/engram/test-lifecycle.sh
```

It uses disposable containers without persistent volumes to check startup
failure, server/proxy failure and graceful shutdown. It does not touch the pilot
database or index.

## Backups and evaluation

Back up PostgreSQL records and the Engram SQLite volume. For a consistent SQLite
filesystem backup, stop the Engram service before copying its volume, including
WAL files, then restart it. Restore into an isolated environment first and check
save/search/delete and authorization before resuming the pilot. Do not copy only
the live main database file while it is being written. Loss of the index can
temporarily hide findings even when Flow records survive.

The local recovery exercise verified a stopped-service SQLite archive restored
into a separate volume, with search, new writes and scoped deletion working
without changing the original index. Threaded PostgreSQL tests verify real lock
contention for session quotas and competing reviews. A subsequent controlled exercise restored PostgreSQL and Engram together into
a separate database and volume, verified canonical/index revision associations,
exact snapshots and access denials, and confirmed deletion stayed isolated. These
checks do not replace your installation's recovery procedure or sustained
production-load testing.

Memory failures return a bounded, sanitized tool error; ordinary workflows can
continue using their specifications and artifacts. Source checks and review add
latency. Session metadata under `project_memory` records retrieval calls,
estimated retrieved tokens, captures and backend failures. Retrieval snapshots
are separate authorized records, not copied into the initial context metadata.

Compare 20–30 comparable tasks with memory off/on, recording actual provider
tokens, cache effects, total cost, latency, retries and human acceptance/rework.
Include proposals and review effort in the assessment. This is a preliminary
sample, not evidence of universal savings. Expand only after isolation/control
checks pass and cost or completion time improves without degraded quality.
No production savings are claimed by this implementation.

### Export a comparison cohort

Owners and company admins can export up to 100 explicitly selected sessions,
including sessions with memory disabled. The export reads existing statistics;
it does not run a model or query Engram:

```sh
docker compose exec -T -e PROJECT_ID=123 -e REVIEWER_ID=45 \
  -e SESSION_IDS=101,102 web bin/rails project_memory:metrics
```

Replace the example IDs with the project, authorized reviewer and its sessions.
The task prints a JSON array; ordinary application logs may also appear. A foreign,
missing or mismatched-company session rejects the whole selection. It exports
provider-reported usage/source/models, cache breakdown, costs, timestamps and
memory counters. It does not export prompts, findings or raw provider events.

`usage: null` means missing usage. `token_measurement_available: false` means a
usable positive token measurement is unavailable, including credit-only Kiro
usage; do not turn these into zero-token savings. `retrieved_tokens_estimate`
is a separate approximation and must not be added to the provider total, which
already covers reported retrieval processing. `cost_cents_precise: null` means
no positive precise cost was recorded; use the reported rounded cost with its
source rather than treating the missing precision as a zero charge.

Assign the exported `cohort: null` explicitly to `memory_off` or `memory_on` in
the comparison worksheet. Record task ID, all session IDs including retries,
acceptance/rework and review effort alongside it. The current project switch
cannot establish whether memory was enabled during an old session. Compare total
cost per accepted task; keep unavailable token measurements out of token-based
ratios while reporting how many tasks lack coverage.

Sources: [Engram 3.4.0](https://github.com/Gentleman-Programming/engram/releases/tag/v3.4.0),
[upstream API](https://github.com/Gentleman-Programming/engram/blob/v3.4.0/DOCS.md),
[GitHub file commit query](https://docs.github.com/en/rest/commits/commits#list-commits).
