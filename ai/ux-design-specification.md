---
stepsCompleted:
  - 1
  - 2
  - 3
  - 4
  - 5
  - 6
  - 7
  - 8
  - 9
  - 10
  - 11
  - 12
  - 13
  - 14
lastStep: 14
completedAt: 2026-01-21
inputDocuments:
  - ai/prd.md
  - ai/project-overview.md
  - ai/architecture-web.md
  - ai/integration-architecture.md
documentCounts:
  prd: 1
  brief: 0
  architecture: 2
  overview: 1
workflowType: 'ux-design'
projectType: 'brownfield'
---

# UX Design Specification — Palad

**Author:** Artem_petrov
**Date:** 2026-01-21

---

## Executive Summary

### Project Vision

**Palad** — a cloud platform for orchestrating AI coding agents. This is not yet another AI coding tool, but an **orchestration layer** for existing agents (Claude Code, Codex, OpenCode, Cursor CLI) with centralized workflows, shared settings, and transparent billing.

The name comes from the Palladium — a sacred object, the "anchor" of Troy's protection. The platform serves as an anchor for the chaos of local AI tools.

**Target audience:** A services company (~70 people), fixed-bid projects. First an internal tool, then a public SaaS.

### Target Users

| Persona | Role | Primary scenario |
|---------|------|-------------------|
| **Developer (Misha)** | Middle Dev | Interactive coding sessions with the agent |
| **Senior Dev (Sasha)** | Senior Dev | Non-interactive batch execution |
| **Tech Lead (Katya)** | Tech Lead | Planning workflows (PRD → Tasks) |
| **Admin (Andrey)** | Co-founder | Configuring workflows, tools, secrets |
| **PM (Lena)** | Project Manager | Tracking costs and analytics |

### Key Design Challenges

1. **Information Architecture Complexity** — Many entities (Companies, Projects, Workflows, Steps, Runs, Sessions, Artifacts, Tasks, Tools, MCPs, Secrets). A clear hierarchy and progressive disclosure are needed.

2. **Multi-user Collaboration** — Workflow runs may have steps performed by different people. Visibility into who is doing what is needed, without the ability to "peek" into someone else's terminal.

3. **Two Modes Mental Model** — Interactive and Non-interactive modes require different UI patterns. The mode is chosen at session start.

4. **Terminal in Browser** — ttyd iframe + file tree + file viewer. It should feel like a real IDE, not like a "web application."

### Design Opportunities

1. **Onboarding as Value Demonstration** — Mandatory onboarding with agent setup immediately shows the value of the platform.

2. **Artifact Provenance** — Every artifact knows where it came from (which step of which workflow). This is transparency and trust.

3. **Workflow Progress Visualization** — A stepper with states (completed, in progress by me/other, waiting) gives clarity to the whole team.

4. **Integrated Analytics** — Cost tracking at the step/workflow/project/user level. The PM sees the big picture, the developer understands their contribution.

---

## Core User Experience

### Defining Experience

**Palad is a command center for AI-assisted development.** A single place where tasks, context, agents, results, and transparency come together.

**Core Loop:** Task → Context → Session → Artifact → Next task

The product adds value on top of existing tools (Claude Code, Cursor, Linear) rather than replacing them. The goal is to make usage so much more convenient that you won't want to go back to scattered local tools.

### Platform Strategy

| Aspect | Decision |
|--------|---------|
| Platform | Web-first |
| Input | Desktop (mouse/keyboard) |
| Mobile | Not in MVP |
| Offline | Not supported (cloud agents) |

### Effortless Interactions

1. **Session start** — 2 clicks from task to a working terminal. Context is pulled in automatically.

2. **Navigation through artifacts** — The main UX focus. Provenance everywhere, quick search, filters, inline preview.

3. **Context switching** — Sessions preserve state. Return to a task and everything is in place.

4. **Understanding costs** — Cost is visible at every level: step, workflow, project, user.

### Critical Success Moments

| Moment | Description |
|--------|----------|
| First session | After onboarding, the first session starts in 30 seconds |
| Workflow completed | Summary with artifacts and total cost |
| Team transparency | Visible who is working on which step |
| Artifact found | Search + provenance = answer in seconds |

### Experience Principles

1. **Context is King** — The system knows the connections, the user does not assemble context manually
2. **Provenance Everywhere** — Every artifact knows its history
3. **Transparency by Default** — Costs and statuses are visible without extra actions
4. **Two Clicks to Action** — From intent to action in at most 2 clicks
5. **Graceful Degradation** — On failures, data is not lost and you can continue

---

## Desired Emotional Response

### Primary Emotional Goals

**Efficient + Empowered** — "I do more in less time, and I have a superpower — AI agents work for me."

This is not about "AI does it for me" but about amplifying capabilities. The user stays in control, but their capabilities are extended.

### Emotional Journey Mapping

| Stage | Emotion | Trigger |
|------|--------|---------|
| Onboarding | Clarity — "Easy and clear" | Simple steps, agents configured |
| First session | Confidence — "Works like local!" | Terminal is responsive, familiar experience |
| Work | Flow — "Focus, efficiency" | Everything under control, clear reasons |
| Completion | Satisfaction — "I see the result!" | Artifacts ready, cost visible |
| Error | Control — "Manageable and reversible" | Clear cause, path to recovery |

### Micro-Emotions

**Priority:**
- **Connectedness** — when searching for artifacts and viewing colleagues' status
- **Satisfaction** — when completing a session/workflow

**Supporting:**
- Confidence — the terminal works reliably
- Control — errors are clear and reversible

### Design Implications

| Emotion | UX solution |
|--------|------------|
| Efficient | 2 clicks to action, automatic context |
| Empowered | Visible progress, accumulation of artifacts |
| Connectedness | Real-time team statuses, artifact provenance |
| Satisfaction | Summary screens with results and costs |
| Control | Clear error states, undo where possible |
| No Overwhelm | Progressive disclosure, focused views |

### Emotional Design Principles

1. **Result is visible** — Every action → visible result
2. **Team is nearby** — Always visible who does what
3. **Control preserved** — Errors are clear, actions are reversible
4. **Like local** — A terminal without the "web compromise"
5. **No overload** — Only what is needed, at the right moment

### Unique Emotional Differentiator

**"Real results from team work in one place"**

Not about the tool — about the RESULT. Not about the individual — about the TEAM. Not abstractly — VISIBLY.

---

## UX Pattern Analysis & Inspiration

### Inspiring Products Analysis

**VS Code:**
- Command Palette for quick actions
- Resizable panels for flexible layout
- Activity Bar for navigation
- Status Bar for context info
- Extensions ecosystem

**Raycast:**
- Instant response (<100ms)
- Keyboard-first design
- Fuzzy search everywhere
- Clean, minimal UI
- Cmd+K for global actions

**GitHub:**
- Actions workflow view (steps timeline)
- PR timeline for history
- Code review UI
- Notifications system

### Transferable UX Patterns

**Navigation:**
- VS Code-style layout: Activity Bar + Panels + Status Bar
- Raycast-style Command Palette (Cmd+K)

**Workflow Visualization:**
- GitHub Actions-style stepper with timeline
- Expandable steps with artifacts and costs

**File Management:**
- VS Code-style File Tree (read-only, real-time)
- Google Drive-style flat artifact list with provenance

**Interactions:**
- Keyboard shortcuts for all main actions
- Fuzzy search for artifacts, workflows, tasks
- Resizable panels

### Anti-Patterns to Avoid

| Avoid | Reason |
|----------|---------|
| Overloaded UI (Jenkins) | No focus |
| Many clicks (Jira) | Kills flow |
| Overwhelming complexity (AWS) | Feeling lost |
| Loss of context (Slack threads) | Hard to find |
| Slow response | Annoyance |
| Modal windows everywhere | Blocks work |

### Design Inspiration Strategy

**Adopt:** Command Palette, Resizable Panels, Workflow Timeline, Keyboard shortcuts, Status Bar

**Adapt:** File Explorer (read-only), PR Timeline → Session history, Extensions → Tools/MCPs, Drive files → Flat + provenance

**Avoid:** Deep folder hierarchies, Modal dialogs, Multi-step wizards, Tabs overflow

---

## Design System Foundation

### Design System Choice

**MUI 6 + Custom Dark Theme**

Material UI as the foundation with deep theme customization for a developer-focused experience. MUI is already in the project (v6.4.7), which eliminates migration and speeds up development.

### Visual Direction

**Monochrome base + bright accents**

- **Grayscale foundation:** backgrounds, text, borders — neutral tones from #09090B to #FAFAFA
- **Accent colors:** only for the important — actions (blue), success (green), warnings (amber), errors (red)
- **Dark theme only** for MVP

### Color Tokens

| Token | Hex | Usage |
|-------|-----|-------|
| background.base | #09090B | Page background |
| background.surface | #18181B | Cards, panels |
| background.elevated | #27272A | Hover, selected |
| border.default | #3F3F46 | Borders, dividers |
| text.primary | #D4D4D8 | Main text |
| text.secondary | #A1A1AA | Secondary text |
| text.muted | #52525B | Disabled, hints |
| accent.blue | #3B82F6 | Primary actions, links |
| accent.green | #22C55E | Success, completed |
| accent.amber | #F59E0B | Warnings, in-progress |
| accent.red | #EF4444 | Errors, destructive |

### Spacing & Density

**Comfortable density** — more breathing room for readability:

| Element | Value |
|---------|-------|
| Page padding | 24-32px |
| Card padding | 16-24px |
| Section gap | 24px |
| Item gap | 12-16px |

### Typography

| Role | Font | Weight | Size |
|------|------|--------|------|
| Headings | Inter | 600 | 24/20/16px |
| Body | Inter | 400 | 14px |
| Labels | Inter | 500 | 12px |
| Code/Data | JetBrains Mono | 400 | 13-14px |

### Custom Components

| Component | Purpose |
|-----------|---------|
| CommandPalette | Global Cmd+K search & actions |
| WorkflowStepper | Vertical timeline with statuses |
| StatusBar | Session info, cost, status |

### Implementation Approach

1. **Theme Foundation** — MUI theme with grayscale palette, spacing, typography
2. **Core Components** — CommandPalette, WorkflowStepper, StatusBar
3. **Polish** — Transitions, loading states, error states

---

## Defining Experience

### Core Statement

**"Palad — the place where a team truly uses AI effectively and sees results"**

- **Team** — collaborative, not a solo tool
- **Truly effective** — production value, not a toy
- **Sees results** — artifacts, costs, progress

### User Mental Model

**Metaphor: "GitHub for AI work"**

Just as GitHub collects a team's code with history and collaboration, Palad collects a team's AI results with provenance and costs.

**User expectations:**
- Configure once — works everywhere
- Workflows are ready and reusable
- Costs are transparent at every level
- Artifacts in one place with history
- Visible what the team is doing

### Success Criteria

| Criterion | Metric |
|----------|---------|
| Artifact found | < 10 seconds |
| Context is clear | Provenance visible immediately |
| Team is visible | Real-time statuses |
| Session starts | < 30 seconds |
| Result is visible | Summary after completion |

**"Wow" moment:** The project completed successfully, and you can see how AI helped at every stage — artifacts, costs, timeline.

### Pattern Strategy

| Aspect | Type | Source |
|--------|-----|----------|
| Terminal | Established | VS Code |
| Workflow stepper | Established | GitHub Actions |
| Command Palette | Established | Raycast |
| Artifact provenance | **Novel** | Palad unique |
| Team status | **Novel** | Palad unique |
| Cost tracking | **Novel** | Palad unique |

**Strategy:** Established for core, Novel for differentiators.

### Experience Mechanics

**Primary: Artifact Discovery**
1. Initiation: Cmd+K or Artifacts tab
2. Interaction: Fuzzy search + filters, provenance inline
3. Feedback: Instant results (< 100ms)
4. Completion: Viewer with full provenance and actions

**Secondary: Team Visibility**
1. Passive: Statuses in Workflow Run view
2. Active: Project Overview, activity feed
3. Outcome: No duplication, connectedness

---

## Visual Design Foundation

### Layout Structure

**Global Layout:**
- Header (fixed, 56px): Logo, Breadcrumb, Cmd+K, Notifications, Avatar
- Main Content: varies by screen, max-width 1400px centered
- No persistent sidebar — navigation through tabs + Command Palette

**Screen Layouts:**

| Screen | Layout Type | Key Elements |
|--------|-------------|--------------|
| Projects Dashboard | Grid of cards | Project cards, responsive grid (min 300px) |
| Project View | Tabs + content | 6 tabs (Overview, Tasks, Workflows, Artifacts, Analytics, Settings) |
| Session View | VS Code panels | File Tree (resizable) + Terminal/Viewer + Status Bar |
| Workflow Run | Vertical timeline | Steps stepper + artifacts section |

### Grid & Spacing System

| Token | Value | Usage |
|-------|-------|-------|
| spacing.base | 8px | All spacing multiples of 8 |
| spacing.page | 32px | Page padding |
| spacing.card | 24px | Card/panel padding |
| spacing.section | 24px | Between major sections |
| spacing.item | 16px | Between list items |
| spacing.inline | 8px | Between inline elements |
| layout.maxWidth | 1400px | Main content area |
| layout.sidebarMin | 200px | File tree minimum |
| layout.sidebarMax | 400px | File tree maximum |

### Component Patterns

**Cards:**
- Background: surface (#18181B)
- Border: 1px border.default (#3F3F46)
- Border-radius: 8px
- Padding: 24px
- Hover: elevated (#27272A)

**Buttons:**
| Type | Background | Text |
|------|------------|------|
| Primary | accent.blue | white |
| Secondary | transparent | text.primary |
| Ghost | transparent | text.secondary |
| Danger | accent.red | white |

Padding: 12px 24px, border-radius: 6px

**Status Indicators:**
| Status | Color | Icon |
|--------|-------|------|
| Completed | accent.green | ✅ |
| In Progress (mine) | accent.blue | 🔵 |
| In Progress (other) | accent.amber | 🟡 |
| Waiting | text.muted | ○ |
| Error | accent.red | ❌ |

### Accessibility Considerations

- Contrast ratios: WCAG AA minimum (4.5:1 for text)
- Focus states: visible outline using accent.blue
- Keyboard navigation: all interactive elements accessible
- Screen reader: semantic HTML, ARIA labels where needed
- Motion: respect prefers-reduced-motion

---

## Design Direction

### Chosen Direction: "Developer Command Center"

**Visual Identity:**
- GitHub Dark + VS Code minimalism
- Clean, focused, no visual noise
- Monochrome base, color = meaning
- Professional but not corporate

**Personality:**
- Efficient — every pixel serves a purpose
- Trustworthy — clarity builds confidence
- Modern — current but not trendy
- Developer-native — feels like home for engineers

**Visual Principles:**
1. Content first — UI fades into background
2. Color = signal — only for status, actions, errors
3. Breathing room — comfortable spacing
4. Consistent rhythm — 8px grid everywhere
5. Subtle depth — minimal shadows, borders for structure

### Reference Sources

| Reference | What to Take |
|-----------|--------------|
| GitHub Dark | Color palette, card style, typography |
| VS Code | Panel layout, status bar, activity bar concept |
| Raycast | Command palette, speed feel, minimalism |
| Linear | Clean tables, keyboard-first, animations |
| Vercel | Dashboard cards, deployment logs style |

### Interactive Mockup

**File:** `ai/ux-design-mockup.html`

Screens included:
1. Projects Dashboard — cards, header, Cmd+K
2. Project View — tabs, stats, workflow runs
3. Workflow Run — stepper with status states
4. Session View — file tree + terminal + status bar
5. Artifacts — search, filters, provenance
6. Command Palette — Raycast-style Cmd+K

---

## User Journey Flows

### Flow 1: First-Time User Onboarding

**Entry:** Invite link from admin
**Exit:** Projects Dashboard with configured agents
**Time:** ~3-5 minutes

Steps:
1. Click invite link
2. Google OAuth
3. Welcome screen: "Which agents do you use?"
4. Select agents (checkboxes)
5. For each selected agent: login flow in embedded terminal
6. Success: "Done! Your agents are configured"
7. Redirect to Projects Dashboard

### Flow 2: Task → Interactive Session

**Entry:** Tasks tab in Project
**Exit:** Session summary with artifacts and cost

Steps:
1. Open Tasks tab → see Linear tasks
2. Click task → Task Detail view
3. See: description, related artifacts, previous sessions
4. Click "Start Session" → Configure modal (agent, mode, context, repo)
5. Click "Start" → Session View opens
6. Work in terminal (Interactive mode)
7. Click "Stop Session" or agent completes
8. See Summary: artifacts created, cost, duration

### Flow 3: Workflow Execution

**Entry:** Workflows tab
**Exit:** All artifacts saved, total cost visible

**Interactive Mode (per step):**
1. Step starts → Session opens
2. User works with agent
3. User approves artifact → Save
4. Step completes → Next step available
5. Repeat until all steps done

**Non-Interactive Mode:**
1. All steps queued
2. Agent works autonomously
3. Notifications on completion
4. User reviews artifacts at end

### Flow 4: Artifact Discovery

**Entry:** Cmd+K or Artifacts tab
**Exit:** Artifact viewer with full provenance

**Two paths:**
1. Quick (Cmd+K): Type → See results with provenance → Click → View
2. Browse (Tab): Artifacts tab → Filter → Scroll → Click → View

Provenance visible at every step: `PRD Creation #3 → Step 3 • Katya • 2 hours ago`

### Flow 5: Workflow Builder

**Entry:** Workflows tab → "+ Create Workflow"
**Exit:** New workflow available for runs

Steps:
1. Click "Create Workflow"
2. Enter name and description
3. Add steps (for each step configure):
   - Step name
   - Agent selection
   - Prompt template
   - Tools selection
   - MCPs selection
   - Expected artifact name
4. Review workflow structure
5. Save workflow

### Flow 6: Tools Configuration

**Entry:** Settings tab → Tools section
**Exit:** Tool available for use in workflows

Steps:
1. Navigate to Settings → Tools
2. Click "+ Create Tool"
3. Configure:
   - Tool name and description
   - Docker image
   - Environment variables (with secret references)
   - Required secrets
4. Test tool (optional)
5. Save tool

### Flow 7: MCP Configuration

**Entry:** Settings tab → MCPs section
**Exit:** MCP connected and available

Steps:
1. Navigate to Settings → MCPs
2. Click "+ Add MCP"
3. Select MCP type (GitHub, Linear, Slack, etc.)
4. Configure connection:
   - Repository/workspace details
   - Authentication (secret reference)
   - Permissions
5. Test connection
6. Save MCP

### Journey Patterns

**Navigation Patterns:**
- Breadcrumb back — always can return
- Cmd+K anywhere — global search available everywhere
- Tab-based sections — within Project view

**Decision Patterns:**
- Configure before action — select agent/mode before start
- Smart defaults — pre-filled based on context

**Feedback Patterns:**
- Status visible — always see state (running, completed)
- Cost visible — shown at every level
- Provenance inline — artifact source visible immediately

**Error Patterns:**
- Graceful stop — can stop session without data loss
- Recovery path — can continue if something fails

### Settings Tab Structure

| Section | Content |
|---------|---------|
| General | Project name, description, repository |
| Workflows | List + Create/Edit workflows |
| Tools | List + Create/Edit tools |
| MCPs | List + Add/Configure MCPs |
| Secrets | Manage secrets (write-only) |
| Members | Project collaborators |
| Billing | Usage and costs |

---

## Component Strategy

### Design System Coverage (MUI 6)

**Available from MUI:**
- Layout: Box, Container, Grid, Stack
- Inputs: Button, TextField, Select, Checkbox, Switch
- Navigation: Tabs, Breadcrumbs, Menu, Drawer
- Data Display: Table, List, Card, Chip, Avatar, Badge
- Feedback: Alert, Snackbar, Dialog, Progress, Skeleton
- Surfaces: Paper, Accordion

### Custom Components Needed

| Component | Priority | Purpose |
|-----------|----------|---------|
| WorkflowStepper | P0 | Vertical timeline with status states |
| StatusBar | P0 | Session info (agent, status, cost, duration) |
| FileTree | P0 | Session workspace (exists, needs styling) |
| ArtifactCard | P1 | Artifact display with provenance |
| ProjectCard | P1 | Dashboard project cards |
| StepConfigPanel | P1 | Workflow step configuration |
| ToolConfigPanel | P2 | Tool configuration form |
| MCPConfigPanel | P2 | MCP configuration form |

### Component Specifications

**WorkflowStepper:**
- Vertical timeline layout
- Indicator states: completed (green), running-mine (blue), running-other (amber), pending (gray), error (red)
- Connector lines between steps
- Expandable content with artifacts and metadata

**StatusBar:**
- Fixed height: 28px
- Sections: Agent, Status, Cost, Duration
- Status colors match indicator states

**ArtifactCard:**
- Icon based on file type
- Name in monospace
- Provenance line: "Workflow → Step • User • Time"
- Actions: View, Download

**StepConfigPanel:**
- Step name input
- Agent selector
- Prompt textarea
- Tools checkboxes
- MCPs checkboxes
- Expected artifact input

### Implementation Strategy

**Foundation:** Use MUI components with custom theme tokens

**Custom Layer:** Build on MUI primitives:
```
Card → ArtifactCard, ProjectCard
Stepper → WorkflowStepper (heavily customized)
Box → StatusBar
TreeView → FileTree (with react-accessible-treeview)
Dialog + Forms → ConfigPanels
```

### Implementation Roadmap

**Phase 1 (MVP):**
1. WorkflowStepper
2. StatusBar
3. FileTree styling

**Phase 2 (Supporting):**
4. ArtifactCard
5. ProjectCard
6. StepConfigPanel

**Phase 3 (Enhancement):**
7. ToolConfigPanel
8. MCPConfigPanel
9. AnalyticsCharts

**Future (Post-MVP):**
- CommandPalette (when content volume justifies global search)

---

## UX Consistency Patterns

### Button Hierarchy

| Type | Style | Usage | Example |
|------|-------|-------|---------|
| **Primary** | Blue filled | Main action, ONE per view | "Start Session", "Save Workflow" |
| **Secondary** | Outlined | Supporting actions | "Cancel", "Edit" |
| **Ghost** | Text only | Tertiary, low weight | "Learn more", "Skip" |
| **Danger** | Red outlined | Destructive actions | "Stop Session", "Delete" |
| **Icon** | Icon only + tooltip | Compact actions | Edit, Download icons |

### Status Indicators

| Status | Color | Icon | Usage |
|--------|-------|------|-------|
| Completed | accent.green | ✓ | Finished steps/sessions |
| Running (mine) | accent.blue | ● pulse | My active work |
| Running (other) | accent.amber | ● | Other user's work |
| Pending | text.muted | ○ | Waiting |
| Error | accent.red | ✗ | Failed |

**Cost Display:** Monospace font, green color, format: $XX.XX
**Timestamps:** Relative ("2 hours ago"), absolute on hover

### Feedback Messages (Toasts)

| Type | Border | Dismiss | Usage |
|------|--------|---------|-------|
| Success | Green | Auto 3s | Action completed |
| Error | Red | Manual | Failures, include hint |
| Warning | Amber | Manual | Alerts, cost warnings |
| Info | Blue | Auto 5s | Notifications |

### Loading States

| Context | Pattern |
|---------|---------|
| Content (cards, lists) | Skeleton matching layout |
| Buttons | Spinner, disabled state |
| Terminal | "Connecting..." + cursor |
| File tree | Skeleton or text |

### Empty States

Structure:
1. Icon/Illustration (optional)
2. Title (what's empty)
3. Description (why + what to do)
4. Action button (if applicable)

Examples:
- No artifacts: "Run a workflow to create your first artifact"
- No tasks: "Connect Linear to see your tasks"
- Search no results: "No artifacts match your search"

### Error Handling

| Context | Pattern |
|---------|---------|
| Form fields | Red border + message below |
| Page level | Alert banner, dismissible |
| Session | StatusBar indicator + modal details |

Recovery: Always provide next step (retry, check config, contact support)

### Form Patterns

- Labels above inputs
- Full width inputs
- Validate on blur
- Required fields marked with *
- Actions: Cancel (secondary, left) + Save (primary, right)

### Navigation Patterns

| Pattern | Behavior |
|---------|----------|
| Breadcrumbs | Clickable ancestors, current not clickable |
| Tabs | Horizontal, blue underline active, URL updates |
| Back | "← Projects" link, consistent left position |
| Deep links | Every view has unique URL, bookmarkable |

---

## Responsive Design & Accessibility

### Responsive Strategy

**Platform:** Desktop-only (1024px minimum)

**Rationale:** Palad is a developer tool with terminal, file tree, and workflow builder — features that require desktop screen real estate.

### Breakpoint Strategy

| Resolution | Name | Sidebar | Panels | Density |
|------------|------|---------|--------|---------|
| 1024-1279px | Compact | Collapsed default | Single | Compact |
| 1280-1439px | Standard | Expanded | Resizable | Standard |
| 1440-1919px | Large | Expanded | Multi-panel | Comfortable |
| 1920px+ | Wide | Expanded | Wide | Spacious |

**Small Screen Handling (<1024px):**
- Display message: "Palad requires a desktop browser (1024px minimum)"
- No broken layouts or horizontal scroll

### Accessibility Strategy

**Compliance Level:** WCAG 2.1 AA

**Color Contrast:**
| Element | Ratio | Requirement |
|---------|-------|-------------|
| text.primary on bg.primary | 19.6:1 | ✅ 4.5:1 |
| text.secondary on bg.primary | 8.5:1 | ✅ 4.5:1 |
| text.muted on bg.primary | 4.5:1 | ✅ 4.5:1 |
| UI components | 3:1+ | ✅ 3:1 |

**Keyboard Navigation:**
- All interactive elements focusable
- Logical tab order (visual order)
- Visible focus indicators (2px blue outline)
- Skip link to main content
- Escape closes modals/overlays

**Screen Reader Support:**
- Semantic HTML landmarks (header, nav, main, aside, footer)
- ARIA labels for icon buttons
- ARIA live regions for status updates
- Heading hierarchy (h1 → h2 → h3)

**Motion:**
- Respect `prefers-reduced-motion`
- No auto-playing animations

### Testing Strategy

| Type | Tool | Frequency |
|------|------|-----------|
| Contrast | Lighthouse, axe DevTools | Every PR |
| Keyboard | Manual testing | Weekly |
| Screen reader | VoiceOver | Monthly |
| Automated | axe-core in CI | Every build |

### Implementation Guidelines

**Focus Ring:**
```css
:focus-visible {
  outline: 2px solid #3B82F6;
  outline-offset: 2px;
}
```

**Checklist:**
- Semantic landmarks in layout
- Skip link as first focusable element
- aria-label on all icon buttons
- aria-live for status changes
- Modal focus trap implementation
