---
title: 'Skills catalog: featured browse, registry mirror, manual SKILL.md authoring'
type: 'feature'
created: '2026-08-03'
status: 'done'
baseline_commit: 'ad47277f7420767a34354b9129f395b6e7d2f07a'
review_loop_iteration: 0
context:
  - '{project-root}/docs/planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md'
  - '{project-root}/docs/testing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Skills page opens on an empty search box — `SkillsController#index` returns `[]` for a blank query and `SkillsRegistryService.search` refuses queries under 2 characters — so there is nothing to browse, no popularity signal, and no way to register a skill that isn't in the skills.sh registry. Meanwhile three defects sit in the existing path: `inject_skills` runs the skills CLI without `DISABLE_TELEMETRY=1` (which reports skill name **and skill files** upstream), the authenticated `/api/v1` branch cannot work (Vercel-OIDC only, so setting `SKILLS_SH_API_KEY` silently breaks search), and `Skill` name validation contradicts the Agent Skills spec in ways that make a skill fail to load in the agent.

**Approach:** Bring the Skills page to Connectors-page parity in four stacked phases on one branch: (0) fix the three defects; (1) serve a curated featured set on a blank query behind the connector-style catalog modal; (2) back that view with a `catalog_skills` mirror built by a seeded sweep of the public search endpoint on a weekly Temporal schedule, ranked with upstream installs leading and the connector catalog's bulk-publisher counterweights; (3) allow authoring a skill from pasted `SKILL.md`, validated server-side and delivered into the container without the CLI.

## Boundaries & Constraints

**Always:**
- Skills stay **project-scoped** (`Skill` `scope_type` inclusion `%w[Project]`); no company scope.
- Upstream data is reached **only** through these public, unauthenticated endpoints — never `/api/v1/*` (OIDC-only, returns 401), never an HTML crawler:
  - `GET https://www.skills.sh/api/search?q=&limit=&owner=`
  - `GET https://www.skills.sh/api/download/{owner}/{repo}/{skill}`
  - `GET https://add-skill.vercel.sh/audit?source=&skills=` — third-party security verdicts (**renegotiated by the human, 2026-08-03**, after the CLI's own source showed this host is public; the original boundary assumed audits were reachable only via an OIDC proxy)
  - `GET https://<publisher-host>/.well-known/{agent-skills,skills}/index.json` and the `SKILL.md` it points at — RFC 8615 discovery, the only way non-GitHub publishers (e.g. `open.feishu.cn`, 519k installs) can be installed at all (**renegotiated by the human, 2026-08-03**). Host must be a bare hostname over https; no ports, no IPs, no loopback, with a byte cap and timeout.
- Live upstream search keeps serving the search box; the mirror serves the **default/featured view only**.
- Manual skills are written into the container directly. No manual skill content may reach `npx skills add` or any outbound request.
- A manual skill must land **exactly where the `skills` CLI puts a registry skill** for the same agent — the agent's own config directory plus `skills/<name>/` (`~/.claude/skills/…` for claude-code, `~/.gemini/skills/…`, `~/.cursor/skills/…`), derived from each adapter's existing `home_dir` + config-dir convention rather than a new hardcoded map. Verify by comparing against a CLI-installed skill, not by assumption.
- Every UI-reachable skill operation gets an MCP tool equivalent, authorized through `Web::Company::Projects::SkillsPolicy`.
- Catalog ranking must keep bulk-publisher and curated-seed counterweights; a raw `installs DESC` ordering is not acceptable.
- Testing follows `docs/testing.md`: `stub_request` only in adapter contract tests, a fake for everything above the adapter, no `any_instance`, never stub the class under test.

**Ask First:**
- Tightening `Skill` name validation in a way that could fail `save` on existing rows (strict-on-new-records vs normalize-then-enforce).
- Sweep seed list size/cadence if it would exceed ~250 requests per run.

**Never:**
- No `scripts/` / executable bundle support (markdown, `references/`, `assets/` only if trivial; executables are out of scope).
- No Vercel-hosted OIDC proxy and no trending/hot views. (Security-audit badges **were** in this list; the human moved them out on 2026-08-03 once the audit host turned out to be public. A badge alone is not enough — a `high`/`critical` verdict must interrupt the install, not decorate it.)
- No third-party mirror dependency (`mastra-ai/skills-api`).
- No company-scoped or cross-project skill sharing.
- No eager full-catalog `/api/download` backfill.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Browse default view | `GET .../skills` with blank `q` | Featured/ranked catalog entries returned as props; grid renders | N/A |
| Search catalog | `q="react"` | Live upstream results merged with mirror rows, install counts shown | Upstream failure → empty result set + page still renders |
| Query too short | `q="a"` | No upstream call; featured set stays visible | N/A |
| Install from catalog | POST `skillId` | `Skill` row created with `origin: registry`, `content_hash` stored | Unknown id → flash "Skill not found"; already installed → flash, no 500 |
| Install a flagged skill | Catalog entry whose worst audit verdict is `high`/`critical` | Install is interrupted and requires explicit confirmation | N/A |
| Install from a non-GitHub publisher | `open.feishu.cn/lark-doc` (2-segment id, download 404s) | Resolved via `.well-known` discovery and installed | Host not resolvable → flash naming the publisher, not a generic not-found |
| Typed query | Any `q` ≥ 2 chars | Upstream results rendered **in upstream relevance order**; nothing is persisted by a GET | Upstream failure → mirror full-text results |
| Sweep run | Weekly schedule, some pages fail | Successful pages upserted, ranking recomputed, `failed` counted and logged | One bad page never aborts the sweep |
| Sweep on empty table | No rows | Full sweep populates; featured seed already visible beforehand | N/A |
| Bulk publisher in results | Mirror holds ~25 `larksuite/cli/lark-*` | At most one entry per publisher in the default view | N/A |
| Manual add, valid | Pasted `SKILL.md` with `name`, `description` | `Skill` created with `origin: manual`, `source`/`package` nil | N/A |
| Manual add, bad frontmatter | Missing `description`, `name` with `_`/`--`/>64 chars, or `<`/`>` in frontmatter | Rejected with a field-specific message; nothing persisted | Validation error surfaced in the modal |
| Manual add, duplicate name | Name already used in the project | Rejected on the existing uniqueness index | Error surfaced, no partial write |
| Manual skill in a session | Session with a manual skill | Skill directory written into the container; `npx skills add` not invoked for it | Write failure logged per skill like CLI failures are |
| Context-text runtime | Adapter with `includes_skills_in_context? == true` | Manual skill content flows through `ContextBuilders::Resources`, no file write | N/A |

</frozen-after-approval>

## Code Map

- `app/services/skills_registry_service.rb` -- current transport + install use case in one class; dead OIDC branch lives here
- `app/services/session_context_service.rb:215` -- `inject_skills`; missing `DISABLE_TELEMETRY=1`; manual delivery hooks here
- `app/services/context_builders/resources.rb:66` -- `build_skills` / `build_skills_full` for `includes_skills_in_context?` runtimes
- `app/services/agents/{base,claude_code,gemini_cli,cursor_cli}_adapter.rb` -- `skills_agent_name`, `includes_skills_in_context?`; new skills-directory method goes here
- `app/models/skill.rb` -- name regex to align with spec; `origin` behaviour; `registry_url`
- `app/models/connector.rb` -- ranking/featured/bulk-publisher precedent to mirror (`popular`, `FEATURED`, `VENDOR_TIER`)
- `app/services/mcp/connector_catalog_sync.rb` -- sync precedent: `upsert_all` per page, `refresh_ranking`, `refresh_bulk_publishers`, `Result` struct
- `db/migrate/20260801000002_create_connectors.rb` -- migration precedent incl. stored generated `search_vector` + GIN index
- `app/controllers/web/company/projects/{skills,mcp_servers}_controller.rb` -- blank-vs-query prop logic (`catalog_connectors`, `CATALOG_PAGE_SIZE = 60`)
- `app/frontend/shared/resources/skills/SkillsContent.tsx` -- page + `RegistrySearchModal` to restructure
- `app/frontend/shared/resources/connectors/ConnectorCatalogModal.tsx` -- target UX shape (suggested heading, card grid, monogram fallback, install modal)
- `app/resources/skill_resource.rb` -- props/type surface for new fields
- `app/services/personal_tools/{install_skill,search_skill_registry}.rb` -- tool DSL precedent for a manual-create tool
- `app/temporal/{schedules,workflows}.yml`, `app/temporal/workflows/mcp_connector_catalog_sync_workflow.rb`, `app/temporal/activities/mcp/sync_connector_catalog_activity.rb` -- schedule wiring precedent
- `config/routes.rb:320` -- project-scoped `resources :skills, only: %i[index create destroy]`
- `test/services/skills_registry_service_test.rb`, `test/support/fakes/` -- existing contract test; no skills fake exists yet

## Tasks & Acceptance

**Execution — Phase 0 (independent fixes):**
- [x] `app/services/session_context_service.rb` -- pass `DISABLE_TELEMETRY=1` in the env of the `npx skills add` exec -- stop reporting skill name and files upstream on every session install
- [x] `app/services/skills_registry_service.rb` -- remove the authenticated `/api/v1` search/detail branch (and the `Settings.skills_sh.api_key` reads), leaving the public path as the only path; drop the now-unused `skills_sh.api_key` setting -- an unset-by-default key that 401s and returns `[]` is a silent-breakage trap
- [x] `app/models/skill.rb` -- align the `name` format with the Agent Skills spec (`[a-z0-9-]`, 1–64, no leading/trailing hyphen, no `--`) and keep `name=`'s sanitizer consistent; scope strictness so existing rows can still be saved (see Ask First) -- a spec-invalid name silently fails to load in the agent
- [x] `test/services/skills_registry_service_test.rb`, `test/models/skill_test.rb` -- update/extend for the removed branch and the new name rules

**Execution — Phase 1 (featured browse):**
- [x] `app/models/skill.rb` (or a new `Skills::Featured` constant module) -- add the curated `FEATURED` registry-id seed from the research report, deduplicated by source, incl. the 17 `anthropics/skills` entries -- a cold catalog must still open on something
- [x] `app/controllers/web/company/projects/skills_controller.rb` -- serve the featured set when `params[:q]` is blank, mirroring `catalog_connectors`; add a page-size constant; expose `catalogSyncedAt`-style prop -- blank query currently returns `[]`
- [x] `app/resources/skill_resource.rb` + a catalog resource -- expose catalog entries (id, source, name, title, description, installs, iconUrl, installed?) with Typelizer types regenerated
- [x] `app/frontend/shared/resources/skills/SkillsContent.tsx` (+ new `SkillsCatalogModal.tsx`) -- restructure the registry modal into the connector-catalog shape: "Suggested skills" heading on empty query, card grid, GitHub-owner avatar with monogram fallback, install-count badge, debounced partial reload unchanged
- [x] `test/integration/web/company/projects/skills_controller_test.rb`, `app/frontend/pages/Projects/Skills/SkillsPage.test.tsx`, `SkillsCatalogModal.test.tsx` -- cover blank-query featured props and modal behaviour

**Execution — Phase 2 (mirror + sweep):**
- [x] `app/services/skills/registry_client.rb` -- extract the transport (`search`, `download` returning files + `hash`) out of `SkillsRegistryService`, which keeps the install use case
- [x] `db/migrate/*_create_catalog_skills.rb` -- mirror table keyed on the registry id with `source`, `slug`, `title`, `description`, `installs`, `install_count`, `featured`, `bulk_publisher`, `content_hash`, `registry_synced_at`, stored generated `search_vector` (name/title A, description B) + GIN index, modelled on `CreateConnectors`
- [x] `app/models/catalog_skill.rb` -- `popular` scope (`installs DESC, featured DESC, bulk_publisher ASC, install_count DESC, registry_synced_at DESC`), `search` scope via `websearch_to_tsquery`, `icon_url`, `installed?` helpers
- [x] `app/services/skills/catalog_sync.rb` -- seeded query sweep with per-page `upsert_all`, page-level failure tolerance, `Result` struct logging `fetched/upserted/failed`, and a `refresh_ranking` pass recomputing `bulk_publisher` (window function over the publisher segment), `install_count` (from `skills`), and `featured`
- [x] `app/temporal/activities/skills/sync_catalog_activity.rb`, `app/temporal/workflows/skills_catalog_sync_workflow.rb`, `app/temporal/workflows.yml`, `app/temporal/schedules.yml` -- weekly schedule, generous `start_to_close_timeout`, `max_attempts: 2`
- [x] `app/controllers/web/company/projects/skills_controller.rb` -- switch the default view to `CatalogSkill.popular`, keep live upstream search for the query path, backfill descriptions for rendered/featured entries via `download` guarded by `content_hash`
- [x] `test/support/fakes/fake_skills_registry.rb`, `test/services/skills/registry_client_test.rb`, `test/services/skills/catalog_sync_test.rb` -- WebMock contract tests for the client (incl. `400` on short query and `404 {"error":"not_found"}`), fake-driven sync tests for idempotency, bulk-publisher recomputation, and partial failure

**Execution — Phase 3 (manual authoring):**
- [x] `db/migrate/*_add_origin_to_skills.rb` -- `origin` (`registry` | `manual`, default `registry`, not null) + index
- [x] `app/models/skill.rb` -- require `source`/`package` only for `origin: registry`; `registry_url` nil for manual; keep per-scope name uniqueness
- [x] `app/services/skills/skill_markdown.rb` -- parse and validate pasted `SKILL.md`: frontmatter `name`/`description` per spec, reject `<`/`>` anywhere in frontmatter, cap body size against the progressive-disclosure budget, return derived name/description or field-specific errors
- [x] `config/routes.rb` + `app/controllers/web/company/projects/skills_controller.rb` -- a manual-create action taking pasted content; `name`/`description` derived from frontmatter only
- [x] `app/services/agents/*_adapter.rb` -- expose the per-agent skills directory as the agent's own config dir + `skills/`, matching where `skills add -g -a <agent>` places registry skills; assert parity against a CLI-installed skill rather than hardcoding a fresh map
- [x] `app/services/session_context_service.rb` -- write manual skills' directories into the container instead of invoking the CLI, recording per-skill ok/error like the CLI path does
- [x] `app/services/context_builders/resources.rb` -- ensure manual skills render in the `includes_skills_in_context?` branch
- [x] `app/services/personal_tools/create_skill.rb` -- MCP tool parity for manual creation, same policy authorization as `InstallSkill`
- [x] `app/frontend/shared/resources/skills/ManualSkillModal.tsx` + `SkillsContent.tsx` -- "Add manually" action beside catalog browse, monospace textarea, `skills init`-style starter content, server-error surfacing
- [x] `test/services/skills/skill_markdown_test.rb`, `test/services/session_context_service_test.rb`, `test/integration/.../skills_controller_test.rb`, `test/services/personal_tools/create_skill_test.rb`, `ManualSkillModal.test.tsx` -- validator rules incl. the angle-bracket ban, CLI-free delivery, tool authorization, modal behaviour

**Acceptance Criteria:**
- Given a project with no installed skills, when the Skills page loads with no query, then a populated catalog grid renders and no `larksuite/cli`-style publisher appears more than once.
- Given the sweep has never run, when the page loads, then the curated featured seed still renders (mirror absence degrades freshness, not the page).
- Given a session that includes any skill, when context injection runs, then no outbound request carries skill file contents (`DISABLE_TELEMETRY=1` on CLI installs; no CLI call at all for manual skills).
- Given `SKILLS_SH_API_KEY` is set in the environment, when a user searches, then results are unaffected (the key no longer participates).
- Given a manual skill exists in a project, when a session starts, then its directory is present in the container for the target runtime and the agent can load it by name.
- Given `make check_all` runs in Docker, then backend tests, rubocop, brakeman, eslint, tsc, and vitest all pass.

## Spec Change Log

- **2026-08-03 — production-readiness pass, plus two features the human asked for after the review.**
  - **Install resolution got a hard deadline.** Per-request timeouts were not a bound: download (10s) + well-known (3 × 5s) + raw guesses (3 × 8s) + the GitHub contents API (10s) + up to 15 raw reads (10s each) is ~200s inside a POST, and Puma's default `worker_timeout` is 60s and kills the WORKER — so one unlucky install would take every other request on that worker with it. `RESOLVE_DEADLINE` (15s) is checked between sources and inside the directory walk, and a timeout says so rather than claiming the skill does not exist.
  - **Hand-written skills are editable** (`PATCH .../skills/:id`, `PersonalTools::UpdateSkill`, the authoring modal reused in edit mode). Registry skills are deliberately excluded: their content belongs to the source they name, an edit would silently diverge from it, and the next install would clobber it. `SkillResource` exposes `content` for manual skills only — a registry SKILL.md can be tens of kilobytes and is not editable, so shipping it for every installed skill would be pure weight.
  - **Admin can trigger either catalog sync** (`/admin/catalog_syncs`), because both mirrors fill on a schedule and a fresh deployment would otherwise show an empty catalog for up to a week. The page starts the same Temporal workflow the schedule starts, under a stable workflow id so Temporal itself refuses a concurrent duplicate; the request never does the sweep. Caught while building it: enumerating admin routes for the nav link raises on any route without a dashboard, which would have broken **every** Administrate page — the override now skips dashboard-less routes and a test pins that existing admin pages still render.
  - **Description backfill reworked around a measured ceiling.** `/api/download` allows 60 requests/hour for the whole deployment, which installs also draw on. Descriptions now come from GitHub raw first (free, and what the CLI itself does), a run spends at most `DOWNLOAD_BUDGET` on the rest, and a 429 closes the download budget without stopping the free scan. Live effect: 62 → 441 described rows across two passes; the visible page fills first because the queue is ordered by the grid's own ranking.
  KEEP: a failed download is never treated as evidence that a row is a phantom — only rows upstream has never confirmed (`registry_synced_at IS NULL`) are dropped. The earlier recency-based check deleted 398 real rows on the first live backfill.

- **2026-08-03 — adversarial + edge-case review round; 37 findings after dedup, all material ones patched.**
  One finding was an intent gap and went back to the human, who renegotiated the frozen block (see the two entries below): the audit host and badges had been added on the implementer's own authority against `Always`/`Never`. Everything else was patched in place. The consequential ones, with what each avoided:
  - **Data loss:** every sweep re-wrote `title` to NULL (the search endpoint returns `name == slug` for most entries), permanently undoing the metadata backfill; and an absent `installs` could zero a real count. `CatalogUpsert` now uses an explicit `ON CONFLICT` clause (`COALESCE(excluded.title, …)`, `GREATEST(excluded.installs, …)`), so a re-sweep is strictly additive.
  - **Backfill starvation:** rows whose SKILL.md legitimately has no `description` were re-fetched every run forever and held the whole 60-row budget, including the curated seeds ordered first. Now every ATTEMPT stamps `registry_synced_at` and the queue orders by it, so it rotates; `backfilled` is counted only when a description actually landed.
  - **Write-on-GET by a read-only viewer:** `index` authorizes `project_accessible?` yet called `CatalogUpsert` and an outbound search per keystroke, letting any member of any tenant mutate a globally shared table by loading a URL. Typed queries now render unsaved records merged with mirrored rows; the weekly sweep owns the mirror. This also fixed the loss of upstream relevance order (results were being re-sorted by popularity) and `bulk_publisher` never being computed for search-cached rows.
  - **Manual authoring destroyed the user's paste:** an Inertia redirect with `alert:` is a *successful* visit, so `onSuccess` reset the textarea and closed the modal on every validation failure. Errors now travel as Inertia errors, render beside the field, and leave the draft intact.
  - **Root-owned skill directory:** the manual write bypassed the service's own `write_file` helper and defaulted to uid 0, which would leave `~/.claude` owned by root and make every later agent write fail with EACCES.
  - **Regression from the Phase 0 CLI-fallback removal:** publishers hosting their own skills have two-segment ids (`open.feishu.cn/lark-doc`, 519k installs) that `/api/download` cannot address, so they became uninstallable. Restored through `Skills::WellKnownResolver` (RFC 8615), with SSRF guards: https only, bare public hostname, no redirects, byte caps.
  - **Crashes on third-party JSON:** `worst_risk`/`audit_providers` raised on a provider value that was not an object (reproduced by the reviewer), and an unrecognised risk label silently became "never audited". Malformed entries are skipped; an unknown label now sorts as worst-known and warns.
  - Plus: a one-character query no longer empties the grid (frozen I/O matrix), `?catalog_q=` is dropped when the catalog closes, the audit batch is sliced (414 risk), stale verdicts are cleared when upstream withdraws them, the sweep has a wall-clock budget and per-row retry so one poisoned row cannot cost the page, `RecordNotUnique` is a flash rather than a 500, the GitHub walk is capped and no longer nested, upstream searches are cached for 5 minutes, `SkillsRegistryService` now delegates to `Skills::RegistryClient` instead of carrying a second copy of the transport, the install count no longer depends on which path installed the skill, `CreateSkill` authorizes `:manual?` like the route it mirrors, `SearchSkillRegistry` can browse without a query (frozen MCP-parity boundary), the sync activity reports `audited`, the migration is reversible, and the delete-wiring / description-fallback frontend tests that were dropped are restored.
  KEEP: the catalog identity is `registry_id`, never a database id — an entry can be a live upstream hit with no mirror row, and a nullable `id` in the prop contract is what made that ambiguous.

- **2026-08-03 — `/api/download` pulled forward from Phase 2 into Phase 0; the `yarn dlx skills` fallback was removed.**
  Finding: with the `/api/v1` branch gone, the only remaining install path was GitHub path-guessing followed by a `yarn dlx skills add` shell-out with a 120 s timeout — inside a web request, and untestable without mocking the class under test. The registry's own public `GET /api/download/{owner}/{repo}/{skill}` returns the whole bundle plus a content hash, so it is now the primary detail path with GitHub raw as fallback and no subprocess at all. Avoids: a request-path shell-out that tests could only cover by faking the service itself.
- **2026-08-03 — security audits added; the "no audit badges" boundary was based on a false premise.**
  Finding: reading `vercel-labs/skills` (the CLI's own source) showed it queries `GET https://add-skill.vercel.sh/audit?source=<owner/repo>&skills=<slug,…>` before every install — public, unauthenticated, batched per repository. Verified live: four providers (ath, socket, snyk, zeroleaks) return `risk`, `score`, `alerts`, `analyzedAt`, and **they disagree** (snyk rates `anthropics/skills/pdf` "high" while the others say "safe"). The spec's `Never: no security-audit badges` assumed the only audit surface was the OIDC-gated `/api/v1/skills/audit/...`. Since this feature injects third-party instructions into agent context and the catalog offers no ownership proof, the audit signal is the most valuable thing available and was implemented: `audit` jsonb + `audit_risk` + `audited_at` on `catalog_skills`, batched per source in the sweep, worst-verdict badge with a per-provider tooltip. Avoids: shipping a browse-and-install flow with no external judgement at all. KEEP: the full per-provider map is stored and shown — collapsing it to one verdict would hide the disagreement, and an unaudited skill renders no badge rather than a reassuring one.
- **2026-08-03 — telemetry claim corrected: paths, not contents.**
  Finding: `src/telemetry.ts` shows install events POST to `add-skill.vercel.sh/t` with `skillFiles` = JSON `{ skillName: relativePath }`. The skills.sh docs' phrase "the skill name, skill files, and a timestamp" reads as content egress; it is not. Comments, UI copy, tests and the research report were corrected. The decision stands unchanged — manual skills still bypass the CLI, because an install event naming a private skill and its path has no business leaving the deployment — but the justification is now accurate. Also confirmed from `src/agents.ts` that the per-agent `globalSkillsDir` values match what was implemented (`~/.claude/skills`, `~/.gemini/skills`, `~/.cursor/skills`, `$CODEX_HOME/skills`), and from `src/blob.ts` that `/api/download` is the CLI's own install path rather than a legacy endpoint.
- **2026-08-03 — ranking leads with `featured`/`bulk_publisher`, not `installs`; plus a hard dedup by source.**
  Finding: the spec's proposed `installs DESC, featured DESC, …` would have failed its own acceptance criterion. Measured over 3,702 sampled skills, `larksuite/cli` sums to 9.9M installs across ~25 near-identical entries, so leading with installs hands the grid to one publisher no matter what follows. `CatalogSkill::RANKING` therefore orders `featured DESC, bulk_publisher ASC, installs DESC, install_count DESC, registry_synced_at DESC`, and `one_per_source` (a `DISTINCT ON (source)` subquery) thins publishers out rather than merely ranking them — the penalty orders, it does not deduplicate. KEEP both: either alone leaves the Lark cluster visible.
- **2026-08-03 — `origin` + `content_hash` migration moved from Phase 3 to Phase 0, and name validation split by origin.**
  Finding: a single strict spec-shaped name rule would have broken registry installs — `inject_skills` passes `skill.name` to `skills add --skill <name>`, and upstream publishes names containing `_`, `:`, and digit-leading slugs (`3b1b-style-animation-skill` exists). Registry names are therefore accepted as published, while the spec charset is enforced only for `origin: manual`, whose name becomes a directory name. That required `origin` to exist earlier than planned; `content_hash` came along because the download endpoint hands it over for free. KEEP: length/format validations fire only `if: name_changed?`, so legacy rows stay saveable, and the `name=` setter no longer rewrites junk into underscores (it silently renamed skills).

## Design Notes

**Why the mirror is for browse, not search.** The MCP registry gave an `updated_since` cursor but no popularity; skills.sh gives popularity but no list endpoint on any surface we can reach. So the mirror exists to make a *default view* possible, while `/api/search` (fuzzy, up to 200 rows, `owner` filter) keeps serving typed queries. This is the inverse of `Connector`, where the mirror is authoritative.

**Ranking, and why counterweights are mandatory.** Measured over 3,702 sampled skills, `larksuite/cli` sums to 9.9M installs across ~25 near-identical skills at a flat 393–399k each — 15 of the top 25 by installs. Upstream `installs` leads the order because it is real and public, but `bulk_publisher` and dedup-by-source are what keep the grid from becoming a Lark advert:

```ruby
scope :popular, -> {
  order(Arel.sql("installs DESC, featured DESC, bulk_publisher ASC, install_count DESC, registry_synced_at DESC NULLS LAST"))
}
```

**Sweep shape.** `/api/search` is the only place install counts appear (~31 KB per 200 rows) and returns **no `description`**. Seeds come from the registry's own taxonomy (`/topic/*`, `/package/*`) plus `owner=` for large publishers; ~200 requests ≈ 6 MB per run, sequential with a short delay. Descriptions are backfilled via `/api/download` for featured/rendered entries only, `content_hash`-guarded.

**Telemetry is the reason manual skills bypass the CLI.** Per skills.sh CLI docs, telemetry includes "the skill name, skill files, and a timestamp" unless `DISABLE_TELEMETRY=1`. Routing a customer's hand-written skill through `skills add` would publish it.

## Verification

**Commands:**
- `docker compose exec -T web bin/rails db:migrate` -- expected: both migrations apply; `db/schema.rb` regenerated from the test DB only
- `docker compose exec -T web bin/rails test test/services/skills test/models/skill_test.rb test/integration/web/company/projects/skills_controller_test.rb` -- expected: green (run alone; backend suites must not overlap)
- `docker compose exec -T web ./node_modules/.bin/vitest run app/frontend/pages/Projects/Skills app/frontend/shared/resources/skills` -- expected: green
- `docker compose exec -T web make check_all` -- expected: green before any push
- `docker compose exec -T web bin/rails runner 'p Skills::CatalogSync.call'` -- expected: `Result` with `fetched > 0`, `failed == 0`

**Manual checks:**
- Skills page with no query shows a populated grid with install badges and at most one card per publisher.
- Manual-add modal rejects a `SKILL.md` whose frontmatter contains `<` or a name with `--`, with a field-specific message, and the pasted draft survives the rejection.
- Installing a skill whose worst audit verdict is `high`/`critical` requires acknowledging a warning first.
- After a session starts with a manual skill, the container holds the skill directory (owned by the agent's uid) and the session log shows no `npx skills add` for it.

## Suggested Review Order

**Ranking — the decision the whole catalog rests on**

- Order and per-publisher dedup; the comment carries the measurement that forced it.
  [`catalog_skill.rb:35`](../../app/models/catalog_skill.rb#L35)

- `DISTINCT ON (source)`: the penalty ranks publishers, this thins them out.
  [`catalog_skill.rb:44`](../../app/models/catalog_skill.rb#L44)

- Curated seed, with both signals (official repo, measured installs) explained.
  [`catalog_skill.rb:84`](../../app/models/catalog_skill.rb#L84)

**Reaching upstream — three public endpoints, nothing else**

- Transport: what each endpoint returns, and why `/api/v1` is unreachable.
  [`registry_client.rb:46`](../../app/services/skills/registry_client.rb#L46)

- Audit lookups, batched per repository; providers disagree, so all verdicts are kept.
  [`registry_client.rb:119`](../../app/services/skills/registry_client.rb#L119)

- RFC 8615 discovery: the only route to non-GitHub publishers, with SSRF guards.
  [`well_known_resolver.rb:49`](../../app/services/skills/well_known_resolver.rb#L49)

- Host validation — the reason this service can be pointed at a hostile name safely.
  [`well_known_resolver.rb:76`](../../app/services/skills/well_known_resolver.rb#L76)

**The sweep — incomplete by construction, and honest about it**

- Why a sweep and not a walk; seeds come from the registry's own taxonomy.
  [`catalog_sync.rb:27`](../../app/services/skills/catalog_sync.rb#L27)

- Explicit `ON CONFLICT`: a re-sweep must never undo the backfill or zero a count.
  [`catalog_upsert.rb:17`](../../app/services/skills/catalog_upsert.rb#L17)

- Backfill rotation, so descriptionless rows cannot hold the budget forever.
  [`catalog_sync.rb:279`](../../app/services/skills/catalog_sync.rb#L279)

- Withdrawn verdicts are cleared; an unreachable endpoint is not evidence.
  [`catalog_sync.rb:225`](../../app/services/skills/catalog_sync.rb#L225)

- Phantom curated seeds are dropped rather than left as cards that fail on click.
  [`catalog_sync.rb:318`](../../app/services/skills/catalog_sync.rb#L318)

- Wall-clock budget: 100 searches of timeouts must not outlast the activity.
  [`catalog_sync.rb:114`](../../app/services/skills/catalog_sync.rb#L114)

**Serving the page — a GET that writes nothing**

- Blank/short query → mirror; typed query → upstream order, unsaved records.
  [`skills_controller.rb:100`](../../app/controllers/web/company/projects/skills_controller.rb#L100)

- Mirrored rows reused so results keep descriptions and audit verdicts.
  [`skills_controller.rb:126`](../../app/controllers/web/company/projects/skills_controller.rb#L126)

- Manual create: errors as Inertia errors, so a rejection never eats the draft.
  [`skills_controller.rb:49`](../../app/controllers/web/company/projects/skills_controller.rb#L49)

**Authoring and delivery**

- Spec validation, including the angle-bracket ban and the size caps.
  [`skill_markdown.rb:45`](../../app/services/skills/skill_markdown.rb#L45)

- Name rules split by origin: upstream slugs verbatim, manual names spec-strict.
  [`skill.rb:30`](../../app/models/skill.rb#L30)

- Registry installs with telemetry off; the slug comes from `package`, not `name`.
  [`session_context_service.rb:226`](../../app/services/session_context_service.rb#L226)

- Manual skills written where the CLI would have put them, with the agent's uid.
  [`session_context_service.rb:273`](../../app/services/session_context_service.rb#L273)

**Browse UI**

- A flagged verdict interrupts the install instead of decorating it.
  [`SkillsCatalogModal.tsx:101`](../../app/frontend/shared/resources/skills/SkillsCatalogModal.tsx#L101)

- Closing drops `?catalog_q=`, so a shared URL opens on the default view.
  [`SkillsCatalogModal.tsx:162`](../../app/frontend/shared/resources/skills/SkillsCatalogModal.tsx#L162)

- Draft-preserving submit: only success resets and closes.
  [`ManualSkillModal.tsx:35`](../../app/frontend/shared/resources/skills/ManualSkillModal.tsx#L35)

**Schema, schedule, peripherals**

- Mirror table: why it is disposable, and the generated `search_vector`.
  [`20260803000002_create_catalog_skills.rb:1`](../../db/migrate/20260803000002_create_catalog_skills.rb#L1)

- `origin` + `content_hash` — the discriminator everything else keys off.
  [`20260803000001_add_origin_and_content_hash_to_skills.rb:1`](../../db/migrate/20260803000001_add_origin_and_content_hash_to_skills.rb#L1)

- Audit columns: whole per-provider map stored, worst verdict denormalised.
  [`20260803000003_add_audits_to_catalog_skills.rb:1`](../../db/migrate/20260803000003_add_audits_to_catalog_skills.rb#L1)

- Weekly schedule, with the reason browse-only staleness is acceptable.
  [`schedules.yml:54`](../../app/temporal/schedules.yml#L54)

- The fake every layer above the transport is tested through.
  [`fake_skills_registry.rb:1`](../../test/support/fakes/fake_skills_registry.rb#L1)

- Sweep behaviour: idempotency, additive re-sweeps, audit clearing, partial failure.
  [`catalog_sync_test.rb:1`](../../test/services/skills/catalog_sync_test.rb#L1)
