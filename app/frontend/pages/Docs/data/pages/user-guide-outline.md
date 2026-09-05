# Aixle Flow User Guide — Outline

> Deliverable for issue #550. This is the outline of the end-user product guide —
> the skeleton a writer expands into full chapters. It follows the product
> sidebar, uses the names a person sees on screen, and stays at product level:
> no architecture, no APIs, no configuration, no file paths.

**Audience.** People who will run work in Aixle Flow: engineering leads,
developers, and operators. Assume they know Git and task boards. Do not assume
they know how agents, containers, or orchestration work.

**Rules for the writer.**

- Every section answers four questions: *what this is · when to use it ·
  what the person does · what they see afterwards.*
- Use the names from the product UI, not internal engineering names
  (see [Terminology notes](#terminology-notes) at the end).
- The operator-level documentation — the [User Guide overview](/docs/user-guide)
  and the pages under it — is written for people installing and operating Flow:
  it is too technical for this guide. Do not reuse its structure or copy; link
  to it only where a reader needs the operator-level detail.
- Every area named in the
  [changelog product-area snapshot](/docs/changelog-product-areas) has a chapter
  here. If a release adds an area, add the chapter in the same change.

---

## 1. What Aixle Flow is

Open with the loop, not a feature list.

- **What it is.** The team layer above personal AI coding agents — Claude Code,
  Cursor CLI, Codex, Gemini CLI, and Grok. Not a personal chat with an agent:
  team control of AI coding work.
- **The loop.** A person moves a card on the board into a column that is bound
  to a workflow. Agents start working. When the run finishes, status, files,
  and cost come back to the board. The team sees what is running, what it
  produced, and what it cost — without anyone opening a terminal.
- **The three levels.** A **company** is the shared workspace. Inside it, each
  **project** has a board and its own resources. Your **profile** holds what is
  personal: your agent credentials and your usage.
- One diagram: board → workflow → agent → results back to the board.

## 2. Your first session

The reader goes from an invite email to their first open project.

- **Getting in.** Accept an invitation or sign in. First-run onboarding walks
  through role, language, and connecting an agent (the agent step is skipped
  for viewer-only users).
- **Connect an agent.** During onboarding — or any time later in **Profile** —
  connect the account of the agent product you already use (Claude Code,
  Cursor CLI, Codex, Gemini CLI, or Grok). Connecting happens in a terminal
  embedded in the page: the product starts a session, you complete the
  runtime's own login in it, and the credential is stored for you. Nothing can
  run on your behalf until this is done — say this plainly and early.
- **Your Profile.** Three tabs: **Account** (agent credentials and personal
  settings), **Usage** (your own sessions, tokens, spend, and any limits that
  apply to you), and **MCP** (personal access, so an agent you run outside
  Aixle — your own Claude Code, for example — can reach your Aixle projects).
- **Find your work.** Open **Projects**, pick a project, land on **Overview**.
- **More than one company?** The workspace switcher moves you between
  companies; each company has its own projects, members, and analytics.
- *Afterwards:* you are inside a project, an agent is connected, and the board
  is one click away.

## 3. The main loop

A single guided walkthrough, before any reference material. Everything later in
the guide hangs off this chapter.

1. Open **Tasks** and create a card (or pick one up from the backlog).
2. Move the card into a column bound to a workflow — the workflow starts
   automatically, or from a button if the column is set to manual.
3. Watch progress in **Sessions & Runs**: live status, the agent's terminal as
   it works, cost accumulating.
4. Review what came back: files in **Assets**, results and comments on the
   card.
5. Move the card forward — or send it back with a comment and run again.

- *Afterwards:* the reader has seen the whole product once, end to end.

## 4. Overview

- **What it is.** The project's home page: recent activity, how tasks are
  distributed across the board, workflow runs, sessions launched, success rate,
  and total spend.
- **When to use it.** The daily "what is this project doing right now, and what
  is it costing" check — before drilling into a specific run.
- **What you do.** Read the tiles; follow one into Tasks, Sessions & Runs, or
  Analytics.
- *Afterwards:* the reader knows where the numbers on this page come from and
  which screen answers the next question.

## 5. Tasks — the board

- **What it is.** The project's board: columns, cards, subtasks, comments,
  attachments.
- **When to use it.** This is where work enters the system and where results
  land; most people live here.
- **What you do.** Create and move cards; comment; attach files; bind a column
  to a workflow so that entering the column starts it (automatically or from a
  button).
- **Board templates.** A new project's board starts empty; pick a template —
  **Simple Kanban** (Backlog / In Progress / Done), **Dev Team** (a
  seven-column engineering flow), or **Full SDLC** (the long form) — and
  customize columns later.
- **Reading a card at a glance.** A card carries chips for its runs and for any
  checks it is waiting on (see [Triggers & gates](#7-triggers-gates)).
- *Afterwards:* cards carry their own history — comments, attachments, runs,
  and activity.

## 6. Workflows

- **What it is.** A named process made of ordered **steps**; each step is one
  agent session doing one job.
- **When to use it.** Whenever the same kind of work should run the same way
  every time.
- **What you do.** Create a workflow; add steps with instructions and an
  assigned agent; set what each step depends on (independent steps run in
  parallel); choose what happens on failure (fail, retry, or skip); mark where
  a person must approve before the run continues. Publish it, duplicate it, or
  copy a ready-made one from the **Workflow Catalog**.
- *Afterwards:* the workflow appears as an option when binding columns, and
  every run of it is tracked.

## 7. Triggers & gates

Two halves of the same question: what starts a run, and what holds one up.

- **What it is.** **Triggers** are the ways a workflow begins: a task enters a
  bound column, someone runs it by hand, a schedule fires, a Slack message
  matches, or an external system posts to an incoming webhook. **Gates** are
  checks a card waits on — typically CI — before work moves on.
- **When to use it.** Triggers: whenever a process should start without anyone
  remembering to press a button. Gates: whenever "the tests must be green"
  belongs in the process rather than in someone's head.
- **What you do.** Add a trigger to a workflow and pick its kind; for a column
  trigger, choose Auto or Manual. Watch a gate on the card: it reads
  **waiting** while CI runs, then **passed**, **failed**, or **stale** when CI
  never reported at all.
- *Afterwards:* work starts on its own, and a card that is blocked says what it
  is blocked on instead of silently sitting still.

## 8. Sessions & Runs

One sidebar item, one chapter. **Runs** are workflow runs; **sessions** are the
individual agent sessions inside them (each step of a run is one session, and
sessions can also run on their own). They share a single list.

- **What it is.** Live and past agent work.
- **When to use it.** To answer "what is happening right now?" and "what
  happened, what did it produce, what did it cost?"
- **What you do.** Open a run to see its steps, which ran in parallel, and
  where it is waiting; watch a running step's terminal live, embedded in the
  page (it shows *Session starting…* until the agent's container is ready);
  approve a step that waits for a person (**Approve & continue**); retry or
  skip a step; open a finished session to read its full log.
- *Afterwards:* every run leaves a trail — status, log, artifacts, tokens, and
  cost.

## 9. Assets

- **What it is.** Files: what the team uploads and what agents produce.
- **When to use it.** Give agents input material; collect and review what they
  made.
- **What you do.** Upload files; attach them to tasks; open what a run
  produced; track versions.
- *Afterwards:* outputs are reviewable in one place instead of scattered
  across runs.

## 10. Agents

- **What it is.** Reusable personas: who the agent is, how it talks, what
  rules it follows. A persona is not a product choice — the same persona can
  run on any of the supported runtimes (Claude Code, Cursor CLI, Codex, Gemini
  CLI, Grok).
- **When to use it.** To make agent behavior consistent across workflows —
  "our reviewer", "our implementer" — instead of re-writing instructions per
  step.
- **What you do.** Create a persona, write its instructions and rules, pick it
  in workflow steps. Remind: runs happen under credentials people connect in
  **Profile**.
- *Afterwards:* steps reference personas by name, and changing a persona
  changes every workflow that uses it.

## 11. Wrappers

- **What it is.** A way to turn a script or an API into something an agent can
  call, when no connector exists for that service.
- **When to use it.** Your internal service, an odd API, a one-off script.
- **What you do.** Define the wrapper once; agents in this project can then
  call it during runs.
- *Afterwards:* the wrapper shows up in run logs as a capability the agents
  actually called.

## 12. Skills

- **What it is.** Packaged instructions an agent can load during a session —
  know-how, not tools.
- **When to use it.** Recurring expertise: "how we write migrations", "our
  review checklist".
- **What you do.** Install a skill from the catalog or write one by hand;
  attach it where it should be available.
- *Afterwards:* agents follow the skill's instructions when the work matches.

## 13. Connectors

- **What it is.** Connections that give agents extra tools — issue trackers
  and other external services.
- **When to use it.** The agent needs to act on a system outside the codebase.
- **What you do.** Add a connector from the catalog (or by hand); supply its
  credentials via **Secrets & Variables**.
- *Afterwards:* the connected service's actions appear among what agents can
  do.

## 14. Repositories & Integrations

- **What it is.** **Repositories** are the Git repos agents work in and push
  to. **Integrations** are the accounts Flow connects to on the team's behalf:
  GitHub, GitLab, Linear, Slack, and Coder.
- **When to use it.** Any workflow that should read code, open pull requests,
  or touch tickets.
- **What you do.** Connect the integration, link the repositories the project
  needs.
- *Afterwards:* runs can produce branches and pull requests in your own
  repos, and tickets can flow both ways.

## 15. AI Builder

- **What it is.** Describe a process in plain language; the product builds the
  tasks, board setup, and workflows from that prompt. (This guide uses **AI
  Builder**, matching the sidebar entry point; the builder's own pages — and
  the changelog taxonomy — say **Aixle Builder**. Show both names once, then
  stick to AI Builder.)
- **When to use it.** Setting up a new process — instead of configuring
  columns, workflows, and steps by hand.
- **What you do.** Write what you want to automate; review what the builder
  proposes; accept, then adjust by hand where needed. While it works you can
  watch its terminal, and open its workspace in an editor.
- *Afterwards:* the board and workflows exist and are editable like anything
  built manually.

## 16. Team

- **What it is.** **Members** at two levels: who is in the company, and who is
  on each project.
- **Roles.** **Admin** manages members, integrations, and settings;
  **Employee** works within projects; **Viewer** looks without touching.
- **What you do.** Invite people by email, set their role, add them to
  projects.
- *Afterwards:* each person sees what their role allows — admins additionally
  see company-wide analytics and sessions.

## 17. Secrets & Variables

- **What it is.** Values agents and connectors need at runtime — credentials
  and configuration — kept out of task text and workflow instructions.
- **When to use it.** Any time a run needs a key, token, or setting.
- **What you do.** Add the value once, name it, reference it where needed.
- *Afterwards:* runs use the value without anyone pasting it into a card.

## 18. Analytics

- **What it is.** Usage and cost: spend, sessions, tokens, success — by
  project, agent, and source.
- **Two levels.** Project **Analytics** for the team; company **Analytics**
  and company **Sessions** for admins, across all projects.
- **What you do.** Answer "what did this cost us?", "which workflows work?",
  "where does agent time go?"
- *Afterwards:* cost conversations happen with numbers, per project and per
  company.

## 19. Settings

- **What it is.** The project's own settings: its name, its language, and the
  end of its life — archive or delete.
- **When to use it.** Renaming a project, changing the language agents write
  in, retiring a project that is finished.
- **What you do.** Edit and save; archive when work stops; delete when nothing
  should remain. Say plainly what delete takes with it.
- *Afterwards:* an archived project is out of the way without losing its
  history.

## 20. The company workspace

Round off with the shared layer above projects.

- **Projects** — create and switch between them.
- **Workflow Catalog** — reusable workflows the team can copy into any
  project.
- **Company Assets** and **Company Members** — workspace-level files and
  people. Company Assets, like company Analytics and Sessions, is visible to
  admins only.
- Switching companies when you belong to more than one workspace.

---

## End-to-end stories

Two closing chapters that retell the loop as narratives. Each one names every
screen it touches, so the reader can replay it.

### Story 1 — drop a card, get a pull request back

A lead links a repository (Integrations → Repositories), binds the
"Implementation" column of a **Dev Team** board to an implementation workflow,
and writes a card describing a small feature. They drag the card into the
column. The workflow starts: one step plans, two parallel steps implement and
write tests, a final step waits for a human. The lead watches the run in
**Sessions & Runs** — the implementing step's terminal live on the page — reads
the diff summary the agent posted to the card, approves the waiting step, and a
pull request appears in the linked repo. The card's CI gate goes from
**waiting** to **passed**. The cost of the whole run is on the card and in
Analytics.

### Story 2 — build a workflow from one prompt

An operator opens **AI Builder** and types: "When a card lands in *Triage*,
summarize it, label it, and draft a reply for review." The builder proposes a
board column, a three-step workflow, and the connector it needs. The operator
accepts, adds the connector credential in **Secrets & Variables**, and drops a
test card into *Triage*. The run appears in **Sessions & Runs**; the draft reply
lands on the card as a comment — written by an agent, reviewed by a person.

---

## Terminology notes

For guide writers — where the UI's names differ from what you might expect, or
from each other. Verified against the product as of 2026-08.

| Guide term | On screen |
| --- | --- |
| Tasks | Sidebar item **Tasks**; the page itself is titled **Board** |
| Sessions & Runs | One sidebar item, **Sessions & Runs**: agent sessions and workflow runs share a single list. The standalone **Sessions** item in the company nav is the cross-project, admin-only view |
| AI Builder | Sidebar card **AI Builder** with button **Build with AI**; the feature's own pages are titled **Aixle Builder** |
| Board templates | Offered on an empty board (not at project creation); UI says "template" (**Use this template**), preset names **Simple Kanban**, **Dev Team**, **Full SDLC** |
| Workflow start | Trigger labels on screen: **Task enters column** (Auto or Manual mode), **On schedule**, **Slack message**, **Incoming webhook** — plus running by hand from the workflow or task |
| Gates | On a card, a gate chip reads **waiting**, **passed**, **failed**, or **stale** (CI never reported) |
| Step failure options | **On Failure**: Fail / Retry / Skip; **Skip Policy**: Never / If outputs exist / Manual |
| Human approval | A waiting step shows **Approve & continue** |
| Live terminal | A running step embeds the agent's terminal; before the container is ready it reads **Session starting…**, then **Connecting to terminal…** |
| Profile | Tabs **Account**, **Usage**, **MCP** — the last is personal access for agents run outside Aixle |
| Docs | The operator documentation portal at `/docs`, reachable from the public site (**Documentation**); there is no docs item in the app sidebar |
