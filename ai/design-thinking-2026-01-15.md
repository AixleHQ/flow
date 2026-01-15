# Design Thinking Session: Cloud AI Agent Platform (Palad)

**Date:** 2026-01-15
**Facilitator:** Artem Petrov
**Design Challenge:** Building a cloud AI agent platform with Cursor-like capabilities, but in the cloud

---

## 🎯 Design Challenge

### Problem Statement

**Context:** Cursor works great with code context — editing, search, navigation. But it is tied to the local machine, which limits usage scenarios for a service company.

**Target State:** A cloud AI agent platform that:
1. Works with any context (code, documents, images) through a cloud file system
2. Allows creating custom agents, prompts, and workflows
3. Reuses existing BMAD agents (analyst, architect, pm, dev, etc.)
4. Integrates with Cursor for exporting tasks and highlighting changes

### Challenge Statement (Refined)

> **How to build a cloud AI agent platform where:**
> 1. Each session gets an isolated file system with the project context
> 2. Agents can edit files, search code, and run commands through tools
> 3. The user interacts through a terminal-like interface in the browser (like BMAD)
> 4. Workflows are configured and stored in the database (BMAD-compatible)
> 5. Upon session completion, content is synced to S3 and objects are created in the database

### Primary Users

- **Primary:** Artem + partner (2 founders, first users)
- **Secondary:** Service company team (70 people, outsourcing/custom development)
- **Future:** Other teams using similar workflows

**Potential:** If the product takes off — fast rollout to 70 people, high rates.

### Target Workflows

1. **Application Replatforming:**
   - Analysis of existing code → contract extraction → routers → domain logic → PRD

2. **Code Generation:**
   - Agents capable of writing code from tasks
   - Results are presented as a PR or highlighted locally in Cursor (with history and changed files)

3. **Brainstorming and product work:**
   - Full BMAD method through the web interface
   - Creating PRD, architecture, user stories

### Three Types of Output Entities

| Type | Storage | Export |
|-----|----------|---------|
| **Assets** | S3 + database record | Files, documents, artifacts |
| **Tasks** | DB | Linear (with priorities, dependencies) |
| **Code** | S3 + Git | PR to GitHub/GitLab or highlighting in Cursor with history |

### Key Constraints

| Aspect | Constraint |
|--------|------------|
| **LLM providers** | Agnostic — model selection like in Cursor (OpenRouter-style) |
| **Budget** | No limits |
| **Technologies** | Rails 8 (web), Python/Temporal (ai-engine), xterm.js for the terminal |
| **File system** | S3 → mounted at session start → sync back on completion |
| **Interface** | Terminal-like (like BMAD/Claude Code) + Kanban for tasks |
| **Workflows** | Stored in the DB, BMAD-compatible format |

### Existing Foundation

You already have a working application:
- **Web:** Rails 8
- **AI Engine:** Python + Temporal + LangGraph + LangChain with agents
- **Integrations:** GitHub, GitLab, Bitbucket
- **Models:** Presets with model selection for different tasks

### Success Criteria (MVP)

1. ✅ Creating and storing workflows in the DB
2. ✅ Running the full BMAD method through the web interface
3. ✅ Assets: file system → S3 → entities in the DB
4. ✅ Tasks: creation with priorities, dependencies → export to Linear
5. ✅ Code: presentation as a PR or highlighting in Cursor with change history
6. ✅ Isolated file system per session with sync on completion

### Critical Architectural Decisions

| Question | MVP Recommendation | Rationale |
|--------|------------------|-------------|
| **Session isolation** | Shared server + directories by session_id | Container per session — overhead not justified for 1-5 users |
| **File system** | Local directories + async sync to S3 | s3fs/goofys are too slow for real-time, sync on session completion |
| **Agent tools** | Custom (file read/write/search) | Start with the minimum, expand as needed |
| **Cursor integration** | MCP server (standard is growing) | Extension API is unstable, MCP — an investment in the future |
| **Linear integration** | API directly | Well documented, simple integration |
| **Terminal UI** | Use a ready-made solution like https://github.com/xtermjs/xterm.js
| **Workflows in DB** | YAML in a jsonb field | Don't create 10 tables at once, iterate |

### Time Traveler Council: Insights

#### Lessons from the past (Past-Artem)
- ✅ Temporal for orchestration — the right choice
- ✅ Splitting Web/AI Engine — scales
- ⚠️ Over-engineering the DB schema — don't repeat this for workflows

#### Current risks (Present-Artem)
- Streaming responses: LangGraph + Temporal + WebSocket — needs working out
- Cursor API is unstable — don't block the MVP on it

#### Future scenarios (Future-Artem)

| Scenario | Probability | Key factor |
|----------|-------------|-----------------|
| **Success** | High if... | Simple onboarding, Linear visibility, MCP for Cursor |
| **Partial** | Medium if... | Complex onboarding, unreliable S3 mount |
| **Failure** | Low if... | Trying to do everything at once, expensive infrastructure |

### Critical Path (minimal path to value)

```
┌─────────────────────────────────────────────────────────────────┐
│ SESSION START                                                   │
│   └─→ Clone files from S3 to local dir (/sessions/{id}/)       │
├─────────────────────────────────────────────────────────────────┤
│ AGENT EXECUTION                                                 │
│   └─→ Agent runs with file tools (read/write/search)           │
│   └─→ User sees output in terminal UI (WebSocket stream)       │
├─────────────────────────────────────────────────────────────────┤
│ SESSION END                                                     │
│   └─→ Sync files back to S3                                    │
│   └─→ Create Asset records in DB                               │
│   └─→ Create Task records → Linear API                         │
│   └─→ Code changes → Git diff → PR or local files for Cursor   │
└─────────────────────────────────────────────────────────────────┘
```

### DO / DON'T for the MVP

| ✅ DO | ❌ DON'T |
|-------|----------|
| Shared server with directories | Container per session |
| Shrine (local → S3 later) | Real-time S3 mount (s3fs/goofys) |
| YAML workflows in jsonb | 10 tables for workflow structure |
| ZIP as a universal input | Complex integrations right away |
| xterm.js for the terminal | Custom terminal from scratch |
| Tasks in DB | Linear integration (defer) |

### First Principles: Practical MVP (2-3 weeks)

**Project context:** ZIP upload (universal primitive)
- Upload ZIP → Extract → Agent workspace
- GitHub/GitLab/Bitbucket integrations will automate fetching the ZIP later

**Storage:** Shrine with a switchable backend
```ruby
# Development: FileSystem
# Production: S3
Shrine.storages = { store: Shrine::Storage::FileSystem.new(...) }
```

**MVP Scope:**
| ✅ In MVP | ❌ Deferred |
|----------|-------------|
| xterm.js terminal | S3 (Shrine local) |
| WebSocket streaming | Linear integration |
| 3-5 agent tools | MCP for Cursor |
| Shrine for files | Presets (hardcode model) |
| Sessions in DB | Workflows in DB (hardcode) |
| Tasks in DB | Team accounts |
| ZIP upload for context | Multi-source integrations |

---

## 👥 EMPATHIZE: Understanding Users

### Key discovery: Two phases — two tools

| Phase | Where it happens | Why | Tool |
|------|----------------|--------|------------|
| **Planning** | ☁️ Cloud | Many people, collaboration, the client | **Palad** |
| **Development** | 💻 Local | One developer, their machine, their code | **Cursor** |

**Insight:** Cursor is good for development, but planning requires inputs from many people, working with the client, brainstorming — this requires a cloud solution.

### User Insights

**The biggest pain in replatforming:** Eliciting requirements
- Brainstorming ideas happens in different places (ChatGPT, documents, calls)
- There is no single platform for collaborative planning

**What works well in Cursor:**
- When there are tasks
- When there are code standards (rules, claude.md)
- When the agent works from a ready tech design

### Key Observations

| Observation | Insight for the product |
|------------|---------------------|
| The client participates in brainstorming | A simple UI is needed, not just a terminal |
| Rules are scattered (cursor/rules, rules-mcp) | Palad as a single hub for rules |
| Tech design → review → implement | Linear as a sync point for human/agent |
| Local agents pull context from the cloud | MCP — the key integration |

### Empathy Map: Artem

| THINKS | FEELS |
|--------|-----------|
| "Eliciting requirements is the hardest part" | Frustration with the planning/dev gap |
| "Inputs from many people are needed" | Confidence that the problem is solvable |
| "Cursor isn't for planning" | Enthusiasm about the workflow idea |
| "Agents should write the tech design BEFORE the code" | High stakes ("will make us rich") |

| DOES | SAYS |
|--------|---------|
| Brainstorms in ChatGPT | "Planning should be in the cloud" |
| Splits work into phases | "Each developer on their own machine" |
| Builds the rules-mcp project | "Agents should argue in Linear" |

### The three roles of Palad

| Role | Description | Users |
|------|----------|--------------|
| **Brainstorm Platform** | Collaborative planning sessions, artifacts | Artem, partner, client |
| **Rules & Prompts Hub** | Storage and distribution via MCP | Local agents (Cursor) |
| **Artifact Factory** | PRD, tasks, documentation | Everyone |

### Interaction architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         PALAD (Cloud)                           │
│  • Workflows (BMAD)           • Rules & Prompts storage         │
│  • Brainstorm sessions        • MCP Server (distributes rules)      │
│  • Artifacts → PRD → Tasks                                      │
└─────────────────────────────────────────────────────────────────┘
                    ↓ MCP                    ↓ Linear API
┌──────────────────────────┐    ┌──────────────────────────────────┐
│   LOCAL AGENT (Cursor)   │    │            LINEAR                │
│  Receives from Palad:    │    │  ready_to_dev                    │
│  - prompts               │    │    ↓                             │
│  - rules                 │    │  Agent writes Tech Design        │
│  - task context          │    │    ↓                             │
│                          │    │  Human review (comments)         │
│  Does:                   │    │    ↓                             │
│  - tech design           │    │  Agent clarifies                 │
│  - implementation        │    │    ↓                             │
└──────────────────────────┘    │  dev_ready → implement           │
                                └──────────────────────────────────┘
```

### Tech Design Conversation Flow (Linear)

```
🤖 Agent: Tech Design v1 (approach, files, risks)
    ↓
👤 Human: Comment ("Why JWT? Consider rate limiting")
    ↓
🤖 Agent: Tech Design v2 (updated based on feedback)
    ↓
👤 Human: "LGTM" → moves to dev_ready
    ↓
🤖 Agent: Implements based on approved design
```

### Rules-MCP integration

| Now (rules-mcp) | In Palad |
|--------------------|---------|
| Text rules | Stored in DB (workspace-level) |
| Distributed as MCP tools | Palad = MCP server |
| Separate project | Built into the platform |

---

_Generated using BMAD Creative Intelligence Suite - Design Thinking Workflow_
