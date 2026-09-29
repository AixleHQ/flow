# BMAD Method 6.11.0 — Guide for Designing Workflow Steps

> Pinned to `BmadMethodInjector::BMAD_METHOD_VERSION`; `test/references/bmad_guide_test.rb` fails when the
> pin moves, so this guide is re-checked on every BMAD upgrade.

Verified against the `bmad-method@6.11.0` npm tarball and WDS `v0.4.3` (the highest stable tag of `bmad-code-org/bmad-method-wds-expansion`, which the installer's `stable` channel resolves). The install command is `bmad-method install --modules bmm,wds --output-folder outputs --directory /workspace --yes`. `core` is always installed.

**6.11 is a big reorganization.** Older names (`bmad-create-story`, `bmad-dev-story`, `bmad-quick-dev`, `bmad-create-prd`, `bmad-create-architecture`) are **deprecated shims**: still installed, mostly forwarding. Recommend the new names.

## 1. The delivery model

6.11 no longer has named "tracks". The README describes a loop with four stages: **Clarify → Plan → Build & verify → Learn & adjust**, where you can start at any stage. The size of the work picks the entry point:

- **Small or clear change.** Go straight to `bmad-build`, which is the quick flow. It writes its own mini-spec, implements it and reviews it.
- **Feature or product.** Run the planning chain: brief → PRD → UX → architecture → epics → sprint plan, then run `bmad-build` for each story.
- **Any intent to a contract.** `bmad-spec` distills any input (a brief, a PRD, a transcript, a brain dump) into `SPEC.md`. It is a lighter alternative to the PRD and epics chain.

Artifact flow in the help catalog (`module-help.csv`, via `preceded-by`/`followed-by`):
`bmad-product-brief` | `bmad-prfaq` → `bmad-prd` → `bmad-ux` (optional) → `bmad-architecture` → `bmad-create-epics-and-stories` → `bmad-sprint-planning` (readiness gate + tracking) → `bmad-build` (per story) → `bmad-code-review` (optional extra) → `bmad-retrospective` (end of epic). `bmad-correct-course` can run at any point when scope changes.

### Where output lands (project root `/workspace`, `output_folder=outputs`)

| Artifact | Path |
|---|---|
| Brief | `outputs/planning-artifacts/briefs/brief-<project>-<date>/brief.md` (+ `addendum.md`, `.memlog.md`) |
| PRFAQ | `outputs/planning-artifacts/prfaq-<project>.md` |
| PRD | `outputs/planning-artifacts/prds/prd-<project>-<date>/prd.md` (+ `addendum.md`, `.memlog.md`) |
| UX | `outputs/planning-artifacts/ux-designs/ux-<project>-<date>/DESIGN.md` + `EXPERIENCE.md` |
| Architecture | `outputs/planning-artifacts/architecture/architecture-<project>-<date>/ARCHITECTURE-SPINE.md` |
| Epics & stories | `outputs/planning-artifacts/epics.md` (single file, `## Epic N:` / `### Story N.M`) |
| Research | `outputs/planning-artifacts/research/<type>-<topic>-<date>/` |
| Change proposal | `outputs/planning-artifacts/sprint-change-proposal-<date>.md` |
| Sprint tracking | `outputs/implementation-artifacts/sprint-status.yaml` |
| Build spec / story file | `outputs/implementation-artifacts/spec-<slug>.md` (plus `epic-<N>-context.md` cache, `deferred-work.md`) |
| Retrospective | `outputs/implementation-artifacts/epic-<N>-retro-<date>.md` |
| QA tests | test files under `tests/` + `outputs/implementation-artifacts/tests/test-summary.md` |
| Spec | `outputs/specs/spec-<slug>/SPEC.md` (+ companions, `.memlog.md`, optional `stories.yaml`) |
| Brainstorm / forge | `outputs/brainstorming/brainstorm-<topic>-<date>/`, `outputs/forge/<slug>/` |
| Project context | a managed block in the repo-root `AGENTS.md` |
| `project_knowledge` | `docs/` (outside `outputs/`) |

Run folders are date-stamped: later steps should **glob** (e.g. `outputs/planning-artifacts/prds/*/prd.md`) or receive the reported path, never hard-code it.

## 2. Headless vs interactive — the key constraint

Many 6.11 skills have a **headless mode**. The skill treats a run as headless if any of these holds: a `headless: true` flag, a caller that is another skill or a non-TTY runner, or a first message that supplies every input and asks for an artifact path back. **When the signal is ambiguous, the skill defaults to interactive.** A headless run never asks questions. It writes the artifact, records `assumptions[]` and `open_questions[]`, and ends with a JSON status: `complete`, `partial` (review before downstream use) or `blocked` (no artifact).

**Rule for unattended steps:** put `headless: true`, the intent (`create`/`update`/`validate`) and every input path in the step instructions. If the skill has a flag, use it (`-H`).

| Skill | Unattended? | How |
|---|---|---|
| `bmad-product-brief` | Yes | headless section; create/update/validate |
| `bmad-prfaq` | Yes | `--headless`/`-H`; requires customer, problem, stakes, solution |
| `bmad-prd` | Yes | `references/headless.md`; validate always writes `validation-report.html/.md` |
| `bmad-ux` | Yes | headless; creative tools off |
| `bmad-architecture` | Yes | headless; still runs reviewer subagents + lint |
| `bmad-spec` | Yes (kernel only) | headless returns JSON; **story breakdown (`stories.yaml`) is never produced headless** |
| `bmad-sprint-planning` | Yes | headless: gate + generate; returns `gate: PASS/CONCERNS/FAIL` |
| `bmad-deep-recon` | Yes | headless defaults to *run* (web fan-out, needs internet) |
| `bmad-brainstorming` | Yes | headless = the agent generates the ideas itself |
| `bmad-retrospective` | Yes | `-H <epic>`; skips team discussion; verdict in doc frontmatter |
| `bmad-build-auto` | **Built for it** | ends with HALT status `done`/`blocked`/`ready-for-dev` |
| `bmad-review` (core) | Mostly | no questions; output goes to chat unless `report_path` is customized, so tell the agent to save it |
| `bmad-qa-generate-e2e-tests` | Mostly | may ask to confirm a framework; say which one |
| `bmad-create-epics-and-stories` | **No** | a `[C] Continue` menu at every step; no headless mode |
| `bmad-code-review` | **No** | HALTs to confirm target and summary, then for numbered choices on findings |
| `bmad-build` | **No** | HALTs for spec approval `[A]/[E]`, split `[S]/[K]`, dirty-tree checks |
| `bmad-correct-course` | **No** | asks Incremental/Batch; collaborative edits |
| `bmad-project-context` | **No** | "Conversational always; the user approves every write" |
| `bmad-checkpoint-preview`, `bmad-party-mode`, `bmad-forge-idea`, `bmad-customize`, `bmad-advanced-elicitation` | **No** | human-in-the-loop by design |
| All agent personas (`bmad-agent-*`, `wds-agent-*`) | **No** | greet, then wait on a menu |
| All `wds-*` workflows | **No** | workshop and menu driven (partial exception: `wds-4-ux-design` `[D] Dream Up`, which the agent does alone before a user review) |

## 3. Skill catalog

### Core + BMM plan
- Core: `bmad-help` (recommends next skill), `bmad-brainstorming`, `bmad-deep-recon` (research; replaces `bmad-market/domain/technical-research`), `bmad-review` (multi-lens diff/doc review; replaces `bmad-review-adversarial-general`, `-edge-case-hunter`, `-verification-gap`, `bmad-editorial-review*`), `bmad-forge-idea`, `bmad-party-mode`, `bmad-advanced-elicitation`, `bmad-customize`.
- `bmad-prd` replaces `bmad-create-prd`/`bmad-edit-prd`/`bmad-validate-prd` (removal planned for v7). `bmad-ux` replaces the removed `bmad-create-ux-design`. `bmad-architecture` writes a lean spine of `AD-n` invariants and ratifies existing code on brownfield. `bmad-sprint-planning` absorbs the removed `bmad-check-implementation-readiness` and replaces `bmad-sprint-status` (intents: readiness, sprint-planning, status, validate, fix). `bmad-project-context` replaces `bmad-document-project`/`bmad-generate-project-context`.
- `bmad-spec`: any intent → `SPEC.md` + companions; a lighter alternative to PRD + epics.

### BMM — ship
- `bmad-build`: **the official implementation skill** (Phase 4). Five steps: clarify/route → plan (writes `spec-<slug>.md`, then HALTs for approval) → implement (in a subagent) → adversarial review (parallel reviewer subagents) → present. A one-shot path handles zero-risk changes. For epic stories it compiles `epic-N-context.md` and updates `sprint-status.yaml` (`in-progress`, then `review`). Replaces `bmad-create-story` + `bmad-dev-story` + `bmad-quick-dev`.
- `bmad-build-auto`: the same pipeline **without human interaction**, "use when invoked by name". Input is a spec file path (resumes by its `status`), a spec folder + story id (`stories.yaml`), or free-text intent. Ends with a HALT status that it writes into the spec frontmatter. Add `Halt after planning.` to stop at `ready-for-dev`. `bmad-dev-auto` forwards here.
- `bmad-code-review`: ad-hoc adversarial review (Blind Hunter, Edge Case Hunter and acceptance layers). Writes findings into the story spec and `deferred-work.md`. Interactive.
- `bmad-qa-generate-e2e-tests`: generates API and E2E tests for code that already exists, then runs them. Not a review tool.
- `bmad-correct-course`: impact analysis of a scope change → `sprint-change-proposal-<date>.md`. Requires the PRD and epics.
- `bmad-retrospective`: evidence-based epic retro (spec, stories, diff, commits). Renders an acceptance verdict and marks the retro key `done` in sprint status.

### Deprecated shims (installed, avoid)
All the old names above, plus `bmad-create-architecture`, `bmad-quick-dev` and `bmad-dev-auto`, forward to the new skills. `bmad-create-story` and `bmad-dev-story` still carry their full legacy workflows (story file `outputs/implementation-artifacts/<story_key>.md`), but they are marked "only use when explicitly invoked by name".

### WDS — Whiteport Design Studio (installed; deprecated upstream, no further updates, being folded into bmm UX)
A design-first pipeline, all interactive. Output goes to `outputs/`, one lettered folder per phase: `A-Product-Brief/`, `B-Trigger-Map/`, `C-UX-Scenarios/`, `D-Design-System/`, `E-Assets/`, `E-Development/`, plus `_progress/00-design-log.md`.
- Workflows: `wds-0-project-setup`, `wds-0-alignment-signoff` (pitch/signoff), `wds-1-project-brief` (→ A), `wds-2-trigger-mapping` (→ B: trigger map, personas), `wds-3-scenarios` (→ C), `wds-4-ux-design` (page specs; modes Discuss/Suggest/Dream Up/Specs/Validate/Visual/Delivery), `wds-5-agentic-development` (build from specs), `wds-6-asset-generation` (→ E-Assets), `wds-7-design-system` (→ D), `wds-8-product-evolution` (brownfield).
- Agents: `wds-agent-saga-analyst` (brief and trigger map), `wds-agent-freya-ux` (UX, scenarios, Work Orders), `wds-agent-mimir-builder` (tech audit, PRD, build from Work Orders)
- Tools: `memory` (session state), `sync` (see Pitfalls).

### Optional modules (not installed by default; enable with `session_config.bmad_modules`)
- **bmb** (BMad Builder, stable v2.2.2): `bmad-bmb-setup`, `bmad-agent-builder`, `bmad-workflow-builder`, `bmad-module-builder`, `bmad-eval-runner`. Builds custom BMAD skills and agents.
- **cis** (Creative Intelligence Suite, stable v0.3.2): agents `bmad-cis-agent-brainstorming-coach`, `-creative-problem-solver`, `-design-thinking-coach`, `-innovation-strategist`, `-presentation-master`, `-storyteller`; workflows `bmad-cis-design-thinking`, `bmad-cis-innovation-strategy`, `bmad-cis-problem-solving`, `bmad-cis-storytelling`.
- Other upstream modules (not default): **tea** (Test Architect: `bmad-tea`, `bmad-testarch-*`; not part of bmm), **bmad-loop** (runs `bmad-build-auto` across a whole epic unattended), **gds** (game dev).

## 4. Personas (bmm roster in `module.yaml`)

| Persona skill | Name / role | Owns (menu) |
|---|---|---|
| `bmad-agent-analyst` | Mary, Business Analyst | brainstorming, deep-recon (market/domain/technical/competitive/user-voice/select), product-brief, prfaq, project-context |
| `bmad-agent-pm` | John, Product Manager | prd, create-epics-and-stories, sprint-planning (readiness), correct-course |
| `bmad-agent-ux-designer` | Sally, UX Designer | ux |
| `bmad-agent-architect` | Winston, System Architect | architecture, sprint-planning (readiness) |
| `bmad-agent-dev` | Amelia, Senior Engineer | build, qa-generate-e2e-tests, code-review, sprint-planning, retrospective |

**Removed in 6.x:** the SM (`bmad-agent-sm`), QA (`bmad-agent-qa`), Quick-Flow Solo Dev and Tech Writer (`bmad-agent-tech-writer`) personas. SM and QA duties now sit with the dev persona's menu, and test architecture lives in the optional tea module. For platform agent personas, reuse these role descriptions but have each step call the **workflow skill directly**. Persona skills are interactive menus and do not suit unattended steps.

## 5. Mapping to workflow automation

Suggested step patterns (each step has `bmad_enabled: true`; artifacts pass between steps as files under `/workspace/outputs/`):

1. **Discovery / research**: `bmad-deep-recon` headless, type named → a research summary.
2. **Brief**: `bmad-product-brief` headless create from the task description → `brief.md`.
3. **Requirements**: `bmad-prd` headless create with the brief path → `prd.md`. Add a follow-up step running `bmad-prd` headless validate as a quality gate.
4. **UX** (UI projects): `bmad-ux` headless with the PRD path.
5. **Tech design**: `bmad-architecture` headless with the PRD (+ UX) path → `ARCHITECTURE-SPINE.md`.
6. **Backlog**: `bmad-create-epics-and-stories` is interactive, so make this an attended step or put an approval gate around it. The unattended alternative is `bmad-spec` headless, which produces a `SPEC.md` contract; a story breakdown still needs an interactive run.
7. **Readiness + sprint**: `bmad-sprint-planning` headless → `sprint-status.yaml`. Branch on `gate`: FAIL → route back to planning.
8. **Implementation**: unattended → `bmad-build-auto` with a spec path or a story reference; attended → `bmad-build`. Run one story per step run.
9. **Review**: unattended → `bmad-review` on the branch diff, telling the agent to write the report to `outputs/implementation-artifacts/`. Attended → `bmad-code-review` or `bmad-checkpoint-preview`.
10. **Tests**: `bmad-qa-generate-e2e-tests`, naming the framework.
11. **Epic close**: `bmad-retrospective -H <epic>`, then read `verdict` from the retro document's frontmatter.

Treat headless `partial`/`blocked` or a build-auto `blocked` spec status as needs-review/failed, not success.

## 6. Pitfalls (verified in source)

- **Interactive skills stall unattended runs.** They HALT and wait (menus, `[C] Continue`, approvals). Headless-capable skills still fall back to interactive when the signal is ambiguous.
- **`bmad-build` is not autonomous.** It waits for spec approval. Use `bmad-build-auto` for unattended implementation.
- **`bmad-build-auto` requires** a clean git working tree, a branch whose name fits the intent, and working subagents. Otherwise it HALTs `blocked`: "no subagents", dirty tree, "unclear intent". It commits the reviewed changes itself and **does not update `sprint-status.yaml`**; only interactive `bmad-build` syncs sprint status.
- **Most skills shell out to `uv run _bmad/scripts/*.py`** (Python ≥3.11 for `render_skill.py`; `uv` is in our base image). If `render_skill.py` fails, `bmad-build`/`bmad-build-auto` HALT; other skills fall back to reading `customize.toml` directly.
- `bmad-sprint-planning` parses `epics.md` headings (`## Epic N:` / `### Story N.M`), so hand-written epics must match that format.
- `bmad-correct-course` HALTs if the PRD or epics are missing. `bmad-retrospective` forces verdict **rejected** when stories are unfinished, and still marks the retro `done` in sprint status.
- `bmad-deep-recon` in run mode and the reviewers in architecture/PRD mode spawn web-research subagents, so they need outbound network access.
- WDS personas trigger `sync`, which asks the user on first activation and writes to `~/.claude/commands/`. The WDS `design_artifacts` setting defaults to `design-artifacts/`, but the workflows observed write to `outputs/<Letter>-*/`.

## Appendix — source paths (tarball `package/`)

`bmad-modules.yaml` (external module registry) · `removals.txt` · `src/{core,bmm}-skills/module.yaml` + `module-help.csv` · `src/bmm-skills/{plan,ship,agents,v6-shims}/<skill>/SKILL.md`, `customize.toml` (output paths), `references/headless.md` · `src/bmm-skills/ship/bmad-build{,-auto}/workflow.md`, `step-0*.md` · `src/scripts/render_skill.py` · `tools/installer/core/manifest-generator.js` (recursive `SKILL.md` discovery, so shims get installed) · WDS: `src/module.yaml`, `src/workflows/wds-*/`, `src/agents/`, `src/tools/`.
