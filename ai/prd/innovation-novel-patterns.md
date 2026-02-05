# Innovation & Novel Patterns

## Detected Innovation Areas

**Core Innovation:** Centralization and orchestration of AI agents — not the agents themselves (they already exist locally), but everything around them:

| Innovation | Description |
|------------|-------------|
| **Global Workflows** | Sharing workflows across the team, versioning, reuse |
| **Agent Orchestration** | A single platform for different agents (Claude Code, Codex, Gemini CLI, Cursor CLI) |
| **Shared Prompts & Settings** | Centralized storage of prompts, settings, secrets |
| **Billing & Analytics** | Transparency of costs across all agents and workflows |
| **MITM Billing Approach** | An innovative approach to tracking without modifying the agents |

## Assumptions Being Challenged

| Assumption | Challenge |
|------------|-----------|
| "Coding agents must be local" | A cloud platform with the same agents |
| "Can't share workflows across the team" | Centralized storage and reuse |
| "Everyone configures agents themselves" | Shared settings, prompts, tools at the company level |
| "Can't accurately track CLI agent costs" | MITM Proxy solves this problem |

## Market Context & Competitive Landscape

| Competitor | What They Do | Palad Differentiation |
|------------|--------------|----------------------|
| **Cursor** | Local IDE with AI | Palad = cloud orchestration layer |
| **Replit Agents** | Cloud coding | Palad = agent-agnostic, workflow-focused |
| **GitHub Copilot Workspace** | Cloud AI coding | Palad = BMAD-style workflows, multi-agent |
| **n8n / Zapier** | Workflow automation | Palad = AI agents as workflow steps |

**Unique Position:** Palad is not just another AI coding tool, but an **orchestration layer** for existing agents with workflows, sharing, and billing.

## Validation Approach

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Daily Active Usage** | Team uses it as the primary tool | DAU/WAU ratio > 0.6 |
| **Fixed-bid Success** | Projects stay within budget | % of projects on-budget |
| **Workflow Adoption** | Workflows are reused | # workflow runs / # unique workflows |
| **Agent Coverage** | MITM works with all 4 agents | 4/4 agents supported |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **MITM doesn't work with agent X** | Fallback: log parsing, wrapper scripts, provider API usage reports |
| **Agents update breaks integration** | Version pinning, integration tests, quick response team |
| **Users prefer local tools** | Seamless experience, clear value (sharing, billing), Cursor integration via MCP |

---
