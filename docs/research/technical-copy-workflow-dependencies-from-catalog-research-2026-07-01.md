---
research_type: technical
research_topic: "Copy workflow dependencies (agents, skills, mcp, tools) when adding from catalog"
date: 2026-07-01
web_research_enabled: true
source_verification: true
stepsCompleted: [1, 2, 3, 4, 5, 6]
---

# Copy or Reference? How Template-to-Instance Platforms Clone Dependency Graphs Without Leaking Secrets: Technical Research — Copy workflow dependencies (agents, skills, mcp, tools) when adding from catalog

## Executive Summary

We are building catalog-to-project workflow instantiation: when a team adds a shared
company workflow from the catalog, the workflow's dependency graph (agents, skills,
MCP servers, custom tools) should be **deep-copied into project-local, independently
editable copies**, while secrets/credentials are **never** copied so the project team
supplies its own. This research validates that approach against real-world precedents
and resolves the five open product decisions in our internal design doc
(`ai/research/technical-copy-workflow-dependencies-from-catalog-2026-07-01.md`).

**Key findings**

1. **The "copy the graph, but never copy secrets, and remap IDs" pattern is the
   industry norm**, not a novel design. Make.com's scenario `clone` API copies the
   scenario and takes explicit `account`/`hook`/`datastore` *mapping pairs* of
   `original→clone` IDs — exactly our `source_id → project_local_id` remap maps —
   and lets you map an entity to `null` to *omit* its settings (credentials) rather
   than transfer them ([Make API](https://developers.make.com/api-documentation/api-reference/scenarios)).
   A GitHub repository created from a template "starts with a single commit" and its
   branches "have unrelated histories, which means you cannot create pull requests or
   merge between the branches" — i.e. the new repo is a clean, disconnected instance,
   which is the whole point ([GitHub Docs](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)).
2. **Every credential-bearing platform excludes secrets from the template and
   re-provisions them in the instance.** Zapier templates "do not include your app
   connections or any values you've entered" ([Zapier](https://zapier.com/help/manage/collaborate/share-a-copy-of-your-zap));
   Make blueprints "do not store your real connection details like API keys"
   ([Make](https://help.make.com/blueprints)); n8n exports "include credential names and
   IDs" but, per troubleshooting guidance, leave out the sensitive auth data
   ([n8n Docs](https://docs.n8n.io/build/manage-workflows/export-and-import),
   [Latenode](https://latenode.com/blog/low-code-no-code-platforms/n8n-setup-workflows-self-hosting-templates/n8n-export-import-workflows-complete-json-guide-troubleshooting-common-failures-2025));
   Airflow DAGs reference a `conn_id` by name and never hardcode the secret
   ([Airflow Docs](https://airflow.apache.org/docs/apache-airflow/stable/howto/connection.html)).
   This is precisely our `ConfigItem`-is-the-boundary rule.
3. **The copy-vs-reference choice is a known tradeoff with a clear default for our
   case.** dbt frames it exactly: installing a *package* pulls in full source code you
   own and can edit but must maintain, whereas a *project dependency* resolves
   references on-the-fly to an upstream interface you cannot edit
   ([dbt Docs](https://docs.getdbt.com/docs/mesh/govern/project-dependencies)).
   Since the whole point of ticket #302 is **per-project editability**, the
   package/copy model is correct for project-scoped resources; reference (pass-through)
   is correct only for platform/shared-by-design resources.
4. **Deep-copying an object graph is a solved algorithm — an identity map
   (`original→clone` hash) that doubles as a visited-set handles dedup, shared
   nodes, and cycles in linear time** ([AlgoMaster](https://algomaster.io/learn/dsa/clone-graph)).
   Our per-type memoized maps are this pattern. The hard part is not the traversal;
   it is (a) the secret boundary and (b) the Rails-specific pitfalls below.
5. **The dominant failure mode to design against is the *broken reference on import*** —
   credential errors are "one of the most frequent causes of workflow import failures
   in n8n," because the exported JSON carries only credential names/IDs and the target
   instance has no matching credential to bind them to
   ([Latenode](https://latenode.com/blog/low-code-no-code-platforms/n8n-setup-workflows-self-hosting-templates/n8n-export-import-workflows-complete-json-guide-troubleshooting-common-failures-2025)).
   A representative report: imported workflows whose credentials appear in the global
   Credentials section but are unusable inside the workflow, surfacing errors such as
   "unrecognized credential type: oauth2api"
   ([n8n issue #20049, "Imported Workflows Break Credentials Across CMD and Render Instances"](https://github.com/n8n-io/n8n/issues/20049)).
   This directly justifies (a) our defensive "leave unknown IDs as-is, never abort"
   mapper and (b) surfacing a "needs setup" banner instead of silent breakage
   (UiPath Studio's pattern: mark invalid activities and show an error banner —
   [UiPath Docs](https://docs.uipath.com/studio/docs/managing-dependencies)).

**Top recommendations**

1. **Keep the deep-copy + per-type ID-remap design** in `WorkflowDuplicator`. It mirrors
   Make's clone-with-mapping-pairs and the textbook clone-graph identity map. (High)
2. **Hold the secrets boundary at `ConfigItem`** (never copy those rows); copy MCP
   `env`/`headers` verbatim because `config_item:NAME` references carry no secret
   material. This matches Zapier/Make/n8n/Airflow precedent and the OWASP MCP Top 10
   ("never embed secrets in configuration files / prompt templates") — [OWASP MCP01:2025](https://owasp.org/www-project-mcp-top-10/2025/MCP01-2025-Token-Mismanagement-and-Secret-Exposure). (High)
3. **Idempotent reuse by natural key (`name` per scope)** is the correct dedup strategy
   — a unique constraint on the natural key plus find-or-create-in-the-same-transaction
   is the recommended idempotency mechanism, with the dedup record co-located in the
   business transaction ([Brandur — Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys)). (High)
4. **Prefer the Rails clone gems' patterns conceptually but hand-roll the copy** —
   `amoeba` explicitly leaves **polymorphic `has_many` and nested `parent_id`
   undefined** and makes no mention of JSONB ([amoeba README](https://github.com/amoeba-rb/amoeba)),
   while `rails_deep_copy` and `deep_cloneable` reassign FKs only over **real
   ActiveRecord associations** ([rails_deep_copy](https://github.com/LaunchPadLab/rails_deep_copy)),
   not our JSONB-arrays-of-foreign-IDs. Our entire model is polymorphic-scope +
   JSONB-ID-arrays, so a manual copier with explicit remap maps is safer than a gem. (High)
5. **Surface a "needs setup" banner** for the three unresolvable-after-copy cases
   (dropped managed MCP, integration-gated tool, missing `ConfigItem`) rather than
   failing silently like n8n. (Medium)

## Table of Contents

1. Problem Framing & Research Methodology
2. Industry Precedents
3. Patterns & Pitfalls
4. Concrete Libraries & Approaches
5. Recommendations for palad-app
6. Open Decisions Informed by Research
7. Sources & Confidence

---

## 1. Problem Framing & Research Methodology

### What we are building

In palad-app, a shared **company catalog** publishes workflows. When a team "adds"
one into a project, today only the `Workflow` row and its `Step`/`SubStep` children
are copied; the **dependencies** the workflow needs to run — `Agent` (FK on the
step), and the JSONB ID arrays `tool_ids` / `skill_ids` / `mcp_server_ids` plus the
workflow-level `base_*_ids` — are **left pointing at the source company's shared
rows**. That produces two problems the internal design doc documents:

- **No per-project customization** — a team cannot tweak an agent persona, a skill,
  or an MCP server without mutating the shared company resource that every other
  project also references.
- **Silent breakage** — editing or deleting the shared resource changes/breaks every
  copied workflow out from under teams.

The proposed fix is to **deep-copy the dependency graph into project-local, editable
copies and remap the IDs**, in one transaction, inside `WorkflowDuplicator`, while
**never copying `ConfigItem` secret rows** (the project team provides its own).

Our stack constrains the implementation: **Ruby on Rails + Pundit + React/Inertia/
Mantine + Postgres**. The dependency references are a mix of a real FK (`agent_id`)
and **JSONB arrays of bare foreign IDs** (not FKs), and every dependency model is
**polymorphically scoped** (`scope_type ∈ {Company, Project, System}`). Those two facts
(JSONB-IDs + polymorphic scope) are exactly the two things the popular Rails clone
gems say they do *not* handle — see §3/§4.

### Why research it

The design is sound on paper, but the five open product decisions (custom tools in
scope? backfill? opt-in checkbox? missing-dependency UX? copy vs reference?) are
judgment calls that benefit from knowing how comparable platforms actually solved the
same template-to-instance dependency-copy problem — particularly around the two things
that go wrong in production: **leaked/duplicated secrets** and **dangling references**.

### How it was researched

Web-search-first (mandatory), reading primary docs where possible. Coverage:

- **No-code/workflow platforms** that instantiate templates with dependencies:
  n8n, Zapier, Make.com.
- **Scaffolding/IaC/data platforms**: GitHub template repositories, Backstage
  software templates, Terraform modules (registry vs git), dbt packages vs project
  dependencies, Apache Airflow connections.
- **AI agent frameworks**: LangChain / CrewAI templates and tool adapters.
- **Foundational patterns**: clone-graph algorithm (identity map / cycle handling),
  idempotency & natural-key dedup, secrets-management cheat sheets (OWASP, vault
  patterns), MCP secret handling (OWASP MCP Top 10).
- **Rails specifics**: `amoeba`, `deep_cloneable`, manual association duplication,
  JSONB behavior.
- **Broken-reference UX**: UiPath Studio, Power Platform/Power Automate, error-message
  UX patterns.

Confidence is flagged inline (High/Medium/Low). Where sources conflict it is noted in §7.
The full query list is in §7.

---

## 2. Industry Precedents

This section names real products and how they actually solve template-to-instance
dependency copying, organized by the three sub-questions: **copy / reference / hybrid**,
**how they remap**, and **how they exclude secrets**.

### 2.1 Make.com — copy the scenario, remap entities by explicit `original→clone` ID pairs, omit credentials

Make is the closest precedent to our design. Two layers:

- **Blueprints (export/import)** deliberately strip secrets. Make's help page states that
  although "blueprints include modules, settings, and mapped values, users still need to
  create connections" after importing
  ([Make blueprints](https://help.make.com/blueprints)); the more pointed phrasing —
  "Blueprints do not store your real connection details like API keys or login tokens…
  After you import a blueprint, you need to reconnect your apps" — is the widely-cited
  Make guidance, corroborated by community write-ups
  ([backup-scenarios walkthrough](https://medium.com/@tremblayjustin89/how-i-backup-my-make-com-scenarios-3d749b302213)).
  Either way: a blueprint = workflow structure minus credentials, and the user
  re-provisions on import — identical to our "copy the workflow, not the `ConfigItem`
  secrets" rule.
- **Scenario `clone` API** is the explicit remap mechanism. `POST /scenarios/{id}/clone`
  accepts mapping objects in the body that "specify pairs of original and clone
  connection IDs to map connections to the cloned scenario" (`account`), plus the same
  for webhooks (`hook`), data stores (`datastore`), data structures (`udt`), keys, and
  devices ([Make API](https://developers.make.com/api-documentation/api-reference/scenarios)).
  Critically, when cloning to a different team you "map entities to alternative ones
  with matching properties, or use `notAnalyze`… mapping entity IDs to `null`, which
  omits the entity settings" rather than transferring credentials (same source).

**Why this matters for us (High confidence):** Make's `account`/`hook`/`datastore`
mapping pairs are *exactly* our `agent_map` / `mcp_server_map` / `tool_map`
`source_id → project_local_id` dictionaries. And Make's `null`-mapping-to-omit is the
precedent for our "drop a managed-MCP reference that isn't visible in the target"
behavior (D4). Make validates the clone ("blueprint analysis makes sure the clone
will work without further changes") unless explicitly suppressed — an argument for a
post-copy validation/banner pass (§3.5).

### 2.2 GitHub template repositories — copy = a clean, disconnected instance

GitHub draws the sharpest line between **copy** and **reference (fork)**. Per GitHub's
docs, "a new fork includes the entire commit history of the parent repository, while a
repository created from a template starts with a single commit," and "branches created
from a template have unrelated histories, which means you cannot create pull requests or
merge between the branches"
([GitHub Docs](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)).
Synthesizing those two facts: a template instance is a clean, disconnected copy with no
live coupling to the source — community write-ups describe it the same way, as having "no
shared history" and "no connection to the original"
([DEV.to](https://dev.to/gitprotect/how-to-use-github-repository-templates-3dfk)).

**For us (High):** This is the canonical statement of *why* we copy rather than
reference for the editable resources — disconnection from the source is the feature.
A copied project workflow should be an independent instance with no live coupling to
the catalog original, exactly like a template-repo instance.

### 2.3 Zapier — template excludes connections; sharing connections is a separate, explicit act

Zapier cleanly separates the two models we are choosing between:

- A **Zap template** "include[s] a basic outline of each step… apps and events
  pre-populated, but it does not include your app connections or any values you've
  entered in step fields. Other users will need to connect their own accounts"
  ([Zapier: share a template](https://zapier.com/help/manage/collaborate/share-a-copy-of-your-zap)).
- **Shared App Connections** is a *deliberate, separate* feature that lets team members
  reuse one connection "without needing your login credentials" — and explicitly warns
  that recipients "will be able to view data used to test a Zap"
  ([Zapier: share app connections](https://help.zapier.com/hc/en-us/articles/8496326497037-Share-app-connections-with-members-of-your-Team-or-Enterprise-account)).

**For us (High):** Zapier validates **never copy secrets into the instance** (templates
exclude connections), and shows that *sharing* credentials is a conscious, opt-in,
audited action — not something a copy should do implicitly. Our `ConfigItem` rows stay
shared at the company level and are referenced by name, which is closer to Zapier's
"shared connection" than to copying.

### 2.4 n8n — references credentials by name/ID; the cautionary tale of dangling references

n8n's own docs state that "exported workflow JSON files include credential names and
IDs" ([n8n Docs](https://docs.n8n.io/build/manage-workflows/export-and-import)).
Troubleshooting guidance is explicit that the sensitive material is left out: "when
exporting a workflow, the generated JSON file only includes credential names and IDs,
leaving out sensitive information like API keys or passwords," so on import you must
"recreate the necessary credentials in the target n8n instance, ensuring they have the
exact same names as those referenced in the JSON file" — or "manually map existing
credentials to the affected nodes"
([Latenode troubleshooting](https://latenode.com/blog/low-code-no-code-platforms/n8n-setup-workflows-self-hosting-templates/n8n-export-import-workflows-complete-json-guide-troubleshooting-common-failures-2025)).

The instructive part is the **failure mode**: per Latenode, "credential-related errors are
one of the most frequent causes of workflow import failures in n8n." Because the export
carries only credential names/IDs and there is no automatic binding, an imported workflow
can carry credential references the target instance cannot resolve. A representative
GitHub report is issue #20049, "Imported Workflows Break Credentials Across CMD and Render
Instances," where credentials appear in the global Credentials section yet remain unusable
inside nodes, producing errors such as "unrecognized credential type: oauth2api"
([Latenode troubleshooting](https://latenode.com/blog/low-code-no-code-platforms/n8n-setup-workflows-self-hosting-templates/n8n-export-import-workflows-complete-json-guide-troubleshooting-common-failures-2025),
[n8n GitHub #20049](https://github.com/n8n-io/n8n/issues/20049)).

**For us (High):** This is the exact anti-pattern our design avoids. By **remapping IDs
to project-local copies** instead of carrying source IDs, we eliminate n8n's dangling-ID
class entirely for copied resources. And the residual cases that *can* dangle (a managed
MCP not visible in the target, an integration-gated tool, a missing `ConfigItem`) are
precisely where n8n's silent failure argues for our **"needs setup" banner** (§3.5, D-UX).

### 2.5 dbt — the canonical copy-vs-reference framing

dbt is the best articulation of the copy-vs-reference tradeoff and maps directly onto
our "editable project copy vs shared company reference" decision:

- **Packages (copy):** "you're pulling down its full source code and adding it to your
  runtime… dbt needs to parse and resolve more inputs (slower), expects you to
  configure these models as if they were your own"
  ([dbt: packages](https://docs.getdbt.com/docs/build/packages),
  [dbt: project dependencies](https://docs.getdbt.com/docs/mesh/govern/project-dependencies)).
- **Project dependencies (reference):** "a metadata service… resolves references
  on-the-fly to public models… will not be pulled down as source code," using "an
  intentional interface designated by the model's maintainer with access set to
  public" (same source).

dbt's verdict: copying (packages) is great for a *starting point you will customize*,
but bad for *living shared code at scale*; reference is for stable, maintainer-owned
interfaces.

**For us (High):** The catalog workflow is exactly a "starting point you will customize,"
so the **copy/package** model is right for project-editable resources (agents, skills,
custom tools, custom MCPs). The **reference** model is right only for platform/shared
resources whose interface is stable and maintainer-owned (System agents, internal MCP
servers, platform tools, and same-company shared `ConfigItem`s) — which is precisely our
hybrid pass-through rule.

### 2.6 Terraform modules — reference-by-version is the default for *shared* code

Terraform is the counterweight: for code shared across **3+ teams**, the recommended
pattern is **reference a registry module with a version constraint** (`version = "~> 1.2.0"`),
not copy, because the registry "enables centralized management," SemVer constraints,
discoverability, and access control ([Terraform module docs](https://developer.hashicorp.com/terraform/language/block/module),
[InstaDevOps](https://instadevops.com/blog/terraform-modules-best-practices/)).

**For us (Medium):** This supports keeping *company-level shared* resources as
references when the goal is central governance — i.e., it backs our decision to
**pass through (reference) System/internal/platform resources** rather than fork them.
It does *not* contradict copying the project-editable resources, because Terraform's
reference model assumes you do **not** want to edit the shared module locally — which is
the opposite of #302's requirement.

### 2.7 Backstage software templates & Airflow — scaffold-then-own; reference secrets by name

- **Backstage scaffolder** defines a template as "a small `yaml` definition which
  describes the template and its metadata, along with some input variables that your
  template will need, and then a list of actions which are then executed by the
  scaffolding service" — actions like `fetch:template` and `fetch:plain` that render and
  fetch content into a new component the team then owns
  ([Backstage: writing templates](https://backstage.io/docs/features/software-templates/writing-templates/)).
  This is a copy-and-own model with parameter (input-variable) substitution — analogous to
  our copy + team-supplies-its-own-`ConfigItem` flow.
- **Airflow** is a clean **reference-by-name** secrets precedent: a DAG references a
  `conn_id` (e.g. `slack_webhook_conn_id`) and the actual credential lives in a
  connection store / secrets backend (Vault, AWS SSM), never in DAG code
  ([Airflow: connections](https://airflow.apache.org/docs/apache-airflow/stable/howto/connection.html)).
  Identical in shape to our `config_item:NAME` reference inside MCP `env`/`headers`.

### 2.8 LangChain / CrewAI — config-as-template variables; tools need adapters across ecosystems

AI agent frameworks template the *persona/config*, not secrets: CrewAI custom templates
use variables like `{role}`, `{goal}`, `{backstory}` populated at execution
([CrewAI: agents](https://docs.crewai.com/en/concepts/agents)). A relevant caution for
our `Tool` copy: handing a raw LangChain tool to a CrewAI agent "without preparation"
causes "vague Pydantic validation errors, schema mismatches" — tools have **specific
input schemas** that must be carried correctly across a boundary
([daily.dev](https://daily.dev/blog/ai-agents-guide-for-developers-langchain-crewai/),
[DEV.to](https://dev.to/petter-strale/give-your-langchain-or-crewai-agent-250-data-capabilities-in-3-lines-of-code-552n)).

**For us (Medium):** When we copy a custom `Tool`, we must copy its `input_schema`
faithfully (the design already does). The agent-framework lesson is that a tool's schema
is load-bearing and a lossy copy breaks invocation — reinforcing the §3 pitfall about
copying *all* fields a dependency needs to actually run (including binary `tool_files`).

### 2.9 Precedent summary table

| Platform | Copy / Reference / Hybrid | How references are remapped | Secret handling on copy |
| --- | --- | --- | --- |
| **Make.com** | Hybrid: copy scenario, map entities | Explicit `original→clone` ID pairs per entity type; `null` to omit | Blueprints strip API keys; reconnect after import |
| **GitHub templates** | Copy (disconnected) | New IDs, no link to source | N/A (no secrets in repo template) |
| **Zapier** | Copy structure; share-connections is separate opt-in | Each user reconnects own accounts | Template excludes connections & field values |
| **n8n** | Reference credentials by name/ID | *No auto-mapping* → dangling-ID failures | Export = names+IDs only, never auth data |
| **dbt** | Both, explicitly: package=copy, dependency=reference | Package: own the code; dependency: metadata service resolves | N/A (env vars / profiles stay out of project) |
| **Terraform** | Reference (registry + version) for shared | Logical name + version constraint | Vault/Key Vault reference, never in template |
| **Backstage** | Copy-and-own (scaffold) | Parameter substitution into new component | Team provides inputs/secrets at scaffold time |
| **Airflow** | Reference secrets by `conn_id` | conn_id name resolved at runtime | Connections/Variables/Vault, never in DAG |

---

## 3. Patterns & Pitfalls

### 3.1 Recommended pattern: identity-map deep copy (handles dedup, shared nodes, cycles)

Deep-copying a dependency graph is the classic **clone-graph** problem. The canonical
solution is a **hash map from original node → cloned node that does double duty as a
visited-set and a lookup table**, so "shared nodes point to the same clone and cycles
are preserved," in **linear time** over nodes+edges
([AlgoMaster](https://algomaster.io/learn/dsa/clone-graph),
[algo.monster](https://algo.monster/liteproblems/133)).

Our per-type memoized maps (`agent_map`, `skill_map`, `mcp_server_map`, `tool_map`) are
exactly this identity map. Consequences we get for free:

- **De-duplication of shared dependencies**: two steps referencing the same agent map
  to one project-local agent (the map returns the existing clone). (High)
- **Cycle safety**: our graph is shallow (workflow→steps→IDs) with no resource→resource
  cycles, but the identity map would handle them anyway. (High)
- **ID remapping correctness**: write the *mapped* ID everywhere the source ID appeared
  (both step columns and `workflow.config.base_*_ids`). Missing one location is the #1
  remap bug (n8n's dangling-ID failure, §2.4). (High)

### 3.2 Recommended pattern: idempotency via natural key + unique constraint + transaction

Best practice for making a copy operation safely repeatable is **upsert on a natural
key under a unique constraint, inside the same transaction as the business mutation**.
Brandur Leach's canonical Postgres write-up implements exactly this: the idempotency key
is `UNIQUE` in the database, the API action is "wrapped entirely in transactions" (the
atomic phase is committed before any foreign-state mutation), and a concurrent duplicate
returns a `409 Conflict` — so conflict detection lives at the database level and the
dedup record is co-located with the business data in the same transaction
([Brandur — Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys)).
Brandur also **scopes the key by tenant** — his unique constraint is across
`(user_id, idempotency_key)` "so that it's possible to have the same idempotency key for
different requests as long as it's across different user accounts"; general guidance to
combine the key with a user/endpoint scope is echoed elsewhere
([DesignGurus](https://www.designgurus.io/blog/idempotency-in-distributed-systems)).
For us, the natural key is `(scope_type, scope_id, name)`, which is exactly the per-scope
unique index our models already carry.

**For us (High):** `find_by(name:)`-in-the-target-then-reuse, backed by the per-scope
unique index, is the textbook idempotent-by-natural-key pattern. Re-running the copy
(or copying two workflows that share an agent) converges instead of erroring. The whole
copy must stay in **one ActiveRecord transaction** so a partial copy never persists —
matching Brandur's pattern of committing the dedup decision atomically with the business
mutation (§3.2 citation above).

**Pitfall (Medium):** natural-key reuse means "a project already has a *different*
resource with the same name" → the copy points at that existing resource. This is
acceptable (names are user-meaningful) but should be a documented behavior, not a
surprise. Suffixing (like `available_name`) is the alternative if collisions are common.

### 3.3 Recommended pattern: secrets boundary = a single, named exclusion (never copy the secret store)

Every credential-bearing platform we surveyed converges on one rule: **the template/copy
never carries the secret; the instance re-provisions it.** Concrete precedents: Zapier
templates exclude connections; Make blueprints strip API keys; n8n exports omit auth
data; Airflow references `conn_id`; Terraform/ARM reference a Key Vault by ID, "never
expos[ing] the value… you only reference its key vault ID"
([Microsoft: Key Vault parameter](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/key-vault-parameter)).
OWASP's Secrets Management Cheat Sheet and the **OWASP MCP Top 10 (MCP01:2025: Token
Mismanagement and Secret Exposure)** both name "embedding [secrets] in configuration
files, environment variables, prompt templates" as the #1 mistake
([OWASP MCP01:2025](https://owasp.org/www-project-mcp-top-10/2025/MCP01-2025-Token-Mismanagement-and-Secret-Exposure),
[OWASP Secrets Mgmt](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)).

**For us (High):** Our design's single boundary — **never copy `ConfigItem` rows** — is
exactly this pattern. Because the real secrets live in `ConfigItem` (encrypted, scoped)
and are referenced by `config_item:NAME` inside MCP `env`/`headers`, copying `env`/
`headers` verbatim copies only *references*, not secret material — analogous to copying
an Airflow DAG's `conn_id` string. This is correct and matches precedent.

**Pitfall — the "scrub heuristic" anti-pattern (High):** an earlier internal draft
considered scrubbing "any `env`/`headers` value that isn't a `config_item:` reference"
as a literal secret. The research **strongly argues against** value-based secret
heuristics: there is no reliable discriminator between a literal secret and a literal
non-secret (a public base URL, a model name). The correct boundary is **structural**
(a designated secret store / named reference), not a guess at the value — which is the
whole reason Airflow/Make/Zapier use *named* connection stores. Verbatim copy + the
`ConfigItem` boundary is the right call; the scrub heuristic would silently destroy
legitimate config (data loss) and still miss cleverly-formatted secrets.

**Pitfall — pre-existing misuse (Medium):** if a user pasted a raw secret directly into
`env`/`headers` instead of using `config_item:`, verbatim copy duplicates it. This is
unavoidable without a discriminator that doesn't exist; the mitigation is the same as
every platform's — steer users to *named references* (`config_item:`) and treat the raw
paste as out-of-scope misuse. (This matches OWASP's "use a central secrets manager
rather than shared .env files.")

### 3.4 Anti-pattern: dangling references / silent breakage

The single biggest production hazard in this space is the **dangling reference**: a copy
that carries a source ID/name that doesn't resolve in the target, then **breaks on import
or at run time** (n8n's credential references that don't bind in the target instance,
§2.4). Power Platform/Power Automate show the same class — solution imports fail on
"missing dependencies… Install the following solutions before installing this one" and
missing connection references
([D365 Demystified](https://d365demystified.com/2020/10/14/there-are-missing-dependencies-install-the-following-solutions-before-installing-this-one-active-connection-references-missing-in-power-platform-solution/),
[DEV: Power Automate fix missing deps](https://dev.to/wyattdave/power-automate-how-to-fix-missing-dependencies-m5i)).

**Mitigations our design already uses (High):**
- Remap to project-local IDs so the common case never dangles.
- **Defensive mapper**: an unknown/unreadable source ID is **left as-is, never raising**,
  so a stray ID can't abort the whole copy (`deep_cloneable` offers a
  `skip_missing_associations` escape for exactly this reason — §4.3).
- Surface the residual unresolvable cases (next section) instead of silent failure.

### 3.5 Recommended UX pattern: "needs setup" banner over silent drop

UiPath Studio is the cleanest precedent: "missing or invalid activities are marked in the
Designer panel, while an error banner provides additional information regarding the
workflow and its unresolved dependency conflicts"
([UiPath: managing dependencies](https://docs.uipath.com/studio/docs/managing-dependencies)).
Error-UX guidance: "don't wait for users to finish all steps… notify them of issues from
earlier steps," and escalate destructive/blocking issues from inline → banner → modal
([Pencil & Paper: error feedback](https://www.pencilandpaper.io/articles/ux-pattern-analysis-error-feedback)).
Make *validates the clone* by default (blueprint analysis) so the user learns of
problems at clone time, not at run time (§2.1).

**For us (Medium):** A "needs setup" banner in the builder listing exactly what to
connect/add (a dropped managed MCP, an integration-gated tool, a missing `ConfigItem`)
is the validated pattern, and it neutralizes the n8n silent-failure class. The silent
alternative is cheaper but ships the exact UX bug other platforms regret.

### 3.6 Edge-case & security traps checklist

- **Remap in *all* locations** (step columns + `config.base_*_ids`). Missing one →
  dangling reference. (High)
- **Copy *everything a dependency needs to run*, not just text.** AI-tool precedent:
  a tool's `input_schema` is load-bearing (§2.8). Our `ToolFile` Shrine binary
  attachment (`file_data`) must be replicated, not just the `content` column, or binary
  tools break at run time. A lossy copy is worse than no copy because it fails *later*. (High)
- **Polymorphic-scope correctness.** Set the clone's `scope` to the **target project**;
  never carry the source scope. (High)
- **NOT NULL JSONB arrays.** Mappers for array columns must always return an array
  (never `nil`) or the copy transaction aborts. (High)
- **Pass-through, don't fork, shared-by-design resources** (System agents, internal MCP,
  platform tools) — forking them pollutes the project and breaks the stable interface
  contract (the dbt/Terraform reference lesson). (High)
- **Don't deep-copy externally-owned resources** (managed MCP owned by an `Integration`
  via FK cascade): you can't own a detached copy; pass through if still visible, else
  drop + flag (Make's `null`-mapping precedent). (High)
- **Transaction boundary** around the whole copy; batch-load source resources to avoid
  N+1 across steps. (Medium)

---

## 4. Concrete Libraries & Approaches (Rails + Pundit + React)

### 4.1 `amoeba` — model-DSL deep copy

`amoeba` declares copy behavior **on the model** with `inclusive`/`exclusive`/
`indiscriminate` modes, recurses into enabled children/grandchildren, can `clone` (vs
re-associate) `has_many :through`/HABTM records, and offers `nullify` / `customize` /
`override` / `prepend` / `append` / `regex` / `set` field transforms
([amoeba README](https://github.com/amoeba-rb/amoeba)). Its `customize` block runs "a
lambda block… that take[s] two parameters, the original object and the newly copied
object," so as a *usage pattern* you can use it to record old association IDs onto the
copy — but this is a hook you write yourself, not a documented built-in remap feature.

**Pitfalls that matter for us (High):** the README explicitly states behavior is
**undefined** for "copying nested hierarchical models" (e.g. `parent_id`) and for
"polymorphic `has_many` associations," and it makes **no mention of JSONB** handling.
Our model is *all polymorphic scope + JSONB-arrays-of-foreign-IDs*, i.e. squarely in
amoeba's undefined zone. Configuring copy behavior on the model is also a poor fit for a
copy that must behave **differently by target scope** (copy into Project, identity into
Company).

### 4.2 `rails_deep_copy` — recursive association deep copy with FK reassignment

`rails_deep_copy` (LaunchPadLab) is the most on-the-nose gem for the stated problem: it
"creates a deep duplicate of any active record object, its infinitely deep descendants,
and reassigns their foreign keys appropriately"
([rails_deep_copy README](https://github.com/LaunchPadLab/rails_deep_copy)). It walks
`has_many`/`has_one` associations, duplicates each descendant, and rewrites the child's
foreign key to point at the newly-created parent — and you can override which associations
are duplicable on the model.

**Why it still doesn't fit us (High):** like `amoeba` and `deep_cloneable`, it reassigns
**real ActiveRecord foreign keys on real associations**. Our cross-resource references are
**JSONB arrays of bare foreign IDs** (`tool_ids`/`skill_ids`/`mcp_server_ids`/`base_*_ids`)
plus a single polymorphic scope — none of which the gem models as associations, so it has
nothing to reassign there and would copy those JSONB columns verbatim (the dangling-ID
bug). Its automatic-descendant traversal also can't express our per-type copy/skip/
pass-through rules (System agent, internal MCP, platform tool, managed MCP). It confirms
the deep-copy-with-FK-remap idea is mainstream, but doesn't change the hand-roll verdict.

### 4.3 `deep_cloneable` — call-site deep copy with a dictionary

`deep_cloneable` declares associations **at the call site** (`deep_clone include: …`)
and uses a **`dictionary` (the identity map) so models aren't duped multiple times** —
"storing a mapping of the original object to its duped object"
([deep_cloneable README](https://github.com/moiristo/deep_cloneable),
[source](https://github.com/moiristo/deep_cloneable/blob/master/lib/deep_cloneable/deep_clone.rb)).
It exposes `skip_missing_associations` to "skip missing associations" instead of raising
`DeepCloneable::AssociationNotFoundException` (same README) — the gem-level version of
our **defensive "leave unknown ID as-is" mapper**.

**Pitfalls (High):** community reports that `deep_cloneable` "had issues with circular
and nested associations not being cloned properly, creating duplicate models in
tree-like structures," which is why some teams switched to amoeba
([CookiesHQ](https://www.cookieshq.co.uk/posts/duplicating-models-with-complex-nested-associations)).
Like amoeba, it is built for **real ActiveRecord associations**, not **JSONB arrays of
bare foreign IDs** — it will faithfully copy the JSONB column *verbatim* (no remap),
which for us is exactly wrong (we must rewrite those IDs).

### 4.4 Verdict for our stack: hand-rolled copier with explicit per-type remap maps

All three gems share the same showstopper: **our cross-resource references are JSONB ID
arrays and a polymorphic FK, not associations the gems can traverse and remap.** A gem
would either (a) not see the JSONB IDs at all, copying them verbatim and re-creating the
dangling-reference bug, or (b) hit its own "undefined for polymorphic `has_many`" zone
(amoeba) / verbatim-copy-no-remap of the JSONB column (deep_cloneable, rails_deep_copy).

Therefore: **keep the manual `WorkflowDuplicator::DependencyCopier` with explicit
`map_agent_id` / `map_tool_ids` / `map_skill_ids` / `map_mcp_server_ids` methods, each
memoizing a `source_id → project_local_id` dictionary** (the clone-graph identity map,
§3.1). This is more code than a gem call but it is the only approach that:

- rewrites the JSONB ID arrays (gems can't),
- sets the polymorphic `scope` to the target project explicitly,
- applies per-type copy/skip/pass-through rules (System agent, internal MCP, platform
  tool, managed MCP, integration-gated tool),
- does idempotent find-or-reuse by natural key,
- and stays defensive (leave unknown IDs, never abort) like `skip_missing_associations`.

We **borrow the gems' proven ideas** (identity-map dictionary; skip-missing escape
hatch) without taking their constraints. (High)

### 4.5 Transaction, dedup, and performance specifics

- **One transaction** (`ActiveRecord::Base.transaction`) wrapping workflow + steps +
  copied dependencies, so a failure rolls back the entire copy — the "atomic dedup +
  mutation" idempotency guidance (§3.2). (High)
- **Natural-key dedup** via `target_project.<assoc>.find_by(name:)` then reuse; rely on
  the per-scope unique index as the backstop, with Tool's `find_by` scoped to
  `not_deleted` to match its partial unique index. (High)
- **Batch-load** distinct dependency IDs once (collect across all steps + `config`) and
  fetch source rows in bulk to avoid N+1 across steps. (Medium)
- **Shrine binary attachments**: replicate `file_data` (or re-upload `file`) for binary
  `tool_files`, not just `content` (§3.6). (High)

### 4.6 React/Inertia/Mantine + Pundit notes

- **No serialized-shape change** is required: the builder's deferred pickers already
  render whatever is `visible_for_project`, and steps store `number[]` ID arrays; we
  just write project-local IDs. No Typelizer regeneration. (High — from internal design)
- **Pundit**: the catalog `duplicate?` action already gates on company membership;
  copying dependencies introduces **no new authorization surface** because everything
  stays within the same company and project membership is already enforced. The
  copied resources inherit project scoping, so existing per-resource policies apply
  to the new project-local rows automatically. (High — from internal design)
- **Needs-setup banner** (if adopted, §3.5/D-UX) is an Inertia prop computed server-side
  after copy (list of dropped/gated/unresolved dependencies), rendered as a Mantine
  `Alert`/banner in `BuilderPage`. This is additive FE work, no schema change. (Medium)

---

## 5. Recommendations for palad-app

Tied directly to the internal design doc. All are **endorsements with sourced backing**,
plus a few refinements.

1. **Keep the deep-copy + per-type ID-remap design inside `WorkflowDuplicator`** (the
   identity-map clone-graph pattern, §3.1; mirrored by Make's clone-with-mapping-pairs,
   §2.1). It is the validated approach and the smallest consistent change. **(High)**
2. **Hand-roll the copier; do not adopt `amoeba`/`rails_deep_copy`/`deep_cloneable`** — all
   three operate on real ActiveRecord associations and none remaps JSONB ID arrays
   (amoeba is also explicitly undefined for polymorphic `has_many`) (§4.1–4.4). Borrow
   their identity-map dictionary and skip-missing-association ideas. **(High)**
3. **Hold the secret boundary at `ConfigItem` (never copy those rows); copy MCP
   `env`/`headers` verbatim**; reject the value-based scrub heuristic (§3.3). This is the
   universal precedent (Zapier/Make/n8n/Airflow/OWASP). **(High)**
4. **Idempotent reuse by `(scope, name)` natural key, in one transaction** (§3.2). Document
   the "same-name reuse points at the existing resource" behavior. **(High)**
5. **Pass-through (reference), don't fork, shared-by-design resources** — System agents,
   internal MCP servers, platform tools, and same-company shared `ConfigItem`s — and
   **don't deep-copy externally-owned managed MCP** (pass through if visible, else drop +
   flag, per Make's `null`-mapping, §2.1/§3.6). This is the dbt/Terraform reference-for-
   stable-interfaces lesson (§2.5–2.6). **(High)**
6. **Copy every field a dependency needs to actually run** — including `Tool.input_schema`
   (AI-framework schema lesson, §2.8) and **binary `tool_files` via Shrine `file_data`**,
   not just text `content` (§3.6). A lossy copy fails later and is worse than failing
   loudly. **(High)**
7. **Surface a "needs setup" banner** for the unresolvable-after-copy cases instead of
   silently dropping/gating (UiPath/Make validate-and-surface, §3.5; n8n's silent
   failure is the anti-precedent). **(Medium — recommend, costs FE work; see D-UX)**
8. **Validate the copy post-write** (Make's blueprint-analysis idea): after remap, assert
   no copied step references an ID that isn't `visible_for_project`, and feed the
   leftovers into the banner. Cheap insurance against the dangling-reference class. **(Medium)**

---

## 6. Open Decisions Informed by Research

### D1 — Are custom tools (not just agents/skills/mcp) in scope for v1?

**Recommendation: Yes, include custom tools. (Confidence: High)**

A custom `Tool` referenced by a copied step has the *identical* sharing/fragility
problem as an agent or skill — it is a project-editable resource a team needs to own,
not a stable platform interface. dbt's framing (§2.5) says copy-and-own is exactly right
for "a starting point you will customize," and a custom tool is that. Excluding tools
would leave a partial dependency graph and reproduce n8n's dangling-reference class for
the one resource type most likely to be tweaked per project. The only real cost is the
**binary `tool_files` / `input_schema` fidelity** work (§3.6, §2.8), which is bounded and
must be done correctly regardless. Platform tools (`system`/`internal`/`workflow`/`meta`)
are pass-through (reference), consistent with the Terraform/dbt reference-for-shared rule.

### D2 — Backfill existing already-copied workflows, or only fix new copies?

**Recommendation: Only fix new copies by default; offer backfill as an explicit, opt-in,
idempotent migration — do not auto-run it. (Confidence: Medium)**

Idempotency research says a natural-key-based copy is safely re-runnable (§3.2), so a
backfill *is* technically safe (re-running maps each already-local ID to itself, a
no-op). But **GitHub's "disconnected instance"** and **dbt's "don't silently change a
running consumer"** lessons argue against silently forking shared resources for projects
that are working today: a backfill changes behavior (the project stops tracking the
shared resource) out from under teams who didn't ask for it. Make/Power Platform treat
re-instantiation as an explicit user action with validation, not a background sweep.
So: ship the fix forward-only; provide a guarded rake task / data migration that product
can trigger per-company or per-project when desired, gated behind an explicit decision.

### D3 — Always copy dependencies vs an opt-in "copy dependencies" checkbox?

**Recommendation: Always copy (no checkbox) for v1; revisit only if a "link to shared"
mode is ever requested. (Confidence: Medium-High)**

GitHub template repos, Backstage scaffolding, and Zapier templates all instantiate a
**complete, self-contained, disconnected instance by default** — the user does not toggle
"also bring the files" (§2.2, §2.3, §2.7). The acceptance criterion ("all required
agents, skills and MCPs already available… without any manual setup") *is* "always copy."
A checkbox adds a decision the user must understand (and a half-copied workflow is the
dangling-reference footgun, §3.4). The opt-in pattern only makes sense if we wanted to
offer a *reference/link* alternative (the Zapier "shared connection" model), which is a
separate, later feature — not a v1 toggle. Keep v1 unconditional; the default matches
every "copy" precedent.

### D4 — Missing-dependency UX: silent vs "needs setup" banner

**Recommendation: Surface a "needs setup" banner. (Confidence: Medium)**

This is the most evidence-backed of the open decisions. **Silent handling is the exact
anti-pattern other platforms regret** — credential-related errors are "one of the most
frequent causes of workflow import failures in n8n," with imported credential references
that don't bind in the target instance (§2.4), and Power Platform surfaces missing
connection references explicitly rather than letting deploys quietly break (§3.4). The
validated pattern is UiPath Studio's: mark the unresolved items and **show an error/info
banner naming what to connect or add** (§3.5), and notify early rather than at run time
(Pencil & Paper). For us the banner enumerates: dropped managed-MCP references (D4 in the
design), integration-gated copied tools (`requires_integration` not connected), and
`config_item:NAME` references whose `ConfigItem` the target company lacks. Cost is
additive FE work (a server-computed Inertia prop + Mantine `Alert`); if v1 must be lean,
ship silent-but-defensive *and* a post-copy validation log, and fast-follow the banner —
but the banner is the right destination.

### D5 — Copy vs reference for shared company-level resources

**Recommendation: Hybrid — copy project-editable resources, reference (pass through)
shared-by-design ones; keep `ConfigItem` as a same-company reference. (Confidence: High)**

This is the central architectural call and the research gives a crisp rule, from dbt's
explicit framing (§2.5): **copy (package) when the consumer should own and customize;
reference (dependency) when the resource is a stable, maintainer-owned interface.**
Mapped to our resources:

- **Copy** (project-local, editable): custom Agents, Skills, custom MCP servers, custom
  Tools — these are "a starting point you will customize" (#302's whole purpose).
- **Reference / pass-through** (keep the ID): System agents, internal MCP servers,
  platform tools — stable interfaces shared by design; forking them pollutes the project
  and breaks the contract (Terraform's reference-for-3+-consumers lesson, §2.6).
- **Reference by name** (never copy): `ConfigItem` secrets — Airflow's `conn_id` / Make's
  blueprint-strip / Zapier's exclude-connections precedent (§3.3). The team supplies its
  own values; the `config_item:NAME` reference travels with the copy and resolves in the
  same-company target.
- **Externally-owned, can't-be-copied** (managed MCP via `Integration`): pass through if
  still visible, else drop + flag (Make's `null`-mapping, §2.1).

Pure-reference-everything (n8n/Terraform style) fails #302's editability goal;
copy-everything (including secrets, or including platform resources) violates the secrets
boundary and pollutes the project. The hybrid is what the survey converges on.

---

## 7. Sources & Confidence

Confidence reflects source authority and corroboration. Primary vendor docs = higher;
single blog posts = lower.

### Industry precedents — copy/reference/secrets

1. **Make.com — Scenario clone API (entity ID mapping pairs; `null` to omit; blueprint
   analysis)** — High — https://developers.make.com/api-documentation/api-reference/scenarios
2. **Make.com — Blueprints require recreating connections after import (page states "users still need to create connections"); the widely-cited "do not store your real connection details like API keys" phrasing is corroborated by community write-ups** — Medium (help page confirms substance; exact verbatim phrasing corroborated, not on the help page render) — https://help.make.com/blueprints
2a. **Make.com — blueprint backup walkthrough (corroborates "Blueprints do not store your real connection details… reconnect your apps")** — Low — https://medium.com/@tremblayjustin89/how-i-backup-my-make-com-scenarios-3d749b302213
3. **GitHub — Creating a repository from a template (template repo "starts with a single commit"; branches "have unrelated histories")** — High — https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template
4. **GitHub repo templates — disconnected, no shared history (corroboration; source of the "no connection to the original" framing)** — Medium — https://dev.to/gitprotect/how-to-use-github-repository-templates-3dfk
5. **Zapier — Share a template (excludes connections & field values)** — High — https://zapier.com/help/manage/collaborate/share-a-copy-of-your-zap
6. **Zapier — Share app connections (separate, explicit; recipients can view test data)** — High — https://help.zapier.com/hc/en-us/articles/8496326497037-Share-app-connections-with-members-of-your-Team-or-Enterprise-account
7. **n8n — Export and import workflows (exported JSON "include[s] credential names and IDs")** — High — https://docs.n8n.io/build/manage-workflows/export-and-import
8. **n8n — issue #20049 "Imported Workflows Break Credentials Across CMD and Render Instances" (credentials present in global section but unusable; error "unrecognized credential type: oauth2api")** — Medium — https://github.com/n8n-io/n8n/issues/20049
9. **n8n — import troubleshooting (credential errors "one of the most frequent causes" of import failures; JSON "only includes credential names and IDs, leaving out sensitive information"; recreate or manually map credentials)** — Medium — https://latenode.com/blog/low-code-no-code-platforms/n8n-setup-workflows-self-hosting-templates/n8n-export-import-workflows-complete-json-guide-troubleshooting-common-failures-2025
10. **dbt — Packages (copy full source; you own/maintain)** — High — https://docs.getdbt.com/docs/build/packages
11. **dbt — Project dependencies (reference via metadata service; not pulled down)** — High — https://docs.getdbt.com/docs/mesh/govern/project-dependencies
12. **Terraform — module block (registry source + version constraints)** — High — https://developer.hashicorp.com/terraform/language/block/module
13. **Terraform module best practices (registry reference for 3+ consumers)** — Medium — https://instadevops.com/blog/terraform-modules-best-practices/
14. **Backstage — Writing software templates ("a small yaml definition… input variables… and then a list of actions which are then executed by the scaffolding service", e.g. fetch:template/fetch:plain)** — High — https://backstage.io/docs/features/software-templates/writing-templates/
15. **Airflow — Managing connections (reference conn_id; secrets in backend, not DAG)** — High — https://airflow.apache.org/docs/apache-airflow/stable/howto/connection.html
16. **CrewAI — Agents (template variables role/goal/backstory)** — Medium — https://docs.crewai.com/en/concepts/agents
17. **LangChain/CrewAI tool adapters (tool input-schema mismatches)** — Low — https://daily.dev/blog/ai-agents-guide-for-developers-langchain-crewai/

### Patterns & pitfalls

18. **Clone-graph: hash-map identity map = visited-set + lookup; cycles; linear time** — High — https://algomaster.io/learn/dsa/clone-graph
19. **Clone-graph in-depth (shared nodes/cycles via map)** — Medium — https://algo.monster/liteproblems/133
20. **Brandur — Implementing Stripe-like Idempotency Keys in Postgres (UNIQUE constraint on the idempotency key scoped `(user_id, idempotency_key)`; API actions wrapped in transactions; atomic phase committed before foreign-state mutation; 409 Conflict on concurrent duplicate)** — High — https://brandur.org/idempotency-keys
20a. **DEV — Understanding idempotency in APIs (client sends a unique UUID key; server stores key and response — high-level only, no DB-constraint/transaction detail)** — Low — https://dev.to/msnmongare/understanding-idempotency-in-apis-and-distributed-systems-3afb
21. **DesignGurus — Idempotency in distributed systems (Redis/DB table + TTL; combine key with user ID/endpoint)** — Medium — https://www.designgurus.io/blog/idempotency-in-distributed-systems
22. **OWASP MCP Top 10 — MCP01:2025 Token Mismanagement & Secret Exposure** — High — https://owasp.org/www-project-mcp-top-10/2025/MCP01-2025-Token-Mismanagement-and-Secret-Exposure
23. **OWASP Secrets Management Cheat Sheet** — High — https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
24. **Azure — Key Vault parameter (reference vault by ID; value never exposed)** — High — https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/key-vault-parameter
25. **MCP secret-management best practices (runtime injection; never in config/git)** — Medium — https://www.doppler.com/blog/mcp-server-credential-security-best-practices
26. **UiPath Studio — Managing dependencies ("Missing or invalid activities are marked in the Designer panel, while an error banner provides additional information regarding the workflow and its unresolved dependency conflicts")** — High — https://docs.uipath.com/studio/docs/managing-dependencies
27. **Error-feedback UX patterns (inline/banner/modal; notify early)** — Medium — https://www.pencilandpaper.io/articles/ux-pattern-analysis-error-feedback
28. **Power Platform missing-dependency / connection-reference import failures** — Medium — https://d365demystified.com/2020/10/14/there-are-missing-dependencies-install-the-following-solutions-before-installing-this-one-active-connection-references-missing-in-power-platform-solution/
29. **Power Automate — fixing missing dependencies** — Low — https://dev.to/wyattdave/power-automate-how-to-fix-missing-dependencies-m5i
30. **Monorepo coupling vs duplication tradeoff (when to reuse vs reimplement)** — Low — https://dev.to/dortort/monorepo-vs-multi-repo-why-ai-agents-tip-the-scale-1cdj

### Rails libraries

31. **amoeba README (modes; recursion; many-to-many clone; `customize` lambda takes original+copy; *undefined* for polymorphic has_many & nested parent_id; no JSONB)** — High — https://github.com/amoeba-rb/amoeba
31a. **rails_deep_copy README (LaunchPadLab) — "Creates a deep duplicate of any active record object, its infinitely deep descendants, and reassigns their foreign keys appropriately"; walks has_many/has_one only, no JSONB/bare-ID-array remap** — High — https://github.com/LaunchPadLab/rails_deep_copy
32. **deep_cloneable README (call-site include; dictionary identity map; skip_missing_associations)** — High — https://github.com/moiristo/deep_cloneable
33. **deep_cloneable deep_clone source (dictionary implementation)** — Medium — https://github.com/moiristo/deep_cloneable/blob/master/lib/deep_cloneable/deep_clone.rb
34. **CookiesHQ — duplicating complex nested associations (deep_cloneable circular/nested issues; switched to amoeba)** — Medium — https://www.cookieshq.co.uk/posts/duplicating-models-with-complex-nested-associations

### Conflicting / nuanced sources

- **Copy vs reference is genuinely contested across platforms** — GitHub/Zapier/Backstage
  favor *copy a disconnected instance*; Terraform/dbt-project-dependencies/n8n favor
  *reference a shared resource*. They do **not** actually conflict: the deciding variable
  is **"does the consumer need to edit it?"** — copy when yes (our project resources),
  reference when no (our platform/secret resources). dbt is the source that states both
  sides explicitly (sources 10–11), and our hybrid recommendation follows its rule.
- **amoeba vs deep_cloneable (vs rails_deep_copy) for complex graphs** — source 34 reports
  teams *leaving* deep_cloneable for amoeba on circular/nested graphs, while deep_cloneable's
  own docs (sources 32–33) tout its dictionary for exactly that; rails_deep_copy (source
  31a) offers automatic FK reassignment but only over real associations. We treat the
  gem-vs-gem debate as moot for us because **none of the three handles our JSONB-ID-array
  remap**, so we hand-roll (§4.4).
- **Make credential transfer on same-team clone** — the API docs (source 1) detail entity
  *ID mapping* but are explicit only about *cross-team* and `null`-mapping; they "do not
  explicitly detail" whether same-team clone re-uses the original connection credentials.
  We rely on the *blueprint* behavior (source 2: secrets stripped) for the secret-exclusion
  claim, not the same-team clone path. (Noted as a Low-confidence gap on Make's same-team
  credential behavior.)

### Web search queries used

1. `n8n workflow template how dependencies credentials are handled when importing template into instance`
2. `Backstage software templates scaffolder how dependencies are copied template to instance`
3. `Rails deep copy associations amoeba vs deep_cloneable gem comparison nested associations`
4. `Zapier templates Shared App Connections vs copy when using a Zap template credentials`
5. `Make.com blueprint clone scenario connections not exported credentials remapping`
6. `Terraform module reference vs copy registry shared module versioning composition`
7. `dbt packages vs copy models how dbt handles dependency reuse package management`
8. `GitHub template repository creates independent copy no shared history disconnected from source`
9. `LangChain templates CrewAI templates how agents tools copied scaffolded into project`
10. `idempotent operations distributed systems dedupe natural key upsert transactional consistency best practices`
11. `copying object graph remap foreign key references identity map cycle detection deep clone algorithm`
12. `secret management never store secrets in template reference vault by name re-provision credentials best practice`
13. `MCP server configuration secrets environment variables never hardcode reference env best practice 2025`
14. `broken reference missing dependency UX pattern "needs setup" banner reconnect required workflow editor`
15. `deep_cloneable gem dictionary skip_missing_associations Rails clone postgres jsonb column behavior`
16. `Apache Airflow DAG connections variables not stored in DAG code reference connection id by name`
17. `monorepo shared library vs copy duplication "rule of three" coupling tradeoff when to copy vs reuse`
18. `n8n credentials referenced by id not exported import maps credential id reconnect "Credentials not found"`

Direct primary-source fetches: Make scenario clone API; amoeba README.
