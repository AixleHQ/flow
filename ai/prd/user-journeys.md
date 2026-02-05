# User Journeys

## Journey 1: Developer Misha — Interactive Implementation

**Persona:** Misha, 28 years old, middle developer

**Opening Scene:**
Misha received a task in Linear — "Implement user authentication API". The task contains a link to a tech design (an artifact from the planning phase). In the morning he opens Palad — it is his main work tool, and he rarely leaves the platform's perimeter.

**Rising Action:**
1. Misha sees his tasks from Linear in Palad
2. Selects a task → sees the related artifacts (tech design, PRD)
3. Selects **Interactive mode** — he wants to control every step
4. Starts a session with the agent (Claude Code / Codex)
5. The agent loads the context: codebase, tech design, related files

**Climax:**
Misha communicates with the agent in the terminal, clarifies details, approves changes. He sees how the agent finds the needed code and proposes solutions.

**Resolution:**
- The agent created a PR with the changes
- Misha sees a summary: what was done, which files were changed, the cost of the session
- The PR is ready for review

**Future Feature — PR Review in Cursor:**
> In the future: any PR can be opened in Cursor with the session context — files under review, change history. Solves the problem of reviewing large PRs.

---

## Journey 2: Tech Lead Katya — Planning Workflow

**Persona:** Katya, 35 years old, tech lead on fixed-bid projects

**Opening Scene:**
A new project — replatforming a legacy Java application. Katya opens Palad to start the planning phase.

**Rising Action:**
1. Katya creates a new Project in Palad
2. Loads assets: legacy codebase, documentation, call recordings
3. Selects a ready-made workflow: "Replatforming Planning"
4. Workflow steps:
   - Step 1: Code Analysis → artifact: "Legacy System Analysis"
   - Step 2: Requirements Discovery → artifact: "PRD"
   - Step 3: Architecture Design → artifact: "Tech Design"
   - Step 4: Task Breakdown → artifact: "Tasks" → export to Linear

**Climax:**
Katya selects Interactive mode — going through the steps as in BMAD. The agent asks questions, Katya answers. At each step: review the artifact → approve → next step.

**Resolution:**
- Planning phase complete
- Artifacts saved (PRD, Tech Design, Analysis)
- Tasks created in Linear with priorities
- Team ready for the Implementation phase

---

## Journey 3: Developer Sasha — Non-Interactive Batch

**Persona:** Sasha, 32 years old, senior developer, trusts agents

**Opening Scene:**
Sasha sees 5 tasks in the backlog. All have a tech design, all are clear. He doesn't want to spend time on interactive mode.

**Rising Action:**
1. Sasha selects tasks in Palad
2. For each one selects **Non-interactive mode**
3. Launches — the agents work
4. Goes to a meeting / other tasks

**Climax:**
The agents work autonomously. Each one creates a PR. Sasha receives notifications: "Task X completed, PR ready".

**Resolution:**
- Sasha comes back — sees the ready PRs
- For each one: summary, diff, cost
- Quick review, merge

---

## Journey 4: Admin Andrey — Platform Setup

**Persona:** Andrey, co-founder, configuring the platform

**Opening Scene:**
The team is growing, and Palad needs to be configured for new projects.

**Rising Action:**
1. Creates new Workflows: "Frontend Feature", "API Endpoint", "Bug Fix"
2. Configures Secrets: Platform level (API keys), Project level (GitHub tokens)
3. Creates custom Tools: "Transcribe Meeting", "Read Slack Channel"

**Resolution:**
- Platform configured
- Workflows ready to use
- Tools available in all sessions

---

## Journey 5: PM Lena — Tracking & Costs

**Persona:** Lena, 30 years old, project manager on a fixed-bid

**Opening Scene:**
A fixed-bid project is in full swing. Need to understand the AI spend.

**Rising Action:**
1. Opens the Dashboard in Palad
2. Sees: Total cost, breakdown by workflows/users, sessions history

**Resolution:**
- Sees that we're staying within budget
- Can show the client a transparency report

---

## Journey Requirements Summary

| Journey | Revealed Capabilities |
|---------|----------------------|
| Developer Interactive | Session management, Agent selection, Mode toggle, Artifact viewer |
| Developer Non-Interactive | Async execution, Notifications, PR integration |
| Tech Lead Planning | Workflow selection, Asset upload, Step-by-step execution, Linear export |
| Admin Setup | Workflow builder, Secrets management, Tool creation |
| PM Tracking | Dashboard, Cost analytics, Usage reports |

## Two Global Phases

**Planning Phase:**
- Workflows: Brainstorm → PRD → Architecture → Task Breakdown
- Output: Artifacts + Tasks in Linear
- Mode: Interactive (recommended) / Non-interactive

**Implementation Phase:**
- SDLC: Tech Design → Implementation → QA
- Output: PRs, Code changes
- Mode: Interactive / Non-interactive (user choice)

---
