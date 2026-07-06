# Open Source Aixle: analysis of a strategic option

> **Status:** Research · **Version:** 1.0 · **Date:** April 2026  
> **Context:** Aixle (Palad AI) product strategy · 12-month horizon

---

## Contents

- [Context and the bet](#context-and-the-bet)
- [Market reality](#market-reality)
- [Upsides of opening up](#upsides-of-opening-up)
- [Downsides and risks](#downsides-and-risks)
- [Three strategic options](#three-strategic-options)
- [Key takeaway](#key-takeaway)

---

## Context and the bet

The question "should we open Aixle as open source" is a question about the **business model**, not about the code. The answer depends on exactly what you are opening and why. A vague "let's go open source" kills companies. A precise "we open X, we monetize Y" creates them.

---

## Market reality: what already works

| Product | Model | ARR | What it proves |
|---------|--------|-----|--------------------|
| **n8n** | Open Core (core OSS, cloud paid) | ~$20M ARR | Workflow automation works through an OSS flywheel |
| **Temporal** | Open Core | ~$75M ARR (2025) | Complex orchestration sells as a managed service on top of OSS |
| **GitLab** | Open Core | $600M+ ARR | Enterprise pays for features, not for code |
| **Devin** | Fully proprietary | $73M ARR | Enterprise pays for controllability without code |

**Signal:** two working paths. Open core is proven in the orchestration space (Temporal is a direct precedent). Proprietary is proven on enterprise AI (Devin).

---

## Upsides of opening Aixle as Open Source

### 1. Directly removes Jordan's main objection
Persona 4 (Platform/DevOps) — "skeptical about vendor lock-in". His pain #1: "every new AI tool = a new integration and a new security review". Open source removes this barrier entirely. For this persona, open code = permission to use without a procurement process.

### 2. The community accelerates the Marketplace
The strategy has two key milestones that require content: the Workflow Marketplace (months 4–5) and the Agent Skills Marketplace (months 11–12). Open source turns this into a community flywheel: developers publish templates, integrations, and MCP configurations themselves. n8n built a library of 800+ workflow templates through its community — without that, Palad would have needed several engineer-years.

### 3. MCP positioning as a reference implementation
Anthropic is pushing MCP as a standard (2024–2026). If Aixle is the first open source, MCP-native orchestration platform with Temporal under the hood, that is a "reference implementation" position. An analogy: Kubernetes became the standard in part because it was open. Platform players (Azure, AWS) find it harder to displace a "community standard".

### 4. CTO trust at the code level
Marcus: "If I can't explain to the board what our AI is doing, I'm not shipping it." The enterprise audience, especially fintech/legal, wants to look at the code before signing a contract. Open source is the ultimate limit of transparency: not documentation, but the source itself. For a SOC2-oriented buyer, this is a signal.

### 5. Distribution without a marketing budget
Aixle has no public monetization and probably no budget for paid acquisition. GitHub stars, Hacker News, developer Twitter — a free channel for tools with an open repository. "Used by X developers" in the README is social proof that closes part of the sales cycle.

### 6. Temporal is already open source — architectural consistency
Temporal, under the hood of Aixle, is itself open source. If the orchestration layer is open while Palad builds a closed product on top of it, there is an architectural inconsistency. Opening the core makes Aixle a "good citizen" of the Temporal ecosystem.

---

## Downsides and risks

### 1. Self-hosting kills ARR before it even appears
This is the sharpest risk. The target buyer is an Engineering Lead at a 5–30 person company with a budget of $49–149/mo. If he can stand up Aixle on his own server in 30 minutes, he will do it. Especially Jordan. There is no monetization yet, the trial hasn't launched yet. Opening the code now = handing out a way to avoid payment before the user has gotten used to paying.

**Hard truth:** open source works as lead generation only if you have a compelling cloud offer. Without a ready managed platform, opening up is a giveaway with no checkout counter.

### 2. Competitors get the architectural blueprint
Codegen.ai and Overcut are direct competitors with resources. Temporal integration, DAG execution, container isolation — a technical advantage that is "hard to copy quickly" according to the strategy itself. Open source shortens "quickly" from 12 months to 2–3. Microsoft's GitHub Copilot Team would get the source for analysis the day after publication.

### 3. Maintenance overhead for a small team
PR review, issues, security advisories, documentation for external contributors. n8n has a dedicated DevRel team. For Palad this is at minimum 0.5–1 FTE diverted from the product roadmap. With a closing 18-month window, that's an expensive waste.

### 4. Enterprise compliance sometimes requires a proprietary contract
Goldman Sachs, Citi — these are Devin-type clients. For them, open source means "who bears responsibility if something breaks?". Proprietary SaaS with support and an SLA is what the enterprise pays for. Open core solves this, but requires an enterprise tier with clear contractual terms that don't exist yet.

### 5. Pricing power drops
If the core product is open, it's hard to justify a $149/mo Team plan. You'd have to rethink monetization: pay for hosting, compute, support, enterprise features, rather than for the product itself. That's a different sales model and a different ICP for the enterprise tier.

### 6. Timing: not now
The strategy states: "the window for the unfilled market is narrowing." Open source requires 3–6 months before real community traction appears. That's time that could be spent closing bleeding wounds: ICP, workflow templates, onboarding, pricing. Opening the code without retention is a giveaway with no flywheel.

---

## Three strategic options

### Option A — Open Core *(recommended for consideration)*

**Description:** Open the execution layer (workflow runner, agent runtimes, DAG engine). Close the cloud platform, enterprise features (SSO, audit logs, advanced permissions, multi-tenant), managed hosting.

**Model:** like n8n or Temporal.

| | |
|--|--|
| **Pros** | Jordan can self-host → trust; community contributes to the Marketplace; MCP positioning as a standard; Temporal consistency |
| **Cons** | Requires a ready cloud offer before publication; needs a boundary between OSS and Enterprise features; 0.5 FTE for community |
| **Trigger condition** | Managed cloud platform is ready and stable before publication |

---

### Option B — Source Available / Business Source License (BSL)

**Description:** The code is visible and auditable, but commercial self-hosting is restricted by the license. Used by HashiCorp (Terraform→BSL 2023), Sentry, CockroachDB.

| | |
|--|--|
| **Pros** | Transparency for CTO/security review; competitors can't fork and monetize; preserves pricing power |
| **Cons** | The developer community perceives BSL as "not real open source"; less community contribution |
| **Trigger condition** | The primary audience is enterprise (the Devin path), not community |

---

### Option C — Fully Proprietary + Partial Openness

**Description:** A closed product, but open peripheral components: CLI, SDK, MCP server, workflow specs documentation. Like GitHub Actions with open action templates but a closed core.

| | |
|--|--|
| **Pros** | Retains full control; a community around the SDK and MCP integrations; fast iteration without PR review |
| **Cons** | Doesn't address Jordan's objection about vendor lock-in; weaker as positioning against platform players |
| **Trigger condition** | PLG growth via cloud trial, not via OSS distribution |

---

## Key takeaway

**Opening up now is risky.** There is one reason: there is no ready monetized cloud platform that extracts value from OSS distribution. Without a checkout counter, open source is a marketing expense with no conversion.

### Recommended sequence

| Stage | Action |
|------|----------|
| Months 1–3 (per strategy) | Pricing page, trial, stable cloud platform |
| In parallel | Open the CLI / SDK / MCP server as "partial openness" for Jordan |
| After D30 retention > 40% | Consider Open Core to accelerate the Marketplace flywheel |

### A question to answer honestly before deciding

Does the team have the resources for managed hosting and community management simultaneously with the current roadmap? If not, opening the code without the infrastructure to support it creates reputational risk, not opportunity.
