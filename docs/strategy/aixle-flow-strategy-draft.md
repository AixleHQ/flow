# Product strategy: Aixle flow — 12-month horizon

> **Status:** Draft · **Version:** 0.2 · **Date:** April 2026 · **Revised:** July 2026
> **Market:** USA · **Horizon:** 12 months
>
> **v0.2 (July 2026):** § 3 Competitors rewritten around the six-layer infrastructure
> map — added OpenHands, Omnigent (Databricks), Conductor, Agent Orchestrator, Gas Town
> + Beads, the layer-5 sandbox vendors (E2B, Daytona, K8s Agent Sandbox, …) and the
> local-dispatcher tier. § 5 differentiator table and market evidence updated
> accordingly. Sections 6–8 (focuses, roadmap, metrics) were **not** re-derived against
> the new competitive picture — see the open follow-up at the end of § 3.

---

## Navigation

- [1. Market and trends](#1-market-and-trends)
- [2. JTBD and users](#2-jtbd-and-users)
- [3. Competitors](#3-competitors)
- [4. The product today (as-is)](#4-the-product-today-as-is)
- [5. Vision and bet](#5-vision-and-bet)
- [6. Strategic focuses](#6-strategic-focuses)
- [7. 12-month roadmap](#7-12-month-roadmap)
- [8. Metrics and success](#8-metrics-and-success)
- [★ Customer dev and observations](#-customer-dev-and-observations)
- [★★ AI customer dev](#-ai-customer-dev)
- [A. AI newcomers and fast growers](#a-ai-newcomers-and-fast-growers)
- [B. Two visions](#b-two-visions)

---

## 1. Market and trends

### Market size

| Segment | 2025 | 2026 | 2030 | CAGR | Source |
|---------|------|------|------|------|----------|
| AI Agent Orchestration Platforms | $5.8B | $8.5B | $35–45B | 23–43% | MarketIntelo, Apr 2026 |
| Enterprise AI Workflow Automation (North America) | ~$2.2B (38% share) | ~$3.2B | — | — | Intelevore Research, Apr 2026 |
| AI-powered project management / Dev tools | part of $5.8B | — | — | — | Deloitte Tech Predictions 2026 |

**Key signal:** North America holds 38–44% of the global AI Agent Orchestration market and is growing faster than other regions (Intelevore Research, Apr 2026). The USA is the entry point and flagship market.

---

### 4 key trends

**Trend 1 — Agents have moved from toy to working tool**
Devin ARR: $1M → $73M in 9 months (Sept 2024 — June 2025). Cursor is valued at $50B (March 2026). Cognition is raising at a $25B valuation (Apr 2026, SiliconAngle). The market is no longer experimental — companies are paying real money for AI agents right now.

**Trend 2 — The agent coordination problem is becoming the critical path**
Single agents (Claude Code, Cursor) solve an individual job. But when a team of 5+ people works, with some tasks delegated to agents, there is no tool that holds the entire context: who launched what, at what stage, what is blocked. This is an unfilled gap.

**Trend 3 — Enterprise demands controllability, not autonomy**
Goldman Sachs, Citi, Cisco (clients of Devin, Cognition 2026) don't want “magic.” They need audit trails, approval gates, cost tracking, and control over what the agent does. The market is moving from “watch how smart AI does it all” to “we control the AI workflow.”

**Trend 4 — Warning signal: platform players are locking down basic orchestration**
GitHub Copilot Workspace, Azure AI Foundry, Google Vertex AI, AWS Bedrock Agent — every big cloud player is building its own orchestration layer. The window for an unfilled market is narrowing. Specialized solutions must show a defensible moat within 12–18 months.

---

## 2. JTBD and users

### Evolution of the user's main request

| Year | Request | How it was solved |
|-----|--------|-------------|
| 2022 | “Write code for me” | GitHub Copilot, TabNine — completion in the IDE |
| 2023 | “Help me with a task” | ChatGPT, Cursor — dialogue + file context |
| 2024 | “Execute the task autonomously” | Claude Code, Devin — an agent with terminal access |
| 2025–2026 | **“Launch and coordinate several agents on different tasks so that I don't lose control”** | ← **Aixle closes this gap** |

---

### 5 key JTBDs

**JTBD 1 — The main, unfilled one**
*“When I want to delegate several tasks to AI agents in parallel, I want to see a single place where everything happens and where I can intervene at any moment, so I don't lose control over the project and don't have to collect results from five different terminals.”*
— Who experiences it: Engineering Lead, CTO at a startup, Solo DevOps
— Current coverage: nothing / a workaround (Notion + GitHub + manual tracking)
— Competitors: 0/5 cover it fully
— Pain intensity: **critical**

**JTBD 2 — Important, partially covered**
*“When I set up an AI agent for a recurring task (code review, test generation), I want to describe the process once and never come back to it, so my team runs it like a button without my involvement.”*
— Who experiences it: Staff Engineer, Engineering Manager
— Current coverage: GitHub Actions + prompts in a document (a brittle workaround)
— Competitors: 1/5 (Codegen.ai partially)
— Pain intensity: **important**

**JTBD 3 — Important for enterprise**
*“When an AI agent works on our code, I want to see a full log of exactly what it did, how much it cost, and where it made a debatable decision, so I can explain it to the team and not sign off on a \"black box.\"”*
— Who experiences it: CTO, Security Engineer, Compliance Lead
— Current coverage: nothing
— Competitors: 0/5
— Pain intensity: **critical for enterprise**

**JTBD 4 — Important for adoption**
*“When I want to start using AI agents in my workflow, I want to get a working first example in 15 minutes rather than reading documentation for 3 hours, so I can confirm it works for my tasks at all.”*
— Who experiences it: Solo Developer, Junior PM
— Current coverage: partially (Cursor onboarding is better)
— Competitors: 2/5
— Pain intensity: **important**

**JTBD 5 — Growing**
*“When I need to standardize AI processes across the team, I want to create templated workflows that every developer runs the same way, so the result doesn't depend on the prompting skills of a particular person.”*
— Who experiences it: Engineering Manager, Platform Team Lead
— Current coverage: nothing / Notion templates
— Competitors: 0/5
— Pain intensity: **nice to have → critical at scale**

---

### 5 user personas

---

**Persona 1 — Alex, 32, Engineering Lead · San Francisco**
*Leads a team of 8 developers at a B2B SaaS startup. Personally experiments with Claude Code and Cursor, but can't “carry” the AI setup for the whole team.*

- **Device:** MacBook Pro, terminal as the primary environment
- **Frequency:** daily
- **Income:** $180K+
- **Top 3 pains:**
  1. Agents are launched differently by each person — no standard, no visibility
  2. When an agent breaks in the middle of a task, it is unclear at which step and why
  3. Hard to explain the ROI of AI tools to a manager without data
- **Primary JTBD:** "When I scale AI workflows across the team, I want to see what the agents are doing right now and have levers of control, so the team works faster and I am not manually supervising every run."
- **Quote:** *"I love Claude Code but it's my personal superpower — my team doesn't use it the same way and I can't scale that."* [AI simulation]

---

**Persona 2 — Sarah, 28, Full-Stack Developer (Solo/Freelance) · Austin, Texas**
*Works independently, running 3-4 client projects in parallel. Active user of Claude Code and Cursor.*

- **Device:** MacBook + iPad
- **Frequency:** daily
- **Income:** $90-120K/year
- **Top 3 pains:**
  1. Switching between terminals during parallel tasks loses context
  2. No history of what the agent did, making it hard to hand off work to the client
  3. Every new project starts from scratch, with no way to reuse a configured workflow
- **Primary JTBD:** "When I juggle several AI tasks at once, I want a single point of control without switching tabs, so each client gets a clear trail of what was done."
- **Quote:** *"I already live in the terminal — I just want one place to see what all my agents are up to."* [AI simulation]

---

**Persona 3 — Marcus, 41, CTO · New York**
*Serial entrepreneur, 3rd startup. Team of 15. Tracks AI trends as a strategist but is technically behind the team.*

- **Device:** MacBook, Chrome, Slack as the primary environment
- **Frequency:** 2-3 times per week
- **Income:** $250K+ + equity
- **Top 3 pains:**
  1. Does not understand the real return from AI tools — no data
  2. Afraid to "hand off" critical tasks to agents without visibility
  3. The team uses different tools — no unified picture
- **Primary JTBD:** "When AI agents work across the team, I want to see what is happening, how much it costs, and where the risks are, so I can make AI investment decisions based on data rather than intuition."
- **Quote:** *"If I can't explain to the board what our AI is doing, I'm not shipping it."* [AI simulation]

---

**Persona 4 — Jordan, 35, Platform/DevOps Engineer · Remote (USA)**
*Responsible for AI pipeline infrastructure at a 50+ person company. Technically strong, skeptical of vendor lock-in.*

- **Device:** Linux / multiple terminals
- **Frequency:** daily
- **Income:** $160K
- **Top 3 pains:**
  1. Every new AI tool = a new integration and a new security review
  2. No standard for running agents in a containerized environment
  3. Hard to set up approval gates without custom code
- **Primary JTBD:** "When I run AI agents in a production environment, I want a container-native platform with an audit log and configurable approval gates, so compliance does not turn into manual work."
- **Quote:** *"Show me the Temporal workflow graph and let me override steps — that's all I need."* [AI simulation]

---

**Persona 5 — Priya, 30, Product Manager (AI-first company) · Seattle**
*PM at a startup where developers actively use agents. Does not write code herself, but assigns tasks on the Board and expects results.*

- **Device:** MacBook + iPhone
- **Frequency:** daily (as a Board user)
- **Income:** $130K
- **Top 3 pains:**
  1. Does not understand what is happening while the agent works — the status is opaque
  2. A task "flew off" to the agent — when will it come back and in what form?
  3. Cannot easily assign a task to AI without a developer's help
- **Primary JTBD:** "When I hand a task to the development team, I want to see live status without having to ping engineers, so I can plan the sprint based on the real progress of the AI workflow."
- **Quote:** *"I move the ticket to 'In Progress' and then... silence. I have no idea if the agent is working or stuck."* [AI simulation]

---

## 3. Competitors

> **Revised July 2026.** The April cut of this section only tracked SDLC-orchestration
> products (Devin, Codegen, Overcut, Forge, Atum). Through H1 2026 the market
> reorganized into six infrastructure layers, and a set of players landed directly on
> the layers Aixle occupies — most importantly **OpenHands** and **Databricks
> Omnigent**, neither of which was in the previous analysis. See
> [layer map](#layer-map) for who sits where.

### Layer map

The 2026 stack splits into six layers. Aixle spans three of them at once, which is
both the differentiator and the reason the competitive set is wider than a
feature-by-feature comparison with Devin suggests.

| Layer | What it decides | Who is there | Aixle's position |
|-------|-----------------|--------------|------------------|
| 1. Agent / harness | Quality of a single agent's work | Claude Code, Codex, Cursor CLI, Gemini CLI, OpenCode, Devin, Jules | **Consume, not compete** — adapters per agent |
| 2. Protocol / interop | How agents reach tools and hosts | MCP (Anthropic, Nov 2024), ACP (Agent Client Protocol) | MCP-native; **ACP not supported — gap** |
| 3. Workspace | Sessions, worktrees, diff review, UI | Orca, cmux, Conductor, Superset, Sculptor, agent-deck, Warp, Claude Squad, Coder mux | **Compete** (Board + session UI) |
| 4. Orchestration | Queues, state, policies, PR/CI loop | OpenHands, Omnigent, Gas Town + Beads, Agent Orchestrator, GitHub Agent HQ | **Compete — core bet** (Temporal, workflow engine, assets) |
| 5. Sandbox / runtime | Trust boundary, reproducibility | E2B, Daytona, Docker Sandboxes, Container Use, AgentTier, K8s Agent Sandbox, Anthropic sandbox-runtime | **Build our own** (`DockerRuntime`, `KubernetesRuntime`) — buy/adopt candidate |
| 6. IDE platform | Ecosystem foundation | Eclipse Theia + Theia AI, VS Code | **Not our play** |

---

### Market financial map

| Player | ARR / Revenue | Funding / Valuation | Momentum | Source |
|-------|--------------|------------------------|----------|---------|
| **Cursor** | ~$300M ARR (estimate) | ~$50B valuation (March 2026) | ↑↑ Hypergrowth | SiliconAngle, March 2026 |
| **Cognition / Devin** | $73M ARR (June 2025) | $25B valuation target (Apr 2026) | ↑↑ | SiliconAngle, Apr 2026 |
| **GitHub Copilot** | Part of $44B GitHub | Microsoft, public | ↑ Steady growth | — |
| **OpenHands** | No public ARR (OpenHands Cloud paid tier) | VC-backed OSS, ~79.6k★ | ↑↑ Largest OSS mindshare | GitHub + openhands.dev, Jul 2026 |
| **Omnigent (Databricks)** | Bundled — no standalone revenue | Databricks balance sheet (~$100B valuation) | ↑↑ New (13 Jun 2026) | Databricks blog, Jun 2026 |
| **Conductor** | Free product, no revenue yet | $22M Series A (Mar 2026), YC | ↑ | Public reporting, 2026 |
| **Orca** | Free, MIT | Stably AI | ↑↑ ~27.4k★ in ~4 months | onorca.dev, Jul 2026 |
| **E2B** | Usage-based cloud | Seed/Series A, ~13k★ | ↑ Steady since Mar 2023 | e2b.dev, 2026 |
| **Daytona** | Usage-based cloud | VC-backed, ~72.3k★ | ↑ | daytona.io, 2026 |
| **Codegen.ai** | $0 public data (1000+ teams) | Seed/Series A | ↑ Early traction | Website, 2026 |
| **Overcut** | No public data | No public data | New | Website, 2026 |
| **n8n** | ~$20M ARR (2025 estimate) | Series B, $56M (2024) | ↑ Steady | TechCrunch, 2024 |
| **Vibe Kanban** | — | — | **Dead — shut down 10 Apr 2026** | vibekanban.com/blog/shutdown |

---

### Tier 1 — Platform giants (dominant by reach)

**GitHub Copilot / Copilot Workspace / Agent HQ**
Built into 150M+ GitHub accounts. Agent mode added in 2025; **Agent HQ ("mission
control") shipped Fall 2025** and now coordinates multiple agents natively inside
GitHub. Strength — zero install cost, existing ecosystem, owns the repo and CI where
the work lands. Weakness — no durable execution engine, no PM-facing workflow layer,
no custom container images. Strategic shift vs April: Agent HQ eats the *bottom* of
the workspace layer, so "we coordinate agents" alone is no longer a defensible pitch
for GitHub-native teams.

**Cursor**
$50B valuation, ~300M ARR. IDE-first. Huge solo-developer base. Weakness — no board,
no multi-step team workflows, no approval gates, no container execution.

**OpenAI Codex app** — added worktree support Feb 2026. **Anthropic Claude Code** —
sub-agents plus team features. Both vendors are absorbing single-user parallelism into
the harness itself, which is what compressed the standalone dispatcher market (see
Tier 4).

---

### Tier 2 — Direct competitors

**2a. New in July 2026 — same layers as Aixle (orchestration + runtime)**

| Product | What it is | Overlap with Aixle | What it lacks |
|---------|-----------|--------------------|---------------|
| **OpenHands** (~79.6k★, OSS + OpenHands Cloud) | Started as OpenDevin, now an agent-agnostic control center. **Agent Canvas** runs OpenHands, Claude Code, Codex, Gemini CLI, or any ACP agent side by side over local / remote / cloud backends; commands execute through a separate action server against a Docker runtime | **Closest competitor overall.** Agent-agnostic sessions, Docker runtime, web UI, automations, hosted cloud tier — and **OpenHands Cloud injects the user's subscription auth at session start**, the only public analogue of our Agent Auth onboarding | Durable execution (no Temporal-class engine), multi-tenant Company→Project scoping, usage-based billing, workflow engine with versioned assets and approval gates, PM-facing surface |
| **Omnigent (Databricks)**, Apache-2.0, 13 Jun 2026 | "Meta-harness": a **runner** wraps any agent in a *sandboxed session* behind a uniform API; a **server** adds policies and sharing and exposes every session over terminal, app, and web APIs. Supports Claude Code SDK, Codex, Cursor, Pi, LangGraph, Agno, CrewAI, plus YAML-defined custom agents | Directly duplicates our agent-abstraction layer **and** our policy/quota layer: session budgets, escalating restrictions on risky actions, unified API across heterogeneous agents. Databricks distribution and budget | Workflow engine, board, assets/versioning, K8s-grade multi-runtime, multi-tenant SaaS with billing. It is a control plane, not a product for a team's process |
| **Conductor** ($22M Series A, Mar 2026, YC) | Free macOS app running Claude Code, Codex, Cursor, OpenCode in isolated git worktrees. Deliberately narrow — orchestration only, no planning/docs/review | Parallel-agent UX, team ambitions, institutional funding | Local-only (macOS), worktrees not containers, no server, no workflows, no audit layer. **Note:** funded ≠ validated — it is free with no revenue model yet |
| **Agent Orchestrator** (Composio → AgentWrapper) | Closes the PR/CI loop: feeds CI failures, review comments, and merge conflicts back to the agent, auto-rebases | Overlaps the part of our workflow engine we have **not** built — outer-loop feedback | Documented risks: agent games the tests, flaky tests cause loops, broad repo/CI token scope. Needs attempt caps, budgets, mandatory human gate before merge |
| **Gas Town + Beads** (Steve Yegge, Jan 2026; ~15k★ + ~25k★) | Role-based agent "factory" (Mayor, Polecats, Witness, Monitor, Refinery) with structured state persisted in Git, surviving individual model sessions | Conceptually our `WorkflowRun` / `SubStepRun` / assets — proof that persistent cross-session state is a real need | Files-in-Git instead of a database, expensive in tokens and attention, no UI, no tenancy. Validates the problem, not a competing product |

**2b. SDLC-orchestration products (April cut, still valid)**

| Product | Description | Strengths | User pains | Strategic gap |
|---------|---------|-----------------|-------------------|-------------------|
| **Devin (Cognition)** | Autonomous AI software engineer, own cloud sandbox, opens PRs | End-to-end tasks, enterprise customers | Expensive ($500+/mo team), "black box", no team board | No team workflow editor, no custom agents, single vendor agent |
| **Jules (Google)** | Async agent: clones the repo to a cloud VM, plans, edits, opens a PR | Zero setup, Google infrastructure | Single vendor agent, no team layer | Not a platform — one agent behind an API |
| **Codegen.ai** | "OS for Code Agents", Linear/Jira integration | 5-min setup, 1000+ teams | Limited customization, no container isolation | No board of its own, runs on top of Linear/Jira |
| **Overcut** | Enterprise agentic SDLC orchestration | Integrations (Jira, GitLab, GitHub), drag-and-drop workflows | Enterprise-only pricing presumably, no public data | Unknown degree of agent customization |
| **Forge** | Tickets → merged PRs | Specialized in PR flow, cost estimate per step | Narrow scope (coding PR only), private beta | Does not work beyond coding workflows |
| **Atum** | Ideation to deployment, SDLC platform | Budget tracking, Figma/Jira/GitHub integrations | Early access, immature | No container execution |

---

### Tier 3 — Layer 5 infrastructure: buy-vs-build, not competitors

These do not compete with Aixle; they compete with **our own runtime code**. Each is a
candidate to sit behind the Runtime interface next to `DockerRuntime` /
`KubernetesRuntime`.

| Product | Isolation | Why it matters to us |
|---------|-----------|----------------------|
| **E2B** (~13k★, since Mar 2023) | microVM, separate kernel | SDK-driven isolated Linux VMs: templates, snapshots, interactive terminal, SSH, network policies. A managed third runtime — stronger boundary than a container, no K8s to operate |
| **Daytona** (~72.3k★, since Feb 2024) | microVM, own kernel/FS/network | Same shape as E2B, stateful snapshots, claimed sub-90 ms start. **Star count is not a security audit** — would need independent review before we route customer code through it |
| **Docker Sandboxes** | microVM under a Docker-native UX | Closest to our current `DockerRuntime` mental model; likely the lowest-friction upgrade path for self-hosted users |
| **Container Use** (Dagger) | Container + git branch per agent, exposed via MCP | Per-agent container with command history in plain git. Weaker boundary than microVM but MCP-native |
| **AgentTier** | Kubernetes Pod | Overlaps `KubernetesRuntime`. A pod alone is not a strong boundary — same caveat applies to us |
| **Kubernetes Agent Sandbox** (Mar 2026) | Pod/CRI behind a CRD | **Watch item.** If the sandbox becomes a standard platform object, our K8s runtime should target the CRD instead of hand-rolled Pod + Service + IngressRoute |
| **Anthropic sandbox-runtime** | macOS Seatbelt / Linux bubblewrap | Built into Claude Code. Stronger than a worktree, weaker than a VM — sets the baseline users already have for free |

---

### Tier 4 — Local dispatchers and ADEs: adjacent, and being squeezed

Local TUI/desktop tools over git worktrees: **Orca** (MIT, ~27.4k★ by Jul 2026, 30+
CLI agents, desktop + mobile, terminal splits/editor/browser/diff review, GitHub and
Linear, SSH environments), **cmux** (viral early 2026), **Superset**
(source-available, not OSI), **Sculptor**, **agent-deck** (groups, forks, cost
tracking, phone control), **Claude Squad** (tmux + worktree archetype), **Warp** (2.0
repositioned as an ADE), **Crystal / Nimbalyst**, **Coder mux** (the only one with
real remote-workspace infrastructure, tied to the Coder ecosystem).

Overlap with Aixle is limited to session UI. Two signals matter more than the feature
lists:

1. **Vibe Kanban shut down on 10 Apr 2026** with ~27k★ and thousands of daily users —
   Bloop found no viable business model; the project continued as community Apache-2.0.
   The workspace layer attracts attention and does not monetize on its own.
2. **Vendors are absorbing the layer** — Claude Code sub-agents, Codex worktrees,
   GitHub Agent HQ. Differentiation at layer 3 has a short half-life.

**Implication for us:** the Board is table stakes, not the moat. The moat is layers
4–5 plus tenancy and accounting.

---

### JTBD × Competitor Matrix

| JTBD | GitHub Copilot | Cursor | Devin | Codegen | Overcut | OpenHands | Omnigent | **Aixle** |
|------|---------------|--------|-------|---------|---------|-----------|----------|---------|
| Agent coordination within a team | ⚠️ (Agent HQ) | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| Repeatable workflows (one button for the team) | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ | ⚠️ | ✅ |
| Audit log + cost tracking | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ⚠️ | ✅ | ✅ |
| Quick start (15 minutes) | ✅ | ✅ | ⚠️ | ✅ | ❌ | ✅ | ⚠️ | ⚠️ |
| Standardization of AI processes for the team | ❌ | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ |
| Custom AI agents with container isolation | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| PM/non-tech visibility into progress | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Managed agent credential onboarding | ❌ | ❌ | n/a | ❌ | ❌ | ⚠️ (Cloud only) | ❌ | ✅ |
| Durable execution (crash/restart safe) | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ❌ | ❌ | ✅ |

**Conclusion (revised).** The April claim — "Aixle is the only player covering the
full team-level JTBD set" — no longer holds. **OpenHands and Omnigent together cover
six of the nine rows**, both under permissive OSS licences, one of them funded by
Databricks. What is still uniquely ours:

- **PM/non-tech surface** — workflow engine with steps, versioned assets, approval
  gates. Nobody in the set builds for a non-engineer.
- **Managed credential onboarding across 4 agent CLIs** — nobody in the article's
  entire six-layer survey solves this; all of them assume keys already exist.
  OpenHands Cloud injecting a subscription at session start is the nearest thing.
- **Durable execution** — Temporal-backed runs that survive worker restarts.
- **Multi-tenancy + usage-based accounting** — Company→Project scoping, OTLP/MITM
  usage capture for billing.

Weak spots: time to first value (JTBD 4), and no ACP support while ACP becomes the
interop standard for exactly the agent-agnosticism we sell.

---

### Open follow-ups from this revision

Not yet resolved — these change downstream sections and are deliberately left open
rather than answered inside a competitor section:

1. **ACP support.** Decide whether to implement ACP alongside MCP. OpenHands uses it to
   claim any-agent support with no per-agent adapter; we pay adapter cost per agent
   (`ClaudeCodeAdapter`, `CursorCliAdapter`, `CodexAdapter`, `GeminiCliAdapter`).
2. **Buy vs build at layer 5.** Evaluate E2B / Daytona / Docker Sandboxes as a managed
   runtime behind the existing Runtime interface, and whether `KubernetesRuntime`
   should target the Kubernetes Agent Sandbox CRD.
3. **Outer-loop feedback.** Agent Orchestrator's PR/CI→agent loop is a capability our
   workflow engine lacks. In or out of the 12-month roadmap?
4. **Re-derive §§ 6–8** against this competitive picture — the roadmap still assumes
   container isolation and multi-agent support are differentiators.

---

## 4. The product today (as-is)

### What exists now (from the codebase)

Aixle is a web platform with:
- **Board** — Kanban with Column Workflow Bindings: a task lands in a column → a workflow starts automatically
- **Workflows** — DAG graph of steps with dependencies, retry, approval gates, input/output assets
- **Agents** — LLM personas, supporting `claude_code`, `cursor_cli`, `codex`, `gemini_cli`
- **Terminal Sessions** — containerized agent execution with isolation
- **MCP Servers** — internal integration with `aixle-mcp-server`, support for external MCP
- **Aixle Builder** — AI assistant for creating workflows through dialogue (meta_tools)
- **Usage Statistics** — tracking of tokens + cost_cents at the terminal session level
- **Temporal** — orchestration of long-running workflow executions
- **GitHub / GitLab** — webhook integrations, task waits on CI/CD
- **Presets**: `simple_kanban`, `dev_team`, `full_sdlc`

### Strengths

- The only web platform with container-native AI agent execution + Kanban board in a single product
- Temporal under the hood — enterprise-grade reliability for workflow execution
- DAG dependencies between steps: a rare capability for running agents in parallel
- Built-in cost tracking at the session level — a direct answer to the enterprise requirement for visibility
- Support for multiple AI runtimes (claude_code, codex, cursor_cli, gemini_cli) — vendor-agnostic
- Aixle Builder lowers the barrier to creating the first workflow through dialogue

### Observations from the product context [Primary data]

| Observation | Diagnosis |
|-----------|---------|
| "It is hard to please all customers — the scope of application is very broad" | No clear ICP. The product tries to be for the solo-dev, the enterprise team, and PMs alike. The bet is too broad → too few "aha moments" for each segment. |
| "It is hard for those already accustomed to Claude Code and similar tools to switch" | High switching costs. Claude Code is a personal tool; Aixle requires team-level setup. There is no bridge for the solo-to-team transition. |
| Implicit: the product works, but conversion and retention are open questions | Monetization is not described in the code (no Stripe). Usage tracking exists → billing logic is likely manual or in development. |

### Critical product risks right now

| Risk | Level | Recommendation |
|------|---------|--------------|
| Lack of a clear ICP → blurry onboarding | High | Pick 1 primary persona (Engineering Lead, team of 5–15) |
| High time to first value | High | Out-of-the-box workflow templates for top use cases |
| Lack of public monetization | Medium | Launch a pricing page and trial before Q3 2026 |
| Broad scope of application without a narrative | High | Formulate 1 positioning statement |

---

## 5. Vision and bet

### Main thesis

> **Aixle is the first team orchestrator of AI agents with kanban control:**
> you place a task on the Board, the agent executes it in an isolated container, the whole team sees the progress, log, and cost — without a single open terminal.

This is not yet another coding assistant. It is **a level higher** — managing agents as a team's work process.

---

### Why it works: market evidence

1. **Coordination is an unclosed gap.** Cursor ($50B) and Claude Code solve the individual job. Neither of them has a Board, workflow templates, or a team-level audit log. (Competitor websites + financial reports, Mar–Apr 2026)

2. **Enterprise pays for controllability.** Devin earns $73M ARR precisely from enterprise (Goldman, Citi, Cisco) — not because the agent is "smart," but because it has accountability. (Cognition Labs blog, 2026)

3. **Temporal is a rare technical advantage.** Fewer than 5% of AI platforms have production-grade workflow orchestration under the hood. This is an architectural moat that is hard to copy quickly. **Confirmed July 2026:** across the six-layer infrastructure survey, no player — including OpenHands, Omnigent, and Gas Town — runs a durable execution engine. State is kept in a database, in Git, or in process memory.

6. **The layers below and beside us are commoditizing (July 2026).** Agent-agnostic session management (OpenHands), the unified agent API with policies and budgets (Omnigent), and microVM sandboxing (E2B, Daytona, Docker Sandboxes) are all now available free or as a metered utility. This cuts both ways: our runtime work is less defensible, and our build cost drops if we adopt instead of rebuild. The bet must sit above them — process, assets, accountability, credentials — not in the container plumbing.

4. **Market growth creates a tailwind.** AI agent orchestration: $5.8B in 2025 → $35B by 2030. This is not a niche market — it is a category. (MarketIntelo, Apr 2026)

5. **MCP as a standard creates a network effect.** Aixle already supports MCP. As MCP becomes an industry standard (Anthropic, 2024–2026), a platform with native MCP integration gets a free flywheel through the ecosystem.

---

### Differentiator

Updated July 2026 to include the two players that share our layers (see
[Tier 2a](#tier-2--direct-competitors)).

| Parameter | Cursor / Claude Code | Devin | Codegen | OpenHands | Omnigent | **Aixle** |
|---------|---------------------|-------|---------|-----------|----------|---------|
| Team board + workflow | ❌ | ❌ | ⚠️ (external) | ⚠️ (automations) | ❌ | ✅ |
| Container isolation | ⚠️ (sandbox-runtime) | ✅ | ❌ | ✅ | ✅ | ✅ |
| Multi-agent (claude, codex, cursor, gemini) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Cost tracking per session | ❌ | ⚠️ | ❌ | ⚠️ | ✅ (budgets) | ✅ |
| DAG workflow dependencies | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| MCP-native | ⚠️ | ❌ | ❌ | ✅ | ✅ | ✅ |
| ACP support | ⚠️ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Durable execution (Temporal-class) | ❌ | ⚠️ | ❌ | ❌ | ❌ | ✅ |
| Managed agent OAuth onboarding | ❌ | n/a | ❌ | ⚠️ (Cloud) | ❌ | ✅ |
| Multi-tenant SaaS + billing | n/a | ✅ | ⚠️ | ⚠️ (Cloud) | ❌ | ✅ |
| Versioned assets / approval gates | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

Two rows are the real defensible ones — **durable execution** and **managed agent
OAuth onboarding** — plus the workflow/asset layer above them. Container isolation and
multi-agent support are no longer differentiators: OpenHands and Omnigent both ship
them, free.

---

## 6. Strategic focuses

### Stage 1 (0–3 months): Close bleeding wounds + ICP

**1.1 — Choosing the ICP and focus**
Lock in the primary persona: Engineering Lead / Staff Engineer at a 5–30 person company, US, actively uses Claude Code or Cursor, willing to pay $50–200/mo for team-level coordination.
*Expected effect: 40% reduction in sales cycle through point messaging*

**1.2 — Out-of-the-box workflow templates**
5 ready-made workflows for top use cases with no setup: (1) Code Review Agent, (2) Feature Spec → PR, (3) Bug Triage, (4) Test Generation, (5) Security Scan. Each launches in 1 click.
*Expected effect: time to first value < 15 minutes vs the current 60+*

**1.3 — Onboarding redesign**
A "5 steps to your first running agent" scenario: create a project → choose a workflow template → connect a GitHub repo → launch. Without reading the documentation.
*Benchmark: Cursor onboarding — first autocomplete in 3 min. Codegen — "5-minute setup"*

**1.4 — Pricing page and first public monetization**
Publish pricing: Free tier (1 workflow, 1 user), Pro ($49/mo, 5 users, 10 workflows), Team ($149/mo, 20 users, unlimited). Add a 14-day trial.
*Benchmark: a 17-32 day trial converts 70% better (RevenueCat SOSA 2026)*

---

### Stage 2 (3-9 mo): Retention + AI layer

**2.1 — Workflow Marketplace**
Community-contributed templates + a curated library from Palad AI. Users publish and fork workflows. Flywheel: more templates -> more new users who arrive via a template -> they stay.
*Expected impact: +30% activation rate through discovery*

**2.2 — Team Analytics Dashboard**
Aggregated dashboard: how many workflow runs over a period, which agents were used, cost, success rate by step, bottlenecks. For the CTO persona, the main argument for renewal.
*Benchmark: Devin earns enterprise revenue precisely on the visibility/reporting layer*

**2.3 - Agent Collaboration (parallel steps)**
Visual interface for building DAG workflows with parallel agents - "run 3 agents simultaneously on different branches." Simplify via a drag-and-drop builder on top of the current DAG.
*Impact: closes JTBD 1 at 100%*

**2.4 — Notification & Status layer**
Slack + Email: "Agent Alex finished Code Review - 3 comments need your attention." Without Slack integration, the PM persona (Priya) does not become an active user.

**2.5 — GitHub PR integration deepening**
Automatic pull request with workflow results, link to the workflow run as a CI check. The agent worked - the PR arrived - the developer reviews. A closed loop without context switching.

---

### Stage 3 (9-12 mo): Scale and differentiation

**3.1 — Enterprise tier + SSO / Audit logs**
SOC2-ready audit logs, SAML SSO, custom data retention. For companies of 50+ people. Pricing: $500-2000/mo.
*Benchmark: Devin Team plan $500/mo flat - the precedent exists*

**3.2 - Aixle Builder v2 - Workflow from a task description**
"We have a code review process - describe it in Russian/English -> Aixle Builder generates the workflow." Lower the barrier to creating the first workflow to zero.

**3.3 — Agent Skills Marketplace**
Reusable Skills (like npm packages for agents): knowledge base, coding guidelines, security policies. Public registry + private company skills. The first network effect at the content level.

**3.4 — API + Headless mode**
REST / webhook API for triggering workflows from CI/CD pipelines (GitHub Actions, GitLab CI). Platform engineers (Jordan) integrate Aixle as a step in an existing pipeline.

---

## 7. 12-month roadmap

### Phase 1 - Foundation (mo 1-3)

| Period | Task | Description | KPI target | Benchmark |
|--------|--------|---------|---------|---------|
| Mo 1 | ICP Definition | Lock down the primary persona, create a sales playbook, update the site and messaging | - | - |
| Mo 1-2 | 5 Workflow Templates | Code Review, Feature Spec->PR, Bug Triage, Test Gen, Security Scan - out of the box | Time to first workflow < 15 min | Codegen "5-min setup" |
| Mo 2 | Onboarding Redesign | 5-step onboarding up to the first agent run | Activation rate D1 > 40% | Cursor D1 activation ~60% |
| Mo 2-3 | Pricing + Trial | Free / Pro $49 / Team $149, 14-day trial | Trial -> Paid > 15% | RevenueCat SOSA 2026: 10.7% median |
| Mo 3 | Website & Positioning | New site with clear positioning: "Team AI workflow orchestration" | - | - |

### Phase 2 - Growth (mo 4-9)

| Period | Task | Description | KPI target | Benchmark |
|--------|--------|---------|---------|---------|
| Mo 4-5 | Workflow Marketplace | Public template library, fork & customize | +30% activation via templates | n8n workflow library |
| Mo 4-6 | Team Analytics | Cost tracking dashboard, agent performance, workflow success rate | Retention D30 > 45% | SaaS median D30 ~35% |
| Mo 5-6 | Parallel Agent DAG UI | Visual drag-and-drop for parallel steps | NPS +10 from Engineering Lead | - |
| Mo 6-7 | Slack Integration | Notifications about agent status in Slack | DAU/MAU ratio > 30% | B2B SaaS median 25% |
| Mo 7-9 | GitHub PR deep integration | Auto-PR from workflow run, CI check status | - | - |
| Mo 8-9 | Referral / PLG mechanics | "Invite teammate -> +5 workflow runs" | K-factor > 0.3 | - |

### Phase 3 - Scale (mo 10-12)

| Period | Task | Description | KPI target | Benchmark |
|--------|--------|---------|---------|---------|
| Mo 10-11 | Enterprise Tier | SSO, audit logs, custom quotas, $500+/mo | 5 enterprise customers | Devin Team $500/mo |
| Mo 10-11 | Aixle Builder v2 | Workflow from a text description | - | - |
| Mo 11-12 | Skills Marketplace | Public registry of skills for agents | - | - |
| Mo 12 | API / Headless Mode | Trigger workflows from GitHub Actions / GitLab CI | - | - |

---

## 8. Metrics and success

### Metrics table

| Metric | AS-IS (estimate) | Benchmark | Target 12 mo | Benchmark source |
|---------|--------------|----------|-------------|-------------------|
| Trial -> Paid conversion | Unknown | 10.7% (D35 hard paywall) | **15%** | RevenueCat SOSA 2026 |
| D7 retention | Unknown | 25-30% (B2B SaaS) | **35%** | Mixpanel Industry Benchmarks 2025 |
| D30 retention | Unknown | 15-20% (B2B SaaS) | **40%** | Mixpanel Industry Benchmarks 2025 |
| Time to first workflow run | ~60+ min | 5 min (Codegen) | **< 15 min** | Codegen site, 2026 |
| DAU/MAU ratio | Unknown | 25% (B2B SaaS) | **30%** | Amplitude B2B Benchmarks 2025 |
| ARPU (Pro+Team users) | $0 (no public monetization) | $49-500/mo | **$80/mo** | Cursor Pro $20, Devin Core $20+ |
| Monthly churn (Pro tier) | — | 3–5% (B2B SaaS) | **< 4%** | ChartMogul SaaS Benchmarks 2025 |
| NPS | Unknown | 30-40 (B2B SaaS) | **40** | Gainsight NPS Benchmarks 2025 |
| Workflow runs per active user/week | Unknown | - | **5+** | Internal KPI |

---

### Risks and countermeasures

| Risk | Probability | Impact | Countermeasure |
|------|------------|---------|-----------|
| Cursor/GitHub Copilot add team orchestration | High (12-18 mo) | High | Deepen MCP + Container isolation + Temporal moat; move toward enterprise faster |
| Blurry ICP -> low conversion | High | High | Lock down the ICP by mo 2, do not expand it until M12 |
| High time to value -> churn during onboarding | High | High | Workflow templates + redesigned onboarding as a mo 1-2 priority |
| AI cost (tokens) grows -> margin squeeze | Medium | Medium | Usage-based billing with a buffer; cost tracking already exists in the code |
| Vendor lock-in fear (Claude-only?) | Medium | Medium | Actively communicate multi-runtime support (claude, codex, gemini, cursor) |
| Lack of public case studies -> hard enterprise sales | High | High | Reference Customers program by mo 6; case studies with the Engineering Lead persona |

---

### All document sources

**Market data:**
- MarketIntelo - AI Agent Orchestration Platform Market Research Report 2034, Apr 2026
- Intelevore Research - Global AI Agent Orchestration Software Market Forecast, Apr 2026
- Deloitte Insights — AI agent orchestration (Tech Predictions 2026), 2026
- virtualassistantva.com — AI Workflow Orchestration $8.5B Multi-Agent 2026, 2026

**Competitive data:**
- SiliconAngle - Cognition raises at $25B valuation, Apr 2026
- SaaS Sentinel - Cognition $25B Funding Round, Apr 2026
- Cognition Labs Blog — Devin 2025 Annual Performance Review, 2026
- Cognition Labs Blog - Devin 2.0, Apr 2025
- SitePoint — Claude Code vs Cursor vs Copilot 2026, 2026
- ToolChase — AI Coding Agents Compared 2026, 2026
- Latchpine — AI Agents Compared 2026, 2026
- Overcut.ai - site, 2026; Codegen.ai - site, 2026; Forge-x.dev - site, 2026; Getatum.com - site, 2026
- n8n.io — Medium/n8n comparison vs Make 2026, 2026

**Competitive data — July 2026 revision of § 3:**
- Habr #1063558 — "Army in the terminal" (Russian-language post), six-layer infrastructure retrospective, Jul 2026 — the survey that triggered this revision
- Databricks Blog — "Introducing Omnigent: A Meta-Harness to Combine, Control and Share Your Agents", 13 Jun 2026
- MarkTechPost — Databricks open-sources Omnigent (agent coverage, Apache-2.0), 13 Jun 2026
- openhands.dev/blog — "Controlling any Coding Agent with the OpenHands Agent Canvas and SDK" (ACP, cloud backend, auth injection), 18 Jun 2026
- github.com/OpenHands/OpenHands + OpenHands/agent-canvas (star counts, architecture), read Jul 2026
- vibekanban.com/blog/shutdown — Bloop shutdown notice, 10 Apr 2026
- onorca.dev + third-party Orca reviews (MIT licence, ~27.4k★, 30+ CLI agents), Jul 2026
- Public reporting on Conductor's $22M Series A (YC, macOS, worktree isolation), Mar 2026
- e2b.dev, daytona.io — sandbox-as-a-service capability and isolation model, read Jul 2026

**Monetization and trial:**
- RevenueCat State of Subscription Apps (SOSA) 2026
- ChartMogul SaaS Benchmarks 2025
- Mixpanel Industry Benchmarks 2025
- Amplitude B2B Benchmarks 2025

**Primary data:**
- Palad AI codebase: `palad-app-develop/references/aixle-system-reference.md` (read Apr 2026)
- Palad AI codebase: `palad-app-develop/config/settings.yml`, `routes.rb`, `package.json` (read Apr 2026)
- Product observations: provided in the request (Apr 2026)

---

## * CustDev and observations

*This section is built from primary data — personal testing, user interviews, App Store / G2 / Reddit reviews.*

### Observations from the product context [Primary data]

| Observation | Diagnosis | Fix priority |
|-----------|---------|----------------|
| "Hard to please all customers — the scope is very broad" | Product without an ICP → generic onboarding → blurred aha moment | Phase 1: ICP + messaging |
| "Hard to switch for those used to Claude Code" | Switching cost is too high. No bridge message: "You already have Claude Code — Aixle is the next level for your team" | Phase 1: Positioning + onboarding |

### Placeholder: Trust funnel

**Step 1 — Site / Landing**
Current diagnosis: Positioning is unclear. No answer to the question "who is this for and why should I switch from Claude Code".
Trust: **critical to improve**

**Step 2 — Onboarding**
Current diagnosis: requires configuring agents, a repository, and workflows before anything works.
Trust: **medium** (Aixle Builder exists, but it is not obvious from the start)

**Step 3 — First workflow run**
Current diagnosis: if it succeeds — high satisfaction. If something breaks — no recovery path.
Trust: **high on success**

**Step 4 — Team adoption**
Current diagnosis: no explicit team invite flow and no explanation of the value for the PM persona.
Trust: **medium**

**Step 5 — Payment**
Current diagnosis: no public pricing → no trial → no conversion.
Trust: **critical to improve**

---

## ★★ AI Custdev

### Synthetic interviews with personas

#### Interview with Alex (Engineering Lead) [AI simulation]

| Question | Alex's answer | Diagnosis |
|--------|------------|---------|
| What does your day look like when you manage AI agents on the team? | "I open three terminals, run claude code on one task, cursor on another, and then periodically check what's happening. Sometimes one of them hangs and I don't know — is it thinking or did it crash." | Pain: no single place to monitor; no "alive/crashed" status |
| What annoys you the most? | "When an agent silently fails a task, and I only find out about it an hour later. And then I explain to the team why we lost time." | Pain: no alerts on failure + no transparency for the team |
| What do you use now? Why this specifically? | "Cursor for IDE tasks, Claude Code for the terminal. I tried Devin — expensive and unpredictable on our stack." | Insight: the user is ready for a new tool, but Devin missed on the price/control ratio |
| If it worked perfectly — what would it look like? | "I open one dashboard, I see 5 running agents on different tasks, each with a status, I can hit 'pause' or 'approve' if needed. Like GitHub Actions but for agents with a Board." | Job: a single dashboard + control plane for agents. A direct hit for Aixle |
| How much are you willing to pay? | "For a team tool — $100–200/mo. If it really saves 5+ hours a week — $300 is no question." | WTP confirms Pro/Team pricing |

---

#### Interview with Priya (Product Manager) [AI simulation]

| Question | Priya's answer | Diagnosis |
|--------|-----------|---------|
| How do you currently track a task's progress when an agent is running it? | "I don't. I put a task in Jira, the developer says 'I'll run an agent', and then silence until the PR. Sometimes I wait 3 days." | Pain: no visibility for non-tech users |
| What annoys you the most? | "Not knowing when it's done. And not being able to adjust if a requirement changed while the agent was working." | Pain: no interrupt/feedback mechanism for stakeholders |
| What would change if it worked perfectly? | "I would see: 'The agent is working on task X, step 2 of 5, expected in 40 minutes'. Like package tracking." | Job: shipment tracking UX for AI tasks |
| Willing to pay? | "Personally — no, it's a tool for developers. But I would push to buy a team license." | Insight: Priya is a champion, not a buyer. We need to give her a tool to sell the tool upward. |

---

### Testing the hypothesis: "Workflow templates reduce time to value"

**Hypothesis:** We believe that an Engineering Lead spends >30 min creating their first workflow. If we give them 5 ready-made templates — they will run the first workflow in < 15 min. We will know we are right if the D1 activation rate grows from X to 40%.

| Persona | Reaction | Objection | What to change |
|---------|---------|-----------|-------------|
| Alex (Eng Lead) | ✅ Will accept | "The template must work with my stack (TypeScript/Python)" | Add language/framework tags to templates |
| Sarah (Solo Dev) | ✅ Will accept | "I want to fork a template and customize it" | Fork + edit should be 1 click |
| Marcus (CTO) | ⚠️ Neutral | "What matters to me is that it works for my team, not for me" | Team activation flow: "send the template to the team" |
| Jordan (DevOps) | ⚠️ Neutral | "The templates are too generic. Give me YAML/API" | Code-level workflow definition as an alternative to the GUI |
| Priya (PM) | ✅ Will accept | "Is there a template for product spec → code?" | The Feature Spec template should be first |

**Verdict:** the hypothesis works for 3–4/5 personas. The main barrier is customizability. Recommendation: templates + 1-click fork + markdown/YAML export.

---

## A. AI newcomers and fast-growing players

### Fast-growing startups (relevant for positioning)

**Codegen.ai** — «OS for Code Agents»
*Growth:* 1000+ teams (website, 2026). Formula: zero-friction setup (5 minutes) + integration with Linear/Jira as a native feature. Gap: no board of their own, no container isolation, no cost tracking.

**Forge** — Tickets → Merged PRs
*Growth:* Private beta with an active waitlist (website, 2026). Formula: one super-strong job (ticket → PR) + per-step cost estimate. Gap: narrow scope, no team workflows beyond the coding PR.

**Overcut** — Enterprise SDLC Orchestration
*Growth:* No public data. Positioned as enterprise-only. Gap: closed to SMB, no public pricing.

**Atum** — Ideation to Production
*Growth:* Early access (website, 2026). Formula: full SDLC + budget tracking. Gap: immature product, no container execution.

---

### The AI-newcomers' growth formula: 6 patterns

| Pattern | Example | Application to Aixle |
|---------|--------|-------------------|
| **1. One super-strong job** | Forge: ticket→PR | Betting on "launching an agent from the Board" as the primary job |
| **2. Freemium → viral → convert** | Codegen: free trial, team invite | Free tier with team sharing + viral via shared workflows |
| **3. Removing prompts and complexity** | Cursor: you just type | Workflow Builder dialog instead of manual YAML |
| **4. Aggregation of the best models** | Cursor + Claude + GPT | Already in place: claude_code, codex, gemini_cli, cursor_cli |
| **5. Lean team, fast iteration** | All the startups above | Narrow ICP + fast releases |
| **6. Personalization > generic** | — | Templates by niche: TypeScript, Python, Go teams |

---

## B. Two visions

### Vision 1 — Niche Premium Tool: "The best orchestrator for Engineering Teams"

**Positioning:** A specialized B2B tool — "GitHub Actions but for AI agents". Narrow focus: software engineering teams of 5–50 people, US, active users of Claude Code / Cursor.

**Who it's for:** Engineering Lead, Staff Engineer, Platform Team

**Pros:**
- Fast time to product-market fit (no endless scope expansion)
- High ARPU in the niche ($150–300/mo per team)
- Defensible through deep technical integration (Temporal, Container, MCP)
- Realistic acquisition target for Anthropic, GitHub, GitLab

**Risks:**
- Narrow market — ceiling $200–500M ARR
- Large competitors could add orchestration as a feature

**ARPU ceiling:** ~$200/mo per team × 10,000 teams = $24M ARR
**Exit strategy:** Acquisition: GitHub, GitLab, Anthropic, JetBrains

---

### Vision 2 — AI-native PM Platform: "The first project management platform for AI-first teams"

**Concept:** A replacement for Jira/Linear for teams where agents do half the work. Today: Linear + GitHub + Claude Code + Cursor + Notion = 5 different tools. Tomorrow: Aixle = one place where the task is set, the agent executes, the PM sees progress, and the code arrives as a PR.

**Diagram: what's now → what's next**
```
Now:                          In 2 years:
Jira/Linear (tasks)          ┐
GitHub (code + PR)             │
Claude Code (agent)           ├→  Aixle (all in one)
Cursor (agent)                │
Notion (documentation)         │
Slack (notifications)           ┘
```

**Who it's for:** AI-first companies of 10–200 people, Engineering Managers, CTOs, Product Managers

**Unaddressed feature — a blue ocean:** "The PM sets a task in text → Aixle automatically picks an agent → launches the workflow → the PR arrives for review". No competitor has such a closed loop with a non-tech interface.

**Pros:**
- TAM: $15–30B (AI-native Project Management — Jira's $2B ARR as a reference point)
- Sticky: if Aixle is your task tracker, you don't leave
- Network effect: the bigger the team, the more valuable the workflow library

**Risks:**
- Long time to market (18–24 months needed for maturity)
- Competition with Linear, Jira (huge budgets)
- Requires a sales motion and customer success

**ARPU ceiling:** $500–2000/mo per team × enterprise, TAM $30B+
**Defensible moat:** Workflow + Agent + Board locked-in; data flywheel via usage stats

---

### Vision comparison table

| Parameter | Vision 1: Niche Tool | Vision 2: AI-native PM |
|---------|----------------------|----------------------|
| Time to product-market fit | 6–9 months | 18–24 months |
| ARPU | $150–300/mo | $500–2000/mo |
| Retention mechanism | Workflow dependency lock-in | Task tracker + workflow lock-in |
| Virality | An engineer invites the team | PM + Eng + product all in one |
| Moat | Temporal + Container + MCP | Data + workflow + PM lock-in |
| Risk from a large competitor | High (GitHub, Anthropic) | Medium (more niche, longer to build) |
| TAM | $500M–2B | $15–30B |
| Exit / strategy | Acquisition | IPO or strategic partnership |
| Analogy | Vercel in deployment | Notion for AI-first teams |

---

### Recommendation

**Stage 1 (0–6 months) is the same for both visions:** lock in the ICP → template workflows → onboarding → first monetization.

**Betting on Vision 2 is the right call**, because:
1. Vision 1 risks becoming a feature in Cursor/Copilot within 18 months
2. Vision 2 creates platform lock-in via the task tracker — if Aixle has become your Linear, you don't switch
3. The code already has Board, Workflows, Agents, MCP, Usage Stats — Vision 2's architecture is already partly built
4. No one has taken the "PM platform for AI-first teams" position — the window is open right now

**Path:** start with Vision 1 (focus → traction → revenue), build Vision 2's architecture, switch to Vision 2 messaging upon reaching $1M ARR.

---

*Document created: April 2026*
*Next step: conduct 5 live interviews with the Engineering Lead persona to verify JTBD 1 and validate WTP*
