---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Skills page parity with the MCP connector catalog — featured/popular skills + manual skill authoring'
research_goals: 'Decide how to source and rank a browsable skills catalog (featured/popular) the way the MCP connector catalog does, and design a manual "add a skill by hand" path.'
user_name: 'Artem_petrov'
date: '2026-08-03'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-08-03
**Author:** Artem_petrov
**Research Type:** technical

---

## Research Overview

This report answers a narrow product request — *make the Skills page behave like the
Connectors page: open on featured/popular skills, and allow adding a skill by hand* —
and finds that the two pages cannot be built the same way, because the two upstream
registries have opposite strengths. The Official MCP Registry offers an incremental
`updated_since` walk but publishes **no popularity signal**, which is why
`Connector#popular` had to lead with our own install count. skills.sh publishes **real
install counts** but offers **no browse or list endpoint on any surface we can reach**:
its documented `/api/v1` leaderboard is authenticated by Vercel OIDC token only
(verified `401`), and no public leaderboard, trending, or list endpoint exists
(verified `404` on five candidates). So the connector architecture inverts here — the
mirror exists to provide *browse*, while search stays live upstream.

Along the way the research surfaced three defects in the current code, independent of
the feature: the authenticated skills.sh path is dead (an unrelated `SKILLS_SH_API_KEY`
would silently break search), the `Skill` name validation contradicts the Agent Skills
spec in ways that make a skill fail to load in the agent, and — the significant one —
`SessionContextService#inject_skills` runs the skills CLI **without**
`DISABLE_TELEMETRY=1`, so every session install reports skill name *and skill files*
to skills.sh. That last one decides the manual-add design: hand-written, potentially
proprietary skills must be written into the container directly rather than routed
through `skills add`.

The recommendation is a curated featured seed first (a small controller change plus a
constant, behind the same props contract the connector modal already uses), then a
sweep-built mirror on a weekly Temporal schedule, then manual add. Empirical ranking
data collected for this report (3,702 skills sampled) shows why the connector
catalog's `bulk_publisher` penalty is mandatory rather than optional: a naive
`ORDER BY installs DESC` puts fifteen consecutive `larksuite/cli/lark-*` entries at the
top of the page. The full executive summary, decision table, and roadmap are in
**Research Synthesis** at the end of this document.

---

## Technical Research Scope Confirmation

**Research Topic:** Skills page parity with the MCP connector catalog — featured/popular skills + manual skill authoring

**Research Goals:** Make the Skills page behave like the Connectors page shipped in `3e586d7b`: open on something browsable (featured / most popular skills) instead of an empty search box, and add a first-class path for registering a skill by hand rather than only from the registry.

### Starting Position in This Codebase

Established by reading the code, not assumed:

- `MCP::ConnectorCatalogSync` mirrors the Official MCP Registry into a global `connectors` table on a weekly Temporal schedule; the walk is watermark-driven and gap-tolerant (`app/services/mcp/connector_catalog_sync.rb`).
- `Connector.popular` ranks by `install_count DESC, featured DESC, bulk_publisher ASC, vendor_tier ASC, registry_updated_at DESC`, and `Connector::FEATURED` seeds a cold catalog with 64 curated registry names (`app/models/connector.rb`).
- Catalog search is Postgres full-text over the mirror, because the upstream registry API can only match server-name substrings.
- `ConnectorCatalogModal` renders a "Suggested connectors" grid with locally drawn monogram fallbacks, `vendor` / `deprecated` badges, and a separate install modal.
- Skills have **no mirror**. `SkillsRegistryService.search` calls skills.sh live and returns `[]` for queries under 2 characters, so the page cannot show anything before the user types (`app/services/skills_registry_service.rb`, `SkillsContent.tsx`).
- Unlike the MCP registry, skills.sh **does** return an `installs` figure, which the UI already sorts on client-side.
- Manual registration does not exist: `SkillsController#create` accepts only a registry `skill_id`, and `Skill` requires `package`, `source`, and `content` to be present.

### Scope

1. **Registry capabilities** — what the skills.sh API actually exposes (browse / popular / trending / list endpoints, pagination, bulk export), auth requirements, rate limits, stability.
2. **Architecture: mirror vs live** — whether to repeat the connector pattern (mirror table + tsvector + scheduled sync) or serve a curated featured list plus live search; which ranking signals genuinely exist for skills.
3. **Sources** — skills.sh alone or multiple registries (Anthropic's own skills repo, plugin marketplaces, community indexes); format compatibility, licensing, deduplication.
4. **Manual add** — the Agent Skills `SKILL.md` specification (frontmatter fields, progressive disclosure, bundled `scripts/` / `references/` directories, size limits), what breaks in the current `Skill` model, and how a hand-written skill reaches the agent container.
5. **Security** — a `SKILL.md` is instructions injected into an agent's context by design; hand-added skills that carry executable files widen that; who may add them.

**Explicitly out of scope (decision, 2026-08-03):** company-scoped skills. Skills stay project-scoped, matching the existing `Skill` validation (`scope_type` inclusion `%w[Project]`).

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-08-03

---

## Technology Stack Analysis

Scope note: the generic stack questions (languages, cloud, containers) are already
settled for this codebase — Rails 8 + Inertia/React + Postgres + Temporal, all in
Docker. So this section analyses the stack that is actually undecided: **where
skill catalog data comes from, in what format, and what tooling moves it around.**
Every claim below that is marked *verified* was checked by calling the endpoint
directly on 2026-08-03, not inferred from documentation.

### Registry APIs and Data Sources

**skills.sh v1 API — documented, but effectively closed to us.**
Five endpoints are documented: `GET /api/v1/skills` (leaderboard, `view` =
`all-time` | `trending` | `hot`, `page`, `per_page` 1–500), `GET /api/v1/skills/search`
(`q` ≥ 2 chars, `limit` 1–200, `owner`), `GET /api/v1/skills/curated`,
`GET /api/v1/skills/{source}/{skill}`, and `GET /api/v1/skills/audit/{source}/{skill}`.
Rate limit 600 req/min per team+project.

The blocker is authentication. The only documented method is a **Vercel OIDC
token** — "Authenticate with your project's Vercel OIDC token" — minted per
Vercel project and rotated automatically. No API-key signup exists for a service
hosted anywhere else.

*Verified:* `GET https://skills.sh/api/v1/skills?per_page=2` →
`401 {"error":"authentication_required","message":"This endpoint requires
authentication. Pass a Vercel OIDC token (Authorization: Bearer <VERCEL_OIDC_TOKEN>)"}`.
Same for `/api/v1/skills/curated`.

**Direct consequence for this codebase:** `SkillsRegistryService`'s authenticated
path is dead code. It sends `Authorization: Bearer #{Settings.skills_sh.api_key}`
(`SKILLS_SH_API_KEY`), which is not an OIDC token, so every request would 401 and
fall through to `[]` — and since the key is unset anyway, production has always
been running the `search_public` fallback. Confidence: high (endpoint response
quoted above + the code path read).

An open upstream request for exactly this (`vercel-labs/skills` issue #1053,
"Request API key for skills.sh official API downloads") has **no maintainer reply**
and remains open, so an official key is not something to plan around.

**Public legacy endpoints — undocumented but live and unauthenticated.**

- *Verified:* `GET https://www.skills.sh/api/search?q=react&limit=2` → `200`, body
  `{query, searchType: "fuzzy", skills: [{id, skillId, name, installs, source}]}`.
  `limit=200` returns 200 results. `q` shorter than 2 chars, or `q=*`, → `400`.
  Results are ordered by **fuzzy relevance, not installs** (verified: `q=ai`
  returns `vercel/ai/ai-sdk` at 44,854 installs ahead of `microsoft/azure-skills/azure-ai`
  at 496,056), which is why the current UI re-sorts client-side.
- *Verified:* `GET https://www.skills.sh/api/download/{owner}/{repo}/{skill}` →
  `200 application/json` with the full `files[]` array (`path` + `contents`). The
  probe returned 243 KB for a single skill, i.e. this endpoint carries the whole
  bundle, not just `SKILL.md`.
- *Verified absent:* `/api/leaderboard`, `/api/trending`, `/api/skills`, `/api/top`,
  `/api/stats` all `404`. **There is no public popularity endpoint.** This is the
  central constraint on a "most popular skills" view.

**Sitemaps — a legitimate enumeration surface.**
*Verified:* `sitemap.xml` indexes `sitemap-misc.xml` (187 URLs),
`sitemap-owners.xml` (17,149 owners), `sitemap-skills-1.xml` and
`sitemap-skills-2.xml` (10,000 skill URLs each → 20,000 skills enumerated). The
first entries are the well-known ones (`vercel-labs/skills/find-skills`,
`anthropics/skills/frontend-design`), suggesting the file is emitted in some
popularity order, though the sitemap format carries no rank field — treat ordering
as a weak hint, not a signal. Confidence: medium for the ordering claim, high for
the counts.

`sitemap-misc.xml` also reveals the site's own taxonomy, all crawlable pages:
`/hot`, `/trending`, `/picks`, `/official`, `/audits`, `/topic/<slug>` (react,
nextjs, design, mobile, agent-workflows, databases, testing, marketing, …),
`/agent/<slug>` (claude-code, …), `/package/<npm|go|cargo|pip>`. This is a
ready-made browse structure that a catalog UI could mirror conceptually.

*Verified caveat:* those pages are largely client-rendered. `/picks` yielded only
6 skill links in the served HTML and `/official` and `/agent/claude-code` yielded
zero, so HTML parsing of the rankings is brittle and not a dependable data source.

**Terms and robots — caching is explicitly blessed, crawling `/api/` is not.**
The Terms (site operated by Vercel) state: *"Use of the public API is rate-limited
per IP. Programmatic abuse, scraping that bypasses the rate limit, or use that
materially degrades service for others may result in IP-level blocks"* and,
decisively for a mirror design, *"Reasonable use, including caching results on your
own infrastructure, is encouraged and not restricted."* Skill content stays the
property of its authors under the licenses in their source repositories.

Meanwhile `robots.txt` is `Allow: /` with `Disallow: /internal/`, `/debug-security/`,
`/search`, `/api/`. So: caching API results — explicitly fine; running a crawler
over `/api/` — against the robots directive; parsing the HTML ranking pages —
allowed by robots but brittle per above.

**Third-party mirror: `mastra-ai/skills-api` (MIT).** Self-hostable API server that
builds its own index by **scraping** (`pnpm scrape`, plus `fetchSkillFromGitHub()`),
covering "34,000+ skills from 2,800+ repositories", and exposes what skills.sh
withholds publicly: `GET /api/skills`, `/api/skills/top` (by installs),
`/api/skills/sources/top`, `/api/skills/stats`. No hosted instance, no dataset dump.
Useful mainly as **precedent that install counts can be assembled independently** —
adopting it would mean owning a scraper, which is strictly worse than the two
options this codebase already has (curated seed; own install counts).

**Curated upstream sources for a featured seed.**
`anthropics/skills` is the official Agent Skills repository (~149k stars as of
June 2026, 17 top-level skill directories per an April 2026 snapshot) — the exact
analogue of the vendor-verified group in `Connector::FEATURED`. `skills.sh/official`
and `skills.sh/picks` are the registry's own curation lists. Confidence on star
count: medium (single secondary source, not verified against the GitHub API).

### Skill Format and Packaging

The format is now an open standard at `agentskills.io`, adopted well beyond Claude
(GitHub Copilot, VS Code, Cursor, Codex, Gemini CLI, Goose, OpenCode, ~40 clients).
Full spec, quoted:

| Field | Required | Constraints |
| --- | --- | --- |
| `name` | Yes | 1–64 chars, lowercase `a-z0-9` + hyphens, no leading/trailing hyphen, no `--`, **must match the parent directory name** |
| `description` | Yes | 1–1024 chars, non-empty; must say what it does *and* when to use it |
| `license` | No | License name or bundled license file |
| `compatibility` | No | ≤500 chars; environment requirements |
| `metadata` | No | Arbitrary string→string map |
| `allowed-tools` | No | Space-separated pre-approved tools, e.g. `Bash(git:*) Read`. Experimental |

Directory layout: `SKILL.md` (required) plus optional `scripts/` (executables),
`references/` (on-demand docs), `assets/` (templates, images, data). Progressive
disclosure is three-tier: metadata (`name` + `description`, ~100 tokens) always
loaded, `SKILL.md` body (< 5000 tokens recommended, ≤ 500 lines) on activation,
bundled files only when needed. Validation tooling exists: `skills-ref validate ./my-skill`.

Spec-level safety note worth carrying into any authoring form: **avoid angle
brackets in frontmatter**, because they can inject unintended instructions into the
system prompt.

**Gap against our schema:** `Skill` stores a single `content` column (one
`SKILL.md`) and requires `package` and `source`. A spec-complete skill is a
*directory*, and the public `/api/download` endpoint already returns multi-file
bundles that we currently discard except for `SKILL.md`. Both the manual-add path
and any registry install that carries `scripts/` hit this.

### Injection Tooling — How a Skill Reaches the Agent

`SessionContextService#inject_skills` shells out per skill inside the container:
`npx -y skills add <source> --skill <name> -a <agent> -g --copy -y`. Two properties
of that follow from the CLI's own capability set:

- Every installed skill must be resolvable by the CLI from a **remote source**.
  A hand-written skill that exists only in our database has no `source` to pass,
  so manual add cannot reuse this code path unchanged.
- The CLI does, however, accept `add` from a **local directory** (`./my-local-skills`),
  a **single `SKILL.md` URL**, an **archive** (`.zip`, `.tar`, `.tar.gz`, `.tgz`),
  an **arbitrary git URL** (`git@github.com:owner/repo.git`), a GitLab URL, and a
  deep `https://github.com/owner/repo/tree/main/skills/<name>` path. Other commands:
  `use`, `list`/`ls`, `find` (keyword or interactive fzf search, `--owner` filter),
  `update`, `remove`/`rm`, `init` (scaffolds a SKILL.md template).

So a manual skill has two plausible delivery mechanisms: write the directory into
the container ourselves, or materialise it to a temp dir and `skills add ./dir`.
There is no CLI `browse`/`popular` command, confirming again that ranking data has
to come from us.

Also relevant: `adapter.includes_skills_in_context?` short-circuits injection
entirely for runtimes that get skills as context text instead of files
(`Agents::BaseAdapter`, used by `ContextBuilders::Resources`) — a manual-add design
has to satisfy both delivery shapes.

### Storage and Ranking Stack (What We Already Own)

Nothing new is needed. The connector catalog established the whole pattern inside
this stack: a global mirror table, `upsert_all` by natural key, a generated
`search_vector` with `websearch_to_tsquery` ranked search, a weekly Temporal
schedule, and a recomputed-not-incremented ranking pass
(`ConnectorCatalogSync#refresh_ranking`) that derives `install_count` from actual
installs and `bulk_publisher` from the mirror's own distribution.

The single meaningful difference for skills: **skills.sh publishes a real
`installs` figure per skill and the MCP registry publishes nothing.** That inverts
the ranking problem. `Connector#popular` had to lead with our own install count
because upstream offered no signal; a skills catalog can lead with upstream installs
(hundreds of thousands for the top entries — 600,754 for
`vercel-labs/agent-skills/vercel-react-best-practices`, verified) and use our own
count only as a secondary, first-party signal. The privacy argument for hiding the
exact number does not transfer either: upstream installs are already public data,
so a skill card *can* display "600.7K installs" the way the existing UI does.

### Ecosystem Scale and Adoption Trends

Catalog size claims disagree by an order of magnitude and should be treated with
care: skills.sh's own API announcement says "more than 600,000 skills"; its
sitemaps enumerate 20,000 (*verified*) across 17,149 owners (*verified*);
`mastra-ai/skills-api` reports 34,000+ from 2,800+ repositories. The plausible
reconciliation is that 600k counts every skill directory discovered across GitHub
while the sitemap publishes a curated/ranked subset — unconfirmed. Confidence: low
on any single figure, high that the browsable set is tens of thousands, not
hundreds.

Trend signals worth noting for the design: the format went open standard
(December 2025) and is now multi-runtime, which means a catalog keyed to "Claude
skills" would be mis-scoped; skills.sh ships a **security audit** endpoint and an
`/audits` page, i.e. the ecosystem already treats third-party skills as a supply-chain
risk surface; and the registry's own taxonomy (`topic/`, `agent/`, `package/`)
suggests browsing by topic matters more here than for MCP connectors, where a flat
popularity grid sufficed.

_Sources:_
- https://www.skills.sh/docs/api
- https://vercel.com/changelog/the-skills-sh-api-is-now-available
- https://github.com/vercel-labs/skills/issues/1053
- https://raw.githubusercontent.com/vercel-labs/skills/main/README.md
- https://www.skills.sh/terms, https://www.skills.sh/robots.txt, https://www.skills.sh/sitemap.xml
- https://agentskills.io/specification
- https://github.com/anthropics/skills
- https://github.com/mastra-ai/skills-api
- Direct endpoint probes, 2026-08-03 (documented inline above)

---

## Integration Patterns Analysis

Two integrations decide this feature: **inbound** (how catalog data and skill
bundles get from skills.sh into our Postgres) and **outbound** (how a skill —
registry or hand-written — reaches a running agent container). A third, smaller
one is internal: the Inertia and MCP-tool contracts the UI and agents both call.

### Inbound API Patterns — Ingestion Without an `updated_since`

The usable public surface is exactly two endpoints, both verified on 2026-08-03:

| Call | Verified behaviour |
| --- | --- |
| `GET /api/search?q=<≥2 chars>&limit=<≤200>&owner=<gh-owner>` | `200`, `{query, searchType, skills:[{id, skillId, name, installs, source}]}`. `owner` **works on the public endpoint too** (`q=design&owner=anthropics` → 5 anthropics-only hits), which the docs only claim for `/api/v1`. ~31 KB per 200 results. |
| `GET /api/download/{owner}/{repo}/{skill}` | `200`, `{files:[{path, contents}], hash}`. Serves any registry-known skill (`obra/superpowers/test-driven-development` → 18 KB, `anthropics/skills/frontend-design` → `LICENSE.txt` + `SKILL.md`). Unknown skill → `404 {"error":"not_found"}`. |

Two consequences follow directly:

**1. The connector ingestion pattern does not port.** `ConnectorRegistryClient.each_updated_since`
works because the MCP registry exposes a cursor plus `updated_since`, which is what
makes `ConnectorCatalogSync` resumable and gap-tolerant. skills.sh publishes
**neither** (*verified absent:* no list, no leaderboard, no `updated_since` on any
public path). Any skills mirror must therefore be built from **fan-out reads**, and
its freshness model is "re-derive periodically", not "resume from a watermark".

**2. There is a cheap fan-out shape, and an expensive one.** The `/api/search`
response is the only place install counts appear, and it returns up to 200 rows for
~31 KB. A sweep of ~200 queries — seeded from the registry's own published taxonomy
(`/topic/react`, `/topic/testing`, `/topic/design`, `/topic/databases`,
`/topic/agent-workflows`, … plus `/package/{npm,go,cargo,pip}` and `owner=` for the
large publishers) — is ~200 requests and ~6 MB, and yields tens of thousands of
`{id, source, installs}` rows. That is one order of magnitude cheaper than
enumerating the 20,000 sitemap URLs and downloading each bundle (18–240 KB per
skill ⇒ hundreds of MB and 20,000 requests). Confidence: high on the per-response
sizes (measured), medium on total coverage of a keyword sweep — a sweep finds what
its seeds reach, so coverage is a tunable, not a guarantee.

Design note: a sweep-built mirror is *by construction* incomplete, so the search box
must keep hitting `/api/search` live for the long tail while the mirror only powers
the **default/featured view**. That is the inverse of the connector design, where
the mirror is authoritative because the upstream search is too weak to use. Here
the upstream search is fine (fuzzy, 200 rows, `owner` filter); what upstream lacks
is a *browse* surface.

**Integrity and change detection.** `/api/download` returns a `hash` alongside the
files (*verified*). This is a better update trigger than timestamps: a stored
`content_hash` makes "has this skill changed since we installed it" a single
comparison, and it gives an install-time pin for hand-inspected skills. The MCP
side has no equivalent.

**Fallback path economics.** `SkillsRegistryService` currently falls back to GitHub:
`raw.githubusercontent.com` guesses plus `GET /repos/{source}/contents/skills` walks.
*Verified:* unauthenticated GitHub API allows **60 requests/hour** per IP
(`api.github.com/rate_limit` → `{"limit":60}`), shared across the whole deployment.
The directory-listing walk can burn several requests per install, so this fallback
is viable only as an occasional install-time rescue — never for catalog building.
*Verified* upside: the layout guess is right for the flagship repo — `anthropics/skills`
root contains `.claude-plugin`, `skills`, `spec`, `template`, so skills do live under
`skills/`.

### Internal Contracts — UI and Agent Tooling

**Inertia partial reload is already the established seam for catalog browsing.**
Connectors: `router.get(pagePath, {connector_q: value}, {only: ['connectors','connectorQuery'], preserveState, replace})`
behind a 300 ms debounce, with a spinner because results come from a server round
trip. Skills: `router.reload({data: {q}, only: ['registryQuery','registryResults']})`
behind a 400 ms debounce. Same pattern, so a featured grid needs no new mechanism —
only props that are populated **when the query is empty**, which today they are not
(`search_registry` returns `[]` for blank `q`, and `SkillsRegistryService.search`
returns `[]` under 2 chars).

**Install contracts differ in shape and that difference is instructive.** A
connector install POSTs a *chosen target plus config-item bindings*
(`ConnectorInstallModal`), because a registry manifest describes several possible
transports and needs secrets wired. A skill install POSTs only `skillId`, because a
skill is inert text. Manual add therefore needs a genuinely new third contract:
a body carrying the skill *content itself* (and possibly extra files) rather than a
reference to something remote.

**MCP-tool parity is a platform convention, not an optional extra.** Every
UI-reachable skill operation already has an agent-facing tool:
`PersonalTools::SearchSkillRegistry` / `InstallSkill` (takes `project_id` +
registry `skill_id`, authorizes through `Web::Company::Projects::SkillsPolicy`) /
`UninstallSkill` / `ListSkills`, mirrored by the `MetaSearchSkills` /
`MetaInstallSkill` / `MetaListSkills` internal tools. If manual add lands only in
the web UI, agents lose an ability the UI has — and an agent authoring a skill for
its own future sessions is one of the more obvious uses of the feature.

**Typed props.** `SkillResource` feeds the generated frontend types, so any new
field (content, files, origin, hash) is a resource change plus a type regeneration,
not an ad-hoc prop.

### Outbound Integration — Delivering a Hand-Written Skill

`SessionContextService#inject_skills` runs, per skill, inside the container:
`npx -y skills add <source> --skill <name> -a <agent> -g --copy -y` with a 30 s
timeout, sequentially, recording per-package `ok` / `error`. A manual skill has no
`source`, so this exact call cannot serve it. Three integration options, all
supported by the CLI's documented input formats:

1. **Write the directory ourselves.** We already push files into containers for
   context injection, so materialising `~/.claude/skills/<name>/SKILL.md` (plus
   `references/`, `assets/`) is the least-moving-parts option and works offline.
   It bypasses the CLI entirely, which also means bypassing whatever the CLI does
   per agent runtime (`-a claude-code|gemini|cursor` path differences already
   encoded in `skills_agent_name`).
2. **`skills add ./local-dir`.** Write a temp dir in the container, let the CLI place
   it. Keeps one code path for registry and manual skills and preserves per-agent
   placement; costs an extra `npx` cold start.
3. **`skills add <url-to-SKILL.md>`** — the CLI accepts a single `SKILL.md` URL or a
   `.zip`/`.tar.gz` archive. Elegant (the platform serves its own skills as an
   archive endpoint) but requires that URL to be reachable and authenticated from
   inside the container, which is new exposure for no functional gain over (1).

Whichever is chosen must also satisfy the second delivery shape: when
`adapter.includes_skills_in_context?` is true, `inject_skills` returns early and the
skill text flows through `ContextBuilders::Resources` into the context file instead.
A manual skill stored as a file bundle rather than a single `content` string has to
render into that path too.

### Data Format Decisions Forced by This

The spec's unit is a *directory*; our column is a single `content` string. The
download endpoint hands us `files:[{path, contents}]` and we currently keep only
`SKILL.md`, discarding `scripts/`, `references/`, `assets/`. Any design that
supports manual add spec-completely has to pick a representation: JSONB `files`
array on `skills`, a child table, or object storage — with the caveat that
`scripts/` is executable content, which is a security decision before it is a
storage one (below).

### Integration Security Patterns

**The audit signal exists upstream but is unreachable.** skills.sh has
`GET /api/v1/skills/audit/{source}/{skill}` (provider, status, summary, `riskLevel`)
and a public `/audits` page — but the v1 endpoint is OIDC-gated (*verified 401*) and
the page is client-rendered. So a "security-audited" badge cannot be sourced today.
Worth re-checking if keys ever open up, because it maps exactly onto the trust
badges the connector catalog already shows.

**No verification tier is available the way it was for connectors.**
`Connector#vendor_published?` works because the MCP registry verifies namespaces by
DNS/HTTP challenge. A skills.sh id is `owner/repo/skill` — a GitHub coordinate with
no ownership proof attached. The honest analogues are: membership in the registry's
own `/official` or `/picks` lists, GitHub org-vs-user, and repository stars (with
the same "stars measure the repo, not the skill" caveat already documented in
`Connector::FEATURED`). Anything stronger would be invented.

**A skill is instructions injected into an agent's context — by design.** That is
the same trust class as an MCP server description, but larger and unstructured. For
manual add specifically:

- Validate frontmatter server-side against the spec (`name` 1–64, `[a-z0-9-]`, no
  leading/trailing or doubled hyphen, must equal the directory name; `description`
  1–1024). Our existing `Skill` name regex `\A[a-z][a-z0-9_:-]*\z` **permits
  underscores and colons the spec forbids and does not cap length**, so
  spec-invalid names can already be stored — and a name that does not match its
  directory silently fails to load in the agent.
- Reject angle brackets in frontmatter: the spec warns they "can inject unintended
  instructions into the system prompt".
- Cap size against the progressive-disclosure budget (body < 5000 tokens / ≤ 500
  lines recommended) rather than an arbitrary byte limit.
- Treat `scripts/` as a separate, later decision: executables authored in a web form
  and run inside an agent container is a strictly bigger blast radius than markdown,
  and nothing about the featured/browse goal requires it.
- Authorization already exists and should be reused, not reinvented:
  `SkillsPolicy` + the `canExecute` gate the UI applies to registry installs.

_Sources:_
- Direct endpoint probes, 2026-08-03: `/api/search` (with `owner`), `/api/download/{owner}/{repo}/{skill}` (200 + `hash`, 404 shape), `api.github.com/rate_limit` (60/hr)
- https://www.skills.sh/docs/api (v1 endpoints incl. audit; OIDC auth)
- https://raw.githubusercontent.com/vercel-labs/skills/main/README.md (CLI input formats: local dir, single SKILL.md URL, archives, git URLs)
- https://agentskills.io/specification (name/description constraints, progressive-disclosure budgets, angle-bracket warning)
- https://api.github.com/repos/anthropics/skills/contents/ (repo layout)
- Codebase: `app/services/session_context_service.rb`, `app/services/skills_registry_service.rb`, `app/services/personal_tools/*skill*.rb`, `app/frontend/shared/resources/{skills,connectors}/*`

---

## Architectural Patterns and Design

### What "Installs" Actually Measures — and Why It Changes the Ranking Design

Before choosing an architecture, the one number the whole feature would lean on had
to be pinned down. skills.sh's own docs: *"By default, the CLI collects anonymous
telemetry data to help rank skills on the leaderboard"*, and the data *"includes the
skill name, skill files, and a timestamp — no personal or device information is
collected"*, with opt-out via `DISABLE_TELEMETRY=1`. The FAQ adds only that
*"aggregated installation counts help surface the most popular skills"* and that the
leaderboard is *"powered by anonymous telemetry data from the skills CLI"*. Neither
document defines whether a count is per skill or per repository, nor mentions
de-duplication or anti-gaming measures. (One secondary source names the opt-out
variable `SKILLS_NO_TELEMETRY=1`; the official CLI docs say `DISABLE_TELEMETRY=1`.
Prefer the docs — and note our `SkillsRegistryService#fetch_skill_md_via_cli`
already sets `DISABLE_TELEMETRY=1`, so it is on the right side of that conflict.)

**Measured on 2026-08-03** by sweeping 20 topic queries over the public search
endpoint (3,702 unique skills collected — itself a useful calibration of the sweep
idea from step 3), ranking by `installs`:

| installs | skill |
| --- | --- |
| 734,415 | `anthropics/skills/frontend-design` |
| 624,680 | `mattpocock/skills/grill-with-docs` |
| 616,655 | `vercel-labs/agent-browser/agent-browser` |
| 600,754 | `vercel-labs/agent-skills/vercel-react-best-practices` |
| 518,503 | `open.feishu.cn/lark-doc` |
| 510,740 | `vercel-labs/agent-skills/web-design-guidelines` |
| 495,744 | `microsoft/azure-skills/azure-deploy` |
| 399,527 … 393,191 | **fifteen consecutive `larksuite/cli/lark-*` entries** |

Summed by source, `larksuite/cli` totals **9.9M installs across ~25 near-identical
skills**, more than 4× the next publisher. Within that namespace the per-skill
figures are implausibly flat (393k–399k across entirely different skills:
`lark-mail`, `lark-whiteboard`, `lark-task`…), which is what a **repo-level install
counted against every skill in the repo** looks like. Confidence: high that the
signal is inflated for multi-skill repos, medium on the exact mechanism (the docs
do not say).

Two design conclusions, both of which the connector catalog already anticipated:

1. **A raw `ORDER BY installs DESC` catalog would show fifteen Lark skills above
   everything else.** The `bulk_publisher` penalty invented for connectors is not
   optional here — it is the difference between a usable featured grid and a Lark
   advert. Dedup-by-source ("one best skill per publisher") produces an immediately
   sane list: `anthropics/skills/frontend-design`, `mattpocock/skills/grill-with-docs`,
   `vercel-labs/agent-browser`, `vercel-labs/agent-skills/vercel-react-best-practices`,
   `microsoft/azure-skills/azure-deploy`, `supabase/agent-skills/supabase-postgres-best-practices`,
   `shadcn/ui/shadcn`, `obra/superpowers/*` …
2. **Upstream installs are evidence, not truth.** Telemetry-based, opt-out-able, and
   as one review puts it, *"the only ranking mechanism is install count, which can be
   gamed, and which doesn't correlate with quality"*. Show it, lead with it, but keep
   a curated seed and our own first-party count as counterweights — exactly the
   layered scheme in `Connector#popular`.

### System Architecture Options

**Option A — Curated seed only, no mirror.**
Add a `Skill::FEATURED` constant (registry ids), fetch those on demand or cache them
in a small table, keep live `/api/search` for everything else. Cheapest possible
change; no scheduled job, no new sync failure modes. Cost: the featured list is
whatever we typed, it ages by hand, and "most popular" would be a claim we cannot
back — the same honesty problem that made the connector modal say "Suggested
connectors" rather than "most installed".

**Option B — Sweep-built mirror + live search (recommended).**
A `catalog_skills` table populated by a periodic sweep of `/api/search` over seeded
queries (registry topics, package ecosystems, big owners), storing
`{id, source, slug, installs, fetched_at}`; ranking computed locally with the
connector-style layered order; `SKILL.md` bodies and descriptions filled lazily via
`/api/download` for entries actually shown or installed. Live `/api/search` continues
to serve the search box for the long tail. Reuses every mechanism already proven by
`ConnectorCatalogSync`: `upsert_all` on a natural key, recomputed-not-incremented
ranking, tsvector search, Temporal schedule. Cost: a genuinely incomplete mirror by
construction (coverage = f(seeds)), and descriptions are absent until backfilled —
the search endpoint returns no `description` field at all (*verified:* keys are
`id, skillId, name, installs, source`), which is a real UX gap since the whole point
of a `description` in this spec is telling the agent when to use the skill.

**Option C — Vercel-hosted OIDC proxy.**
Deploy a tiny Vercel function whose OIDC token unlocks `/api/v1/skills?view=trending|hot`,
`/curated`, and `/audit`, and have Rails call that. This is the only path to the
*real* leaderboard, trending momentum, and security-audit data. Cost: a second
deployment target for a Rails+Temporal product that has none today, an availability
dependency, and an unresolved question of whether using a project's OIDC token to
serve another host's catalog is within the spirit of the auth model (the terms bless
caching, but say nothing about token brokering). Worth keeping on the shelf, not
building first.

**Rejected — HTML scraping of `/trending`, `/hot`, `/picks`.** *Verified* brittle:
`/picks` served 6 skill links, `/official` and `/agent/claude-code` served zero, the
rest is client-rendered. Also `robots.txt` disallows `/api/`, so the fallback of
"scrape the JSON the page calls" is explicitly discouraged.

**Rejected — depending on `mastra-ai/skills-api`.** MIT and it does expose
`/api/skills/top`, but there is no hosted instance, so adopting it means running
someone else's scraper as infrastructure. Strictly more moving parts than Option B
for the same data.

**Recommendation: A → B, with A shipping first.** Option A is a small change to
`SkillsController#index` plus a constant and instantly fixes the actual complaint
("the page opens on an empty search box"); Option B is the durable answer and can
land behind the same props contract without the UI noticing. Option C only becomes
attractive if Vercel starts issuing keys or the audit data becomes a requirement.

### Data Architecture

**Catalog table.** Mirror the connector shape rather than inventing one: natural
key = registry id (`owner/repo/skill`), columns for `source`, `slug`, `title`,
`description`, `installs` (upstream), `install_count` (ours), `featured`,
`bulk_publisher`, `content_hash`, `registry_synced_at`, plus a generated
`search_vector`. `bulk_publisher` is computable exactly as
`ConnectorCatalogSync#refresh_bulk_publishers` does it — a window function over
`split_part(name, '/', 1)`-style publisher grouping — no maintained list.

**Installed skills.** The existing `skills` table stays the record of what a project
has, but two fields are missing for this feature: an **origin** discriminator
(`registry` vs `manual`) and a representation for **bundled files**. Origin is the
more important of the two: nearly every behavioural difference (can it be
re-installed by the CLI? does it have a `registry_url`? can it be updated?) keys off
it, and today `source`/`package` presence is doing that job implicitly by being
`NOT NULL`.

**Bundle representation.** `/api/download` already returns `files:[{path, contents}]`
plus a `hash`. Options: JSONB column, child table, or Active Storage. The pragmatic
first cut is to keep storing only `SKILL.md` (status quo) and add `references/` and
`assets/` later — but **`content_hash` should be stored now**, because it is free
(the endpoint hands it over) and it is the only cheap way to answer "has upstream
changed since we installed this".

**Name validation is currently wrong and should be fixed in the same change.**
`Skill`'s regex allows `_` and `:`, allows any length, and does not forbid `--`,
while the spec requires `[a-z0-9-]`, 1–64 chars, no leading/trailing hyphen, no
doubled hyphen, and **equality with the directory name**. A stored name that
violates this silently fails to load in the agent — a bug that manual add would turn
from theoretical into routine.

### Manual Add Architecture

Three sub-decisions, in dependency order:

**1. Input form.** Paste-`SKILL.md` is the right primary shape: it matches what the
spec calls a skill, it is what `skills init` scaffolds, and it needs no file plumbing.
Parse frontmatter server-side, derive `name`/`description` from it (never from
separate form fields — two sources of truth for `name` is how directory-mismatch bugs
happen), and offer the CLI's other accepted forms (git URL, deep GitHub tree URL,
single-file URL, archive) as *later* additions since the CLI already resolves them.

**2. Storage.** `origin: manual`, `source: nil`, `package` synthesized
(e.g. `manual@<name>`) — or better, relax the `NOT NULL` on `source`/`package` and
let origin carry the meaning. `content` holds the pasted `SKILL.md`.

**3. Delivery — and here the telemetry finding is decisive.** `inject_skills` runs
`npx skills add …` **without** `DISABLE_TELEMETRY=1`, so today every session install
reports to skills.sh, and per their docs that report includes *the skill files*. For
registry skills that is merely inflating public counts (and quietly making our
platform a contributor to the leaderboard we would then rank by). For a
**hand-written, potentially proprietary skill it would ship the customer's content
to a third party.** Therefore:

- Manual skills must be delivered by **writing the directory into the container
  ourselves** (option 1 from step 3) — not via `skills add ./dir`.
- `DISABLE_TELEMETRY=1` should be added to the existing `skills add` invocation for
  registry installs as a separate, small correctness fix.

Confidence: high on the mechanism (quoted from the CLI docs and read from our own
code); the exact payload of "skill files" for a local-directory install is
unverified, which is itself a reason not to route private content through it.

### Deployment and Operations

The sweep is a Temporal schedule alongside `mcp_connector_catalog_sync_workflow`,
and the same durability lesson applies — the memory of schedule-triggers being wiped
on worker redeploy is why `ConnectorCatalogSync` was built to converge regardless of
cadence. A skills sweep should be equally indifferent: idempotent `upsert_all`,
`fetched_at` per row, no dependence on having run yesterday.

Rate-limit posture: the public endpoints are rate-limited **per IP** with no published
number, and the terms warn about *"scraping that bypasses the rate limit"* while
explicitly encouraging *"caching results on your own infrastructure"*. So: modest
concurrency, a delay between requests (the 20-query sweep above used 150 ms and was
untroubled), a sweep that tolerates partial failure page-by-page like
`ConnectorCatalogSync#upsert_page`, and no per-user-request fan-out. GitHub's
unauthenticated 60/hour (*verified*) stays reserved for install-time rescue only.

### Security Architecture

- **No verification tier is obtainable** (step 3): the registry id is a GitHub
  coordinate with no ownership proof. The honest badges are "official"/"picks"
  membership, org-vs-user, and install counts shown as what they are.
- **Audit data is behind OIDC** (*verified 401*), so no risk-level badge today.
  Option C would unlock it.
- **A skill is prompt content by design.** Manual add widens an existing surface
  rather than opening a new one, but it removes the "at least a third party published
  it" filter. Server-side spec validation, an angle-bracket ban in frontmatter,
  progressive-disclosure size caps, and reuse of `SkillsPolicy` + `canExecute` are
  the controls; `scripts/` stays out of scope for a first cut.
- **Telemetry egress** (above) is the newly discovered issue and is independent of
  everything else in this document — worth fixing regardless of which catalog option
  is chosen.

_Sources:_
- https://www.skills.sh/docs/cli (telemetry: contents and `DISABLE_TELEMETRY=1`)
- https://www.skills.sh/docs/faq (leaderboard powered by anonymous CLI telemetry)
- https://vibecoding.app/blog/skills-sh-review (critique: install count is the only ranking signal, gameable)
- https://botlearn.ai/en/docs/skills/skills-leaderboard-overview (all-time / trending-24h / hot views)
- Measured sweep of `https://www.skills.sh/api/search`, 20 queries, 3,702 unique skills, 2026-08-03 (table above)
- Codebase: `app/models/connector.rb`, `app/services/mcp/connector_catalog_sync.rb`, `app/services/session_context_service.rb`, `app/services/skills_registry_service.rb`, `app/models/skill.rb`

---

## Implementation Approaches and Technology Adoption

### Adoption Strategy — Follow the Connector Precedent, Phase by Phase

The connector catalog is the migration template, and its most reusable property is
that **the UI contract did not change when the data source got smarter**. The
`ConnectorCatalogModal` takes `connectors`, `query`, `catalogSyncedAt` — it does not
know whether the rows came from a curated constant or a synced mirror. Building the
skills catalog the same way means Option A (curated seed) and Option B (mirror) share
one frontend and one props contract, so the second phase is a backend swap rather
than a rewrite. That is the gradual-adoption path; a big-bang "mirror first" ordering
delays the visible fix (a page that opens on an empty search box) behind a Temporal
schedule, a migration, and a sweep tuner.

The controller-side shape to copy is exactly six lines in
`Web::Company::Projects::McpServersController`:

```ruby
CATALOG_PAGE_SIZE = 60

def catalog_connectors
  return Connector.discoverable.search(connector_query).limit(CATALOG_PAGE_SIZE) if connector_query.present?

  Connector.discoverable.where(featured: true).popular.limit(CATALOG_PAGE_SIZE)
end
```

"Query present → search; query blank → featured, ranked" is the entire behaviour the
skills page is missing. `SkillsController#index` currently returns `[]` for a blank
query, which is the whole bug.

### Development Workflow — What Gets Touched, Phase by Phase

**Phase 0 — Independent fixes (small, ship first, no design debate).**

- `SessionContextService#inject_skills`: add `DISABLE_TELEMETRY=1` to the `npx skills add`
  environment. Today every session install reports skill name **and skill files** to
  skills.sh. `SkillsRegistryService#fetch_skill_md_via_cli` already sets this variable,
  so the codebase disagrees with itself.
- `SkillsRegistryService`: the authenticated `/api/v1` branch cannot work (Bearer key
  vs Vercel OIDC, *verified 401*). Either delete it, or keep it behind a comment that
  records why it is dormant. Leaving it as-is means anyone setting `SKILLS_SH_API_KEY`
  silently breaks search — every call 401s and returns `[]`.
- `Skill` name validation vs the spec (`[a-z0-9-]`, 1–64, no `--`, no leading/trailing
  hyphen, must equal the directory name). Tighten carefully: existing rows may hold
  names with `_` or `:`, and a stricter `validates` runs on **update** too, so an
  unrelated `save` on a legacy row would start failing. Either scope the strict rule
  to new records or backfill/normalize first, and keep `name=`'s sanitizer aligned with
  whatever rule is chosen.

**Phase 1 — Featured skills, curated (Option A).**

- `Skill::FEATURED` (or a small `catalog_skills` seed table if a constant feels wrong
  for data that carries install counts) holding registry ids. The empirically derived
  seed from step 4 — **deduplicated by source**, which is what keeps fifteen
  `larksuite/cli/lark-*` entries out of the grid — is a defensible starting list:
  `anthropics/skills/frontend-design`, `mattpocock/skills/grill-with-docs`,
  `vercel-labs/agent-browser/agent-browser`, `vercel-labs/agent-skills/vercel-react-best-practices`,
  `vercel-labs/agent-skills/web-design-guidelines`, `microsoft/azure-skills/azure-deploy`,
  `supabase/agent-skills/supabase-postgres-best-practices`, `shadcn/ui/shadcn`,
  `obra/superpowers/*`, `firebase/agent-skills/*`, `github/awesome-copilot/*`, plus the
  17 `anthropics/skills` directories verified via the GitHub API (`frontend-design`,
  `mcp-builder`, `skill-creator`, `webapp-testing`, `pdf`, `docx`, `xlsx`, `pptx`,
  `canvas-design`, `algorithmic-art`, `brand-guidelines`, `theme-factory`,
  `web-artifacts-builder`, `doc-coauthoring`, `internal-comms`, `slack-gif-creator`,
  `claude-api`).
- `SkillsController#index`: serve the seed when `params[:q]` is blank. Descriptions are
  the open question — `/api/search` returns none, so either backfill via
  `/api/download` on a cache-miss basis or accept name-only cards in phase 1.
- Frontend: restructure `RegistrySearchModal` into the connector modal's shape —
  "Suggested skills" heading when the query is empty, card grid instead of a list,
  monogram/avatar fallback (skills.sh ids are GitHub coordinates, so
  `https://github.com/<owner>.png?size=80` works the same way `Connector#icon_url`
  derives icons), install count badge (public data, so it can be shown), and the
  existing debounced partial reload untouched.

**Phase 2 — Sweep-built mirror (Option B).**

- Split `SkillsRegistryService` the way MCP is split: a transport client
  (`SkillsRegistryClient` — `search`, `download`) and use-case services on top
  (`SkillsCatalogSync`, `SkillInstaller`). The current class is an adapter and a
  domain service in one file, which is also what makes it awkward to fake.
- Migration `create_catalog_skills`, modelled on `CreateConnectors`: natural key on the
  registry id, `installs`, `install_count`, `featured`, `bulk_publisher`, `content_hash`,
  `registry_synced_at`, and a **stored generated `search_vector`** with the same weight
  scheme (name/title A, description B) plus a GIN index — the connector migration is
  the copy source, comment style included.
- `SkillsCatalogSync`: seeded query sweep (registry topics, package ecosystems, large
  owners), `upsert_all` per page with `unique_by` the registry id, a recomputed ranking
  pass (`bulk_publisher` via the window function over the publisher segment,
  `install_count` from our own `skills` rows, `featured` from the constant), and
  page-level failure tolerance so one bad response does not abandon the sweep.
- Temporal wiring: an activity + workflow + one line in `app/temporal/schedules.yml`
  and `app/temporal/workflows.yml`, mirroring
  `MCPConnectorCatalogSyncWorkflow` (weekly, `start_to_close_timeout` generous for the
  first full sweep, `max_attempts: 2` because a failed sync leaves the previous mirror
  serving).
- Ranking scope on the model, layered like `Connector#popular` but with upstream
  installs leading: `installs DESC, featured DESC, bulk_publisher ASC, install_count DESC, registry_synced_at DESC`.

**Phase 3 — Manual add.**

- Migration: `origin` on `skills` (`registry` | `manual`), and relax `source`/`package`
  presence so a manual skill does not need synthetic values.
- Controller + route: a create path taking pasted `SKILL.md` text. Parse frontmatter
  server-side; derive `name` and `description` from it only.
- Validation service: the spec rules plus an angle-bracket ban in frontmatter and a
  size cap against the progressive-disclosure budget (body under ~5000 tokens / 500
  lines recommended). No Ruby validator exists to lean on — the reference
  implementation `skills-ref` is Python (`agentskills validate path/to/skill`), with a
  Rust crate and several npm/GH-Action validators, and `vercel-labs/skills` PR #509
  adds a `skills validate` CLI command. All of that is shell-out territory; a ~40-line
  Ruby validator is smaller than any of those integrations and directly unit-testable.
- Delivery: write the skill directory into the container rather than routing private
  content through `skills add` (telemetry, above). This has to satisfy the
  `adapter.includes_skills_in_context?` branch too, where skills flow through
  `ContextBuilders::Resources` as context text instead of files.
- MCP tool parity: a `create_skill`-shaped personal tool beside
  `PersonalTools::InstallSkill`, authorized through the same
  `Web::Company::Projects::SkillsPolicy`. Without it, an agent cannot author a skill
  the UI can.
- UI: a second modal ("Add manually") next to "Browse catalog", with a monospace
  textarea, live frontmatter feedback, and `skills init`-style starter content.

### Testing and Quality Assurance

`docs/testing.md` decides the shape here, and two of its rules bear directly:

- **R3/R4** — a new external service means *adapter + fake + contract test*, not
  `stub_request` scattered through feature tests. `stub_request` "belongs in adapter
  contract tests only". So: WebMock contract tests for `SkillsRegistryClient` (both
  live endpoints, both failure shapes — `404 {"error":"not_found"}` and the `400` on a
  one-character query are both *verified* real responses worth pinning), plus a
  `FakeSkillsRegistry` in `test/support/fakes/` for controller and sync tests. Note
  there is no skills fake today (`test/support/fakes/` holds bedrock, aws, github,
  gitlab, runtime, slack) while `test/services/skills_registry_service_test.rb` stubs
  HTTP directly — acceptable for an adapter contract test, but it means the phase-2
  split needs the fake introduced alongside it.
- **Never stub the class under test; no `any_instance`.** `SkillsCatalogSync` gets
  tested against the fake client, the way `connector_catalog_sync_test.rb` is written
  against `ConnectorRegistryClient`'s canned seam while the client's own contract
  tests pin its behaviour.

Coverage to add per phase: controller tests that a blank query returns the featured
set (phase 1); sync tests for idempotency, bulk-publisher recomputation, and
partial-failure tolerance (phase 2); validator unit tests for every spec rule plus
the angle-bracket ban, and an injection test that a manual skill lands in the
container without invoking `npx` (phase 3). Frontend: extend
`SkillsPage.test.tsx` and mirror `ConnectorCatalogModal.test.tsx` for the catalog and
manual-add modals — functional assertions, no visual ones.

Everything runs in Docker (`docker compose exec -T web …`), and
`make check_all` gates the push. Backend suites must not overlap — the flock note in
`CLAUDE.md` applies since a sweep test touching the same DB as another agent's run
would corrupt both.

### Deployment and Operations Practices

Phase 1 needs no deployment change. Phase 2 adds one schedule, and the operational
lesson already recorded in this repo — a worker redeploy having wiped dynamic
schedule-trigger schedules — argues for the same defensive property
`ConnectorCatalogSync` has: correctness independent of cadence, so a missed week
converges on the next run. Observability should follow the existing convention of a
`Result` struct logged as `fetched=… upserted=… failed=…`, which is what makes a
silent partial sweep visible.

Rate-limit posture in production: sweep sequentially with a short delay (the 20-query
probe used 150 ms without trouble), never fan out per user request, and treat the
public endpoints as best-effort — the terms disclaim availability entirely
(*"as is without warranty of any kind"*).

### Cost and Resource Management

Phase 1: zero marginal cost. Phase 2: a ~200-request, ~6 MB weekly sweep, plus lazy
`/api/download` calls (18–240 KB each, *measured*) only for entries actually rendered
or installed — description backfill is the one place cost could balloon if done for
the whole mirror eagerly, so it should be demand-driven with `content_hash` guarding
re-fetches. Storage is trivial: tens of thousands of rows of metadata.

### Risk Assessment and Mitigation

| Risk | Mitigation |
| --- | --- |
| Public endpoints are undocumented and can vanish (v1 is the supported surface, and it is closed to us) | Keep the mirror serving from cached rows so a dead endpoint degrades browse-freshness, not the page; the terms explicitly bless caching |
| Sweep coverage is seed-dependent, so "popular" may miss a genuinely popular skill | Keep live `/api/search` for the search box; treat the mirror as the default view only; log what a sweep dropped rather than presenting it as complete |
| Install counts are gameable telemetry, inflated for multi-skill repos (*measured*) | Bulk-publisher penalty + dedup by source + curated seed as counterweights; never present the count as a quality claim |
| Manual skills become an unreviewed prompt-injection channel | Server-side spec validation, angle-bracket ban, size caps, `SkillsPolicy`/`canExecute`, `scripts/` deferred |
| Private skill content leaking upstream via CLI telemetry | Write manual skills directly into the container; add `DISABLE_TELEMETRY=1` to registry installs (phase 0) |
| Tightening name validation breaks legacy rows on unrelated saves | Scope strict validation to new records or normalize existing names first |

## Technical Research Recommendations

### Implementation Roadmap

1. **Phase 0 (independent, small):** telemetry flag on `inject_skills`; resolve the dead
   OIDC/API-key branch; align name validation with the spec, carefully.
2. **Phase 1 (visible fix):** curated featured seed served on a blank query + connector-style
   catalog modal. This alone answers the original request.
3. **Phase 2 (durable):** client/service split, `catalog_skills` mirror with generated
   `search_vector`, seeded sweep on a weekly Temporal schedule, layered ranking with
   upstream installs leading.
4. **Phase 3 (manual add):** `origin` column, paste-`SKILL.md` flow with server-side spec
   validation, container delivery without the CLI, MCP tool parity.
5. **Optional later:** Vercel OIDC proxy for the real leaderboard, trending/hot views and
   security-audit badges; `scripts/`/`references/`/`assets/` bundles; skill editing and
   update-on-hash-change.

### Technology Stack Recommendations

Nothing new. Postgres (mirror + generated tsvector), Temporal (weekly sweep), Inertia
partial reloads (browse/search), Mantine (modal/grid), WebMock + fakes (tests). The
only genuinely new code is a small Ruby frontmatter validator, which is cheaper than
integrating any of the existing Python/Rust/JS validators.

### Skill Development Requirements

None exotic. The work is pattern-matching against `connectors`: whoever built that
catalog can rebuild it for skills with the differences already enumerated here
(no `updated_since`, upstream installs exist, no vendor verification, telemetry
caveat).

### Success Metrics and KPIs

- The skills page opens on a populated grid — currently it opens on an empty box.
- Zero `larksuite/cli`-style clusters in the default view (a direct check on the
  bulk-publisher penalty).
- Featured entries carry descriptions, not just names (the `/api/search` gap is closed).
- A skill can be created from pasted `SKILL.md` and loads in a session without any
  outbound request carrying its contents.
- Every UI skill operation has an equivalent MCP tool.
- `make check_all` green, with the new sync covered for idempotency and partial failure.

_Sources:_
- https://github.com/agentskills/agentskills/tree/main/skills-ref (Python reference validator: `agentskills validate`)
- https://github.com/moutons/skills-validator, https://docs.rs/skills-ref-rs/latest/skills_ref/, https://github.com/agent-ecosystem/skill-validator (other validator implementations)
- https://github.com/vercel-labs/skills/pull/509 (`skills validate` CLI command)
- https://www.skills.sh/docs/cli (telemetry payload and `DISABLE_TELEMETRY=1`)
- Codebase: `app/controllers/web/company/projects/mcp_servers_controller.rb`, `db/migrate/20260801000002_create_connectors.rb`, `app/temporal/{schedules,workflows}.yml`, `app/temporal/workflows/mcp_connector_catalog_sync_workflow.rb`, `docs/testing.md` (R3/R4, WebMock scope), `CLAUDE.md` (Docker, `check_all`, suite serialization)

---

# Research Synthesis: A Browsable Skills Catalog Without a Browsable Registry

## Executive Summary

The Connectors page and the Skills page look like the same problem and are not. Both
front a public registry of third-party extensions; both should open on something worth
installing. But the connector catalog could be built as a faithful local mirror because
the Official MCP Registry hands out an incremental change feed — and it *had* to be,
because that registry publishes no popularity data at all. skills.sh is the mirror
image: it knows exactly how popular every skill is (telemetry from its own CLI, hundreds
of thousands of installs on the leaders) and exposes that ranking **only** behind an
authentication method we cannot satisfy. Its `/api/v1` endpoints require a Vercel OIDC
token minted per Vercel project; the request for issuable API keys has sat open upstream
with no maintainer reply. Everything reachable without that token is a *search* endpoint
that refuses queries shorter than two characters — which is precisely why the Skills page
today opens on an empty box.

The way through is to stop treating "mirror the registry" as the goal. What the page
needs is a **default view**, and a default view can be assembled from three sources we
do control: a curated seed (the pattern `Connector::FEATURED` already established), the
public search endpoint swept over seeded queries (200 rows per ~31 KB response, install
counts included), and our own first-party install counts. Search itself stays live
upstream, because upstream search is genuinely good here — fuzzy, 200 results, with an
`owner` filter that works on the public endpoint despite being documented only for v1.
That split — mirror for browse, live for search — is the inverse of the connector design
and is the central architectural finding of this report.

Manual skill authoring turns out to be gated less by UI work than by two facts about the
runtime. The Agent Skills spec's unit is a *directory* (`SKILL.md` plus optional
`scripts/`, `references/`, `assets/`), while our `Skill` model stores a single string and
requires a registry `source` and `package` to exist. And the CLI we use to install skills
into containers reports the skill's *files* to skills.sh as telemetry unless
`DISABLE_TELEMETRY=1` is set, which our injection path does not set. A manual-add feature
built on `skills add` would therefore ship customers' private instructions to a third
party. Writing the skill directory into the container ourselves avoids that entirely and
is also the simpler implementation.

**Key Technical Findings**

1. **skills.sh's ranking data is unreachable, not absent.** `/api/v1/skills` (leaderboard,
   `view=all-time|trending|hot`), `/api/v1/skills/curated`, and
   `/api/v1/skills/audit/{source}/{skill}` all exist and all return
   `401 authentication_required` without a Vercel OIDC token (verified). No public
   substitute exists (`/api/leaderboard`, `/api/trending`, `/api/skills`, `/api/top`,
   `/api/stats` → `404`, verified).
2. **Two public endpoints carry the whole feature.** `/api/search?q=&limit=≤200&owner=`
   returns `{id, skillId, name, installs, source}` — no `description`, ordered by fuzzy
   relevance rather than installs. `/api/download/{owner}/{repo}/{skill}` returns the
   complete `files[]` bundle plus a **`hash`**, which is a better change-detection signal
   than any timestamp and has no equivalent on the MCP side.
3. **Raw install counts are unusable as a sole ranking.** Measured over 3,702 sampled
   skills: `larksuite/cli` sums to 9.9M installs across ~25 near-identical skills with
   implausibly flat per-skill figures (393k–399k), consistent with repo-level installs
   credited to every skill in the repo. Fifteen of the top 25 by installs are
   `lark-*`. The `bulk_publisher` penalty and dedup-by-source are load-bearing, not
   polish.
4. **Caching is explicitly permitted; crawling `/api/` is not.** The terms state
   *"Reasonable use, including caching results on your own infrastructure, is encouraged
   and not restricted"*, while `robots.txt` carries `Disallow: /api/`. A mirror built
   from cached API responses is inside both; an HTML-scraping crawler is outside one and
   verifiably brittle (the ranking pages are client-rendered — `/picks` served 6 links,
   `/official` served none).
5. **Three pre-existing defects, all fixable independently of this feature:** the dead
   OIDC/API-key branch (setting `SKILLS_SH_API_KEY` silently breaks search), `Skill` name
   validation that permits `_` and `:` and unbounded length where the spec requires
   `[a-z0-9-]`, ≤64, no `--`, and equality with the directory name, and the missing
   `DISABLE_TELEMETRY=1` on container installs.

**Recommendations**

1. Ship the **curated featured seed** first (Option A): serve it when `params[:q]` is
   blank and restyle the modal on `ConnectorCatalogModal`. Small, and it closes the
   original complaint.
2. Follow with the **sweep-built mirror** (Option B) behind the same props contract:
   `catalog_skills` with a generated `search_vector`, a seeded query sweep, and a weekly
   Temporal schedule whose correctness does not depend on its cadence.
3. Rank as `installs DESC, featured DESC, bulk_publisher ASC, install_count DESC,
   registry_synced_at DESC` — upstream installs lead (public data, so the number may be
   displayed), with the connector catalog's counterweights intact.
4. Build **manual add** on pasted `SKILL.md` with server-side spec validation, an
   `origin` discriminator on `skills`, container delivery that bypasses the CLI, and an
   MCP tool so agents can do what the UI does.
5. Fix the three independent defects now, especially the telemetry flag.
6. Keep the **Vercel OIDC proxy** (Option C) on the shelf; it is the only route to real
   trending/hot views and security-audit badges, and becomes attractive only if audits
   become a requirement or keys open up.

## Table of Contents

1. **Technical Research Scope Confirmation** — goal, starting position in this codebase, explicit exclusions
2. **Technology Stack Analysis** — registry APIs and what each actually returns; skill format and packaging; injection tooling; storage/ranking stack we already own; ecosystem scale
3. **Integration Patterns Analysis** — ingestion without `updated_since`; internal Inertia and MCP-tool contracts; outbound delivery options; format decisions; integration security
4. **Architectural Patterns and Design** — what `installs` measures (with measured data); Options A/B/C and rejected paths; data architecture; manual-add architecture; ops; security
5. **Implementation Approaches and Technology Adoption** — phase-by-phase file-level plan, testing per `docs/testing.md`, cost, risk table
6. **Research Synthesis** (this section) — executive summary, decision table, roadmap, open questions, methodology

## Decision Table

Decisions this research considers settled, with the evidence behind each:

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Skills stay **project-scoped**; no company scope | User decision, 2026-08-03; matches existing `Skill` validation |
| 2 | **Do not** attempt to consume `/api/v1` | OIDC-only, verified `401`; upstream key request open with no reply |
| 3 | Mirror provides **browse**; search stays **live upstream** | No public list endpoint; upstream search is fuzzy, 200 rows, `owner`-filterable |
| 4 | Ship **curated seed before mirror** | Same props contract, so the mirror is a backend swap; the visible fix should not wait on a Temporal schedule |
| 5 | Ranking leads with **upstream installs**, keeps bulk/featured/first-party counterweights | Upstream data exists (unlike MCP) and is public; measured Lark clustering proves the counterweights are required |
| 6 | Install counts **may be displayed** | Already public on skills.sh; the privacy argument that hid `Connector#install_count` (aggregated tenant usage) does not apply |
| 7 | Build the catalog from **cached API responses**, never an HTML crawler | Terms encourage caching; `robots.txt` disallows `/api/`; ranking pages are client-rendered and verifiably unparseable |
| 8 | Manual skills are delivered by **writing the directory into the container** | CLI telemetry includes skill *files*; private content must not leave |
| 9 | Add `DISABLE_TELEMETRY=1` to registry installs too | Same telemetry path; we are otherwise inflating the leaderboard we intend to rank by |
| 10 | Manual add takes **pasted `SKILL.md`**, `name`/`description` derived from frontmatter only | Spec requires `name` to equal the directory name; two sources of truth is how that breaks |
| 11 | `scripts/` bundles are **out of scope** for the first cut | Executables authored in a web form and run in an agent container is a separate risk decision |
| 12 | Store `content_hash` from `/api/download` immediately | Free from the endpoint; only cheap answer to "has upstream changed" |
| 13 | Write our **own ~40-line Ruby validator** | Reference validators are Python/Rust/JS; shelling out costs more than the rules themselves |
| 14 | Vercel OIDC proxy is **deferred, not rejected** | Only path to trending/hot and audit data; costs a new deployment target and raises an unsettled token-brokering question |

## Implementation Roadmap

- **Phase 0 — independent fixes.** Telemetry flag on `inject_skills`; resolve the dead
  authenticated branch; align name validation with the spec (scoped to new records or
  after normalization, since strict `validates` also fires on update of legacy rows).
- **Phase 1 — featured, curated.** `Skill::FEATURED`; `SkillsController#index` serves it
  on a blank query; catalog modal restyled on the connector modal, with GitHub-owner
  avatars derived from the id and install-count badges.
- **Phase 2 — mirror.** Split transport client from use-case services; `create_catalog_skills`
  with a stored generated `search_vector` + GIN index; seeded sweep with `upsert_all` and
  page-level failure tolerance; recomputed ranking pass; activity + workflow + one line
  each in `app/temporal/{schedules,workflows}.yml`.
- **Phase 3 — manual add.** `origin` column and relaxed `source`/`package` presence;
  paste-`SKILL.md` flow with server-side validation; direct container delivery covering
  the `includes_skills_in_context?` branch too; MCP tool parity.
- **Later.** Vercel OIDC proxy for trending/hot and audit badges; `references/`/`assets/`
  bundles; skill editing; update-when-hash-changes.

## Open Questions

- **Description backfill policy.** `/api/search` returns no `description`, and a skill's
  description is what tells an agent when to use it. Lazily backfill via `/api/download`
  for rendered entries, eagerly for the featured set, or accept name-only cards in
  phase 1? (Recommendation: eager for featured, lazy beyond it, `content_hash`-guarded.)
- **Sweep seed list and cadence.** Which queries, how many, and how coverage gets measured
  rather than assumed. 20 queries yielded 3,702 unique skills; the shape of the curve
  beyond that is unmeasured.
- **`installs` semantics.** Neither the docs nor the FAQ state whether a count is per skill
  or per repository. The measured Lark flatness strongly suggests repo-level crediting,
  but this remains inference.
- **Whether featured should be a constant or a table.** A constant matched the connector
  catalog, but skills carry upstream install counts, which makes a small seeded table
  defensible.
- **Whether manual skills should be shareable** beyond one project later (a template or
  company library), which interacts with the now-excluded company-scope question.

## Methodology and Source Verification

Research ran through the six-step BMAD technical-research workflow: scope confirmation,
technology stack, integration patterns, architectural patterns, implementation research,
synthesis. Two evidence classes were used and are distinguished throughout:

- **Direct verification (2026-08-03).** Live probes of skills.sh (`/api/v1/skills`,
  `/api/v1/skills/curated`, `/api/search` with and without `owner`, `/api/download` for
  three real skills and one nonexistent one, `/api/leaderboard`, `/api/trending`,
  `/api/skills`, `/api/top`, `/api/stats`, `robots.txt`, all four sitemaps, `/picks`,
  `/official`, `/topic/testing`, `/agent/claude-code`), the GitHub API
  (`anthropics/skills` contents, `rate_limit`), and a 20-query sweep of the public search
  endpoint collecting 3,702 unique skills for the ranking analysis. Every claim marked
  *verified* in this document traces to one of these.
- **Documentary sources.** skills.sh API docs, CLI docs, FAQ and terms; the Vercel
  changelog; the Agent Skills specification at `agentskills.io`; `vercel-labs/skills`
  issue #1053 and PR #509; `anthropics/skills`; `mastra-ai/skills-api`.
- **Codebase reading.** `app/models/{skill,connector}.rb`,
  `app/services/skills_registry_service.rb`, `app/services/mcp/connector_catalog_sync.rb`,
  `app/services/session_context_service.rb`, `app/services/personal_tools/*skill*.rb`,
  `app/controllers/web/company/projects/{skills,mcp_servers}_controller.rb`,
  `app/frontend/shared/resources/{skills,connectors}/*`,
  `db/migrate/20260801000002_create_connectors.rb`, `app/temporal/{schedules,workflows}.yml`,
  `docs/testing.md`, `CLAUDE.md`.

**Confidence and limitations.** High confidence on all endpoint behaviour, the spec
constraints, the telemetry payload, and the measured ranking distribution — these were
either quoted from primary documentation or observed directly. Medium confidence on the
sitemap's ordering being popularity-derived and on catalog-size figures, which disagree by
an order of magnitude across sources (600k claimed by skills.sh, 20k enumerated in its
sitemaps, 34k reported by `mastra-ai/skills-api`). Low confidence, and explicitly
inference rather than fact, on the exact mechanism inflating multi-skill-repo install
counts. Ecosystem framing drawn from secondary commentary (marketplace roundups,
"350K packages in two months", Anthropic's org-wide skill management for Team/Enterprise,
2,500+ registered Claude Code plugin marketplaces) is context, not evidence, and none of
the report's decisions rest on it.

**Not investigated.** Pricing or commercial terms of any skills marketplace; per-agent
placement differences between `claude-code`, `gemini`, and `cursor` runtimes beyond
noting that `skills_agent_name` encodes them; whether a Vercel-hosted OIDC proxy is
permitted by Vercel's own terms; and the payload the CLI sends for a local-directory
install (unverified, and a reason to avoid that path for private content).

## Conclusion and Next Steps

The request was "make Skills like MCP". The honest answer is that the *interface* should
match and the *plumbing* cannot: skills.sh gives us popularity but no browse, the MCP
registry gave us browse but no popularity, and each catalog has to be built around what
its registry actually publishes. Fortunately the connector work left behind exactly the
right reusable pieces — a props contract indifferent to its data source, a layered
ranking scheme built for a signal that arrives inflated, a mirror table pattern with
generated full-text search, and a Temporal schedule designed to converge no matter when it
last ran.

Immediate next steps, in order: fix the telemetry flag and the dead auth branch; land the
curated featured view; then decide the description-backfill policy, which is the one open
question that materially shapes phase 2.

**Technical Research Completion Date:** 2026-08-03
**Source Verification:** Live endpoint probes plus primary documentation; inference labelled as such
**Confidence Level:** High on verified endpoint behaviour, spec constraints, and measured ranking data; medium-to-low where noted

_Sources (synthesis section):_
- All sources cited in sections 2–5 above
- https://agentman.ai/blog/agent-skills-ecosystem-report-2026, https://www.agensi.io/learn/best-ai-agent-skills-marketplaces-2026, https://www.buildmvpfast.com/blog/agent-skills-npm-ai-package-manager-2026 (ecosystem framing, secondary)
