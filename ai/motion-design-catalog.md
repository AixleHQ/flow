# Motion Design & Animation Catalog — Aixle

**Author:** Artem_petrov
**Date:** 2026-02-22
**Inspiration:** Factory.ai, Linear, Vercel, GitHub, Raycast
**Status:** Draft — needs stakeholder review

---

## Context

This document catalogs visual effects, animations, and motion design patterns that can elevate Aixle's user experience. Inspiration is drawn primarily from Factory.ai (GSAP 3.13 + Three.js r182 + Rive + Canvas 2D + 26 CSS keyframes), with additional references from Linear, Vercel, and GitHub.

Aixle is a **working SaaS product** (not a marketing site), so every animation must serve productivity and clarity. The catalog is organized into tiers by implementation complexity and impact.

### Technology Stack Reference (Current)

| Layer | Current | Animation-Ready |
|-------|---------|-----------------|
| UI Framework | MUI 6.x | Built-in transitions |
| Build | Vite 7.3.1 | Tree-shaking friendly |
| State | Redux Toolkit + Zustand | Can drive animation state |
| Routing | TanStack Router | Route transitions possible |

### Proposed Animation Technology Stack

| Library | Size | Purpose | Tier |
|---------|------|---------|------|
| CSS Keyframes + Transitions | 0 KB | Micro-interactions, hover, focus | T1 |
| Intersection Observer API | 0 KB | Scroll-triggered reveals | T1 |
| MUI Transitions (Fade, Grow, Slide, Collapse) | 0 KB (included) | Component mount/unmount | T1 |
| Framer Motion | ~32 KB | Complex orchestrated animations, layout | T2 |
| GSAP (gsap + ScrollTrigger) | ~25 KB | Timeline, scroll-based, path animations | T2-T3 |
| Rive (@rive-app/react-canvas) | ~160 KB | Interactive vector animations | T3 |
| Three.js (react-three-fiber) | ~150 KB | 3D WebGL visualizations | T4 |
| Lottie (lottie-react) | ~30 KB | After Effects JSON animations | T3 |

---

## Tier 1 — CSS Only (Zero Dependencies)

Estimated effort: 1-2 days for all. No new dependencies.

### T1-01: Status Pulse Animation

**Where:** Workflow Stepper running indicators, Session status, Header notifications badge
**What:** Pulsing dot/ring on "Running" status indicators — conveys liveness.
**Reference:** Factory.ai uses orange pulse on their "VISION" marker.

```css
@keyframes pulse-ring {
  0% { box-shadow: 0 0 0 0 rgba(59, 130, 246, 0.5); }
  70% { box-shadow: 0 0 0 8px rgba(59, 130, 246, 0); }
  100% { box-shadow: 0 0 0 0 rgba(59, 130, 246, 0); }
}
/* accent.blue for mine, accent.amber for other user */
```

**Impact:** High — instant "alive" feeling for running processes.
**Reduced-motion:** Replace with static filled dot.

---

### T1-02: Card Hover Lift & Border Glow

**Where:** Project cards, Artifact cards, Workflow cards, Tool cards, News items
**What:** Subtle lift (translateY -2px) + border color shift + shadow on hover.
**Reference:** Factory.ai news cards, Linear issue cards.

```css
.card {
  transition: transform 200ms ease, border-color 200ms ease, box-shadow 200ms ease;
}
.card:hover {
  transform: translateY(-2px);
  border-color: #52525B; /* border.default → slightly lighter */
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
}
```

**Impact:** Medium — adds tactile feedback, "clickable" feel.
**Reduced-motion:** Keep border-color change, remove translateY.

---

### T1-03: Scroll Fade-In Reveal

**Where:** All list pages (projects, artifacts, workflows, tools, MCPs), Settings sections
**What:** Elements fade in + slide up slightly as they enter viewport.
**Reference:** Factory.ai section reveals, Vercel homepage sections.

Implementation: Intersection Observer + CSS classes.

```css
.reveal { opacity: 0; transform: translateY(20px); transition: all 500ms ease; }
.reveal.visible { opacity: 1; transform: translateY(0); }
```

**Impact:** High — makes pages feel dynamic rather than static dumps of content.
**Reduced-motion:** Elements render visible immediately, no animation.

---

### T1-04: Skeleton Shimmer Loading

**Where:** All data-fetching views (project list, artifact list, session logs, analytics)
**What:** MUI Skeleton with animated shimmer gradient while data loads.
**Reference:** GitHub loading states, Linear skeleton patterns.

```css
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}
```

**Impact:** High — eliminates layout shift, feels fast even when loading.
**Reduced-motion:** Static gray block without shimmer.

---

### T1-05: Smooth Tab Transitions

**Where:** Project View tabs (Overview, Tasks, Workflows, Artifacts, Analytics, Settings)
**What:** Content cross-fade when switching tabs (opacity transition on entering/exiting content).
**Reference:** Linear tab transitions.

```css
.tab-content-enter { opacity: 0; }
.tab-content-enter-active { opacity: 1; transition: opacity 200ms ease; }
.tab-content-exit { opacity: 1; }
.tab-content-exit-active { opacity: 0; transition: opacity 150ms ease; }
```

**Impact:** Medium — smoother navigation feel vs instant swap.
**Reduced-motion:** Instant swap.

---

### T1-06: Button Press Feedback

**Where:** All buttons
**What:** Subtle scale-down on click (active state), scale-up on hover.
**Reference:** Raycast button interactions.

```css
.btn { transition: transform 100ms ease; }
.btn:hover { transform: scale(1.02); }
.btn:active { transform: scale(0.97); }
```

**Impact:** Low-Medium — tactile feedback for clicks.
**Reduced-motion:** Color change only.

---

### T1-07: Focus Ring Animation

**Where:** All focusable elements (keyboard navigation)
**What:** Animated focus ring that scales in from 0 to full size.
**Reference:** Linear focus indicators.

```css
:focus-visible {
  outline: 2px solid #3B82F6;
  outline-offset: 2px;
  animation: focusRing 200ms ease;
}
@keyframes focusRing {
  from { outline-offset: 6px; opacity: 0; }
  to { outline-offset: 2px; opacity: 1; }
}
```

**Impact:** Medium — better keyboard navigation experience + accessibility.
**Reduced-motion:** Static outline.

---

### T1-08: Notification Badge Bounce

**Where:** Header notifications icon, unread counts
**What:** Small bounce animation when a new notification arrives.

```css
@keyframes badge-bounce {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.3); }
}
```

**Impact:** Low — draws attention to new notifications.
**Reduced-motion:** Skip animation, just show badge.

---

### T1-09: Toast Slide-In

**Where:** Toast/Snackbar notifications (success, error, warning, info)
**What:** Slide in from right + fade, slide out on dismiss.
**Reference:** Vercel deployment notifications.

```css
@keyframes slideInRight {
  from { transform: translateX(100%); opacity: 0; }
  to { transform: translateX(0); opacity: 1; }
}
```

**Impact:** Medium — clear feedback for actions.
**Reduced-motion:** Instant appear/disappear.

---

### T1-10: Table Row Hover Highlight

**Where:** All data tables (sessions, artifacts, users, tools)
**What:** Smooth background color transition on row hover.

```css
tr { transition: background-color 150ms ease; }
tr:hover { background-color: #27272A; }
```

**Impact:** Low — better scanability in dense tables.
**Reduced-motion:** Instant color change.

---

### T1-11: Collapsible Section Accordion

**Where:** Workflow step details, Settings sections, FAQ
**What:** Smooth height animation when expanding/collapsing sections.
**Reference:** Factory.ai FAQ section, MUI Accordion.

Use MUI `<Collapse>` component with `timeout={300}`.

**Impact:** Medium — clearer spatial relationship when content reveals.
**Reduced-motion:** Instant show/hide.

---

### T1-12: Infinite Logo Carousel

**Where:** Onboarding (supported agents), Landing page (if exists)
**What:** Continuously scrolling logos of supported agents: Claude Code, Cursor CLI, Codex, Gemini CLI.
**Reference:** Factory.ai partner logos carousel (Podium, Groq, Chainguard).

```css
@keyframes carouselSlide {
  0% { transform: translateX(0); }
  100% { transform: translateX(-50%); }
}
/* Duplicate items, animate container */
```

**Impact:** Low — marketing feel, good for onboarding.
**Reduced-motion:** Static grid layout.

---

### T1-13: Progress Bar Animation

**Where:** Workflow progress, Session startup, File upload
**What:** Animated striped progress bar for indeterminate states, smooth width transition for determinate.
**Reference:** GitHub Actions progress bars.

```css
@keyframes progress-stripe {
  0% { background-position: 1rem 0; }
  100% { background-position: 0 0; }
}
```

**Impact:** Medium — visual feedback for long operations.
**Reduced-motion:** Static bar.

---

### T1-14: Chip/Tag Enter Animation

**Where:** Status chips, filter tags, selected items
**What:** Scale-in animation when a chip appears (e.g., applying a filter).

```css
@keyframes chipIn {
  from { transform: scale(0.8); opacity: 0; }
  to { transform: scale(1); opacity: 1; }
}
```

**Impact:** Low — subtle UI polish.
**Reduced-motion:** Instant appear.

---

### T1-15: Cursor Blink in Terminal Placeholder

**Where:** Session View terminal area before connection established
**What:** Blinking cursor character in "Connecting..." placeholder text.
**Reference:** Factory.ai terminal blocks with `>` prompt.

```css
@keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
.cursor { animation: blink 1s step-end infinite; }
```

**Impact:** Medium — terminal feels "alive" before actual connection.
**Reduced-motion:** Static cursor.

---

## Tier 2 — Framer Motion / Light JS (Small Dependencies)

Estimated effort: 3-5 days. Requires Framer Motion (~32 KB) or equivalent.

### T2-01: Page Route Transitions

**Where:** All route changes (Projects → Project → Session)
**What:** Cross-fade + subtle slide between route changes. Shared layout animations for elements that persist across routes (header, breadcrumbs).
**Reference:** Linear page transitions.

```tsx
<AnimatePresence mode="wait">
  <motion.div
    key={routeKey}
    initial={{ opacity: 0, y: 8 }}
    animate={{ opacity: 1, y: 0 }}
    exit={{ opacity: 0, y: -8 }}
    transition={{ duration: 0.2 }}
  >
    {children}
  </motion.div>
</AnimatePresence>
```

**Impact:** High — transforms navigation from "page reloads" to "app-like" experience.
**Reduced-motion:** Instant swap.

---

### T2-02: Staggered List Animation

**Where:** Project cards grid, Artifact list, Workflow steps, Team members
**What:** Items animate in sequentially with slight delay (stagger), creating a "cascade" effect.
**Reference:** Linear issue list, Vercel deployment cards.

```tsx
<motion.div
  variants={{ show: { transition: { staggerChildren: 0.05 } } }}
  initial="hidden" animate="show"
>
  {items.map(item => (
    <motion.div
      variants={{
        hidden: { opacity: 0, y: 20 },
        show: { opacity: 1, y: 0 }
      }}
    />
  ))}
</motion.div>
```

**Impact:** High — lists feel intentional and polished, not dumped.
**Reduced-motion:** All items appear at once.

---

### T2-03: Animated Number Counter

**Where:** Cost displays ($XX.XX), Token counts, Duration timers, Analytics numbers
**What:** Numbers count up/down smoothly when values change (like a slot machine).
**Reference:** Vercel analytics counters.

Uses `useSpring` from Framer Motion or custom `requestAnimationFrame` counter.

**Impact:** High — cost/token changes feel dynamic, not just static text swaps.
**Reduced-motion:** Instant value change.

---

### T2-04: Layout Animations (List Reordering)

**Where:** Drag-and-drop workflow steps, Filtered/sorted lists
**What:** Items smoothly slide to new positions when list order changes (filter, sort, reorder).
**Reference:** Linear kanban board transitions.

```tsx
<motion.div layout transition={{ type: "spring", damping: 25 }}>
  {item.name}
</motion.div>
```

**Impact:** High — preserves spatial understanding when content rearranges.
**Reduced-motion:** Instant repositioning.

---

### T2-05: Modal/Dialog Enter-Exit

**Where:** Session config modal, Confirmation dialogs, Command Palette
**What:** Scale up from 95% + fade in (enter), scale down + fade out (exit). Backdrop blur animates.
**Reference:** Raycast command palette appearance.

```tsx
<motion.div
  initial={{ scale: 0.95, opacity: 0 }}
  animate={{ scale: 1, opacity: 1 }}
  exit={{ scale: 0.95, opacity: 0 }}
  transition={{ duration: 0.15 }}
/>
```

**Impact:** Medium — modals feel grounded, not jarring.
**Reduced-motion:** Instant show/hide.

---

### T2-06: Drawer/Panel Slide

**Where:** Settings panels, Mobile nav (future), Side details panels
**What:** Smooth slide from edge with backdrop.

**Impact:** Medium — natural panel interactions.
**Reduced-motion:** Instant.

---

### T2-07: Typewriter Text Effect

**Where:** Terminal initialization ("Connecting to agent..."), Onboarding welcome, Session start
**What:** Text appears character by character, like someone typing.
**Reference:** Factory.ai terminal prompt animation.

```tsx
function Typewriter({ text, speed = 30 }) {
  const [displayed, setDisplayed] = useState('');
  useEffect(() => {
    let i = 0;
    const interval = setInterval(() => {
      setDisplayed(text.slice(0, ++i));
      if (i >= text.length) clearInterval(interval);
    }, speed);
    return () => clearInterval(interval);
  }, [text]);
  return <span className="mono">{displayed}<span className="cursor">|</span></span>;
}
```

**Impact:** High — terminal operations feel "alive" and immersive.
**Reduced-motion:** Show full text immediately.

---

### T2-08: Tooltip Hover with Delay & Spring

**Where:** All icon buttons, Status indicators, Truncated text
**What:** Tooltip springs in after short delay (300ms), with slight overshoot animation.
**Reference:** GitHub tooltip behavior.

**Impact:** Low-Medium — polished micro-interaction.
**Reduced-motion:** Instant tooltip.

---

### T2-09: Workflow Stepper Animated Connector Lines

**Where:** Workflow Run vertical timeline
**What:** Lines between steps animate (draw from top to bottom) as workflow progresses. Completed segments are solid green, in-progress has animated dash pattern.
**Reference:** GitHub Actions workflow visualization.

```css
.connector-active {
  stroke-dasharray: 4 4;
  animation: dashMove 1s linear infinite;
}
@keyframes dashMove {
  to { stroke-dashoffset: -8; }
}
```

**Impact:** High — workflow feels like a living process, not a static list.
**Reduced-motion:** Static lines with color only.

---

### T2-10: Expandable Card with Layout Animation

**Where:** Artifact cards (click → expand to show details + preview), Workflow step cards
**What:** Card expands in-place with smooth height/width animation, content fades in.
**Reference:** Linear issue detail expand.

```tsx
<motion.div layout>
  <Summary />
  <AnimatePresence>
    {expanded && <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      <Details />
    </motion.div>}
  </AnimatePresence>
</motion.div>
```

**Impact:** Medium — better progressive disclosure.
**Reduced-motion:** Instant expand/collapse.

---

### T2-11: Drag-to-Reorder Workflow Steps

**Where:** Workflow Builder (step ordering)
**What:** Drag and drop with smooth animations — picked item lifts with shadow, gap opens where item will drop, spring settle on release.
**Reference:** Linear kanban, Notion drag-and-drop.

Uses `@dnd-kit/core` + Framer Motion for animations.

**Impact:** High for workflow builder — essential interaction pattern.
**Reduced-motion:** Instant reposition.

---

### T2-12: Breadcrumb Path Animation

**Where:** Header breadcrumb (Company > Project > Session)
**What:** New breadcrumb segment slides in from right, old ones compress.
**Reference:** Factory.ai navigation.

**Impact:** Low — subtle navigation feedback.
**Reduced-motion:** Instant.

---

### T2-13: Selection/Multi-Select Animation

**Where:** Tool selection in workflow config, MCP selection, Agent selection
**What:** Selected items bounce slightly + checkmark animates in (draw path).

**Impact:** Low-Medium — satisfying selection feedback.
**Reduced-motion:** Instant check.

---

### T2-14: Resizable Panel Snap Points

**Where:** Session View (file tree | terminal split)
**What:** When resizing, panel snaps to predefined widths with spring animation. Double-click divider to toggle collapse/expand.
**Reference:** VS Code panel resizing.

**Impact:** Medium — better panel management UX.
**Reduced-motion:** Instant snap.

---

### T2-15: Empty State Illustration Animation

**Where:** All empty states (no artifacts, no workflows, no sessions)
**What:** Simple CSS animation on empty state icon/illustration — gentle float or bob.

```css
@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-8px); }
}
.empty-illustration { animation: float 3s ease-in-out infinite; }
```

**Impact:** Low — adds personality to empty states.
**Reduced-motion:** Static.

---

## Tier 3 — GSAP / Canvas / Rive (Medium Dependencies)

Estimated effort: 1-2 weeks per item. Requires GSAP (~25 KB) or Rive (~160 KB).

### T3-01: Workflow Pipeline Visualization

**Where:** Workflow Run detail view (replaces or augments current Stepper)
**What:** Animated horizontal/vertical pipeline where data "flows" between steps. Each node (step) has its state visualized. Lines animate as data moves from one step to the next. When a step completes, a "pulse" travels down the pipe to the next step.
**Reference:** Factory.ai hero "conveyor belt" animation, GitHub Actions visualization.

Tech: GSAP timeline + SVG paths. Each step is an SVG node, connectors are animated SVG `<path>` elements with `stroke-dashoffset` animation.

```
[Step 1: PRD] ──pulse──> [Step 2: Tasks] ──pulse──> [Step 3: Code] ──pulse──> [Step 4: Review]
   ✅ done          🔵 running           ○ pending          ○ pending
```

When Step 2 completes, a glowing dot travels along the path to Step 3.

**Impact:** Very High — transforms workflow from static list to living visualization. This is Aixle's unique differentiator.
**Reduced-motion:** Static stepper with colors only.

---

### T3-02: Session Activity Timeline (Canvas 2D)

**Where:** Project Overview tab, Analytics section
**What:** GitHub-style contribution heatmap but for AI agent sessions. Grid of cells colored by activity intensity (sessions per day/hour). Hover shows tooltip with details.
**Reference:** GitHub contributions graph.

Tech: Canvas 2D for performance (potentially hundreds of cells), hover detection via mouse position math.

**Impact:** Medium — great for analytics/overview pages.
**Reduced-motion:** Static render, no hover animation.

---

### T3-03: Real-Time Cost Ticker

**Where:** StatusBar during active session
**What:** Smooth-rolling number display that updates as tokens are consumed. Digits roll like a mechanical counter (slot machine effect) with blur between transitions.
**Reference:** Stock ticker displays, Vercel bandwidth counters.

Tech: GSAP `to` with custom number formatter, or Framer Motion `useSpring`.

**Impact:** High — makes cost tracking feel live and urgent.
**Reduced-motion:** Instant number update.

---

### T3-04: Sticky Scroll Feature Showcase

**Where:** Onboarding flow, Future marketing/landing page
**What:** Left panel stays fixed with title/description, right panel shows different content cards that swap on scroll. Each scroll "snap" reveals a new feature with its own animation.
**Reference:** Factory.ai "Droids meet you wherever you work" section (5 steps with sticky left + animated cards right).

Tech: GSAP ScrollTrigger + pinning.

Aixle adaptation: showcase agent types (Claude Code → Cursor CLI → Codex → Gemini CLI) with each card showing the agent's unique interface.

**Impact:** Medium (for onboarding) — wow-factor for new users.
**Reduced-motion:** Simple stacked cards without scroll-pinning.

---

### T3-05: Animated Graph — Agent Usage Over Time

**Where:** Analytics tab
**What:** Line chart that draws itself from left to right when entering viewport. Data points pop in with slight delay. Hover reveals crosshair + tooltip.
**Reference:** Vercel analytics, Linear insights.

Tech: Canvas 2D or SVG + GSAP for draw animation. Or use a charting library (recharts/nivo) with custom enter animations.

**Impact:** Medium — analytics feel more engaging.
**Reduced-motion:** Static chart render.

---

### T3-06: Terminal Boot Sequence Animation

**Where:** Session View — while container is starting
**What:** Simulated terminal boot: lines appear one by one with terminal-green text, showing real status messages ("Pulling image...", "Creating container...", "Injecting credentials...", "Starting agent..."). Each line types out, then gets a ✅ when complete.
**Reference:** Factory.ai terminal prompt style, Vercel deployment logs.

Tech: Staged typewriter effect + real WebSocket status events from backend.

```
> Pulling image claude-code:latest... ✅
> Creating container... ✅
> Injecting credentials... ✅
> Starting agent... 🔵
  Connecting to terminal...
  |
```

**Impact:** Very High — transforms "loading spinner" into an informative, engaging experience. Users see exactly what's happening. Combines real data with animation.
**Reduced-motion:** Static log lines appearing instantly.

---

### T3-07: Rive Interactive Mascot/Logo

**Where:** Loading states, Onboarding, Error pages, Empty states
**What:** Interactive animated Aixle logo (Palladium shield/anchor concept) that reacts to cursor movement, loading progress, or application state. Different states: idle (gentle float), loading (spinning/pulsing), error (shake), success (celebration).
**Reference:** Factory.ai snowflake logo animation.

Tech: Rive with state machine. One `.riv` file with multiple animation states. React component switches states based on app state.

**Impact:** Medium — strong branding, memorable personality. But requires designer to create the Rive file.
**Reduced-motion:** Static logo.

---

### T3-08: Scroll-Driven Progress Indicator

**Where:** Long-form content pages (PRD viewer, documentation, workflow detail)
**What:** Thin progress bar at top of page that fills as user scrolls. Optionally: section markers on the bar showing document structure.
**Reference:** Medium article progress bar.

Tech: Scroll event + CSS `scaleX` transform on a fixed element.

**Impact:** Low-Medium — helpful for long content.
**Reduced-motion:** Static, still show position.

---

### T3-09: Animated Donut/Ring Charts

**Where:** Analytics — cost breakdown, token distribution per agent
**What:** Donut chart segments animate in (draw arc from 0 to target angle) with stagger per segment. Hover enlarges segment.
**Reference:** GitHub repo language breakdown.

Tech: SVG arc paths + GSAP or CSS animation.

**Impact:** Medium — better analytics visualization.
**Reduced-motion:** Static chart.

---

### T3-10: File Tree Expand Animation

**Where:** Session View file tree
**What:** When expanding a folder, child items slide down smoothly with stagger. Folder icon rotates (chevron turns). New files pulse briefly when they appear (created by agent).
**Reference:** VS Code file explorer.

Tech: Framer Motion layout animations or GSAP.

**Impact:** Medium — file tree feels responsive and spatial.
**Reduced-motion:** Instant expand.

---

### T3-11: Artifact Provenance Path Animation

**Where:** Artifact detail view
**What:** Visual "path" showing artifact origin: `Workflow → Step → Agent → Session → Artifact`. Each node appears sequentially connected by animated lines. Clicking a node navigates to that entity.
**Reference:** Factory.ai pipeline concept, adapted to artifact lineage.

Tech: SVG + GSAP timeline.

```
[Workflow: PRD Creation] ──> [Step 3: Draft] ──> [Agent: Claude Code] ──> [Session #42] ──> 📄 prd.md
```

**Impact:** High — provenance is Aixle's differentiator. Making it animated and interactive elevates it from "metadata" to "experience".
**Reduced-motion:** Static breadcrumb path.

---

### T3-12: Notification Stream Animation

**Where:** Notifications panel/dropdown
**What:** New notifications slide in from top, pushing others down. Real-time updates animate in without jarring the list.
**Reference:** Slack notification behavior.

Tech: Framer Motion `AnimatePresence` + `layout` on list items.

**Impact:** Medium — smooth notification experience.
**Reduced-motion:** Instant insert.

---

### T3-13: Confetti/Celebration on Workflow Completion

**Where:** Workflow Run view — when all steps complete successfully
**What:** Brief confetti or sparkle animation when a workflow finishes. Subtle, not overwhelming — few particles + auto-dismiss in 2 seconds.
**Reference:** GitHub Actions green checkmark moment, Notion page creation.

Tech: Canvas 2D particle system (custom, ~50 lines) or `canvas-confetti` library (~5 KB).

**Impact:** Low-Medium — delightful micro-moment. Reinforces satisfaction emotion from UX spec.
**Reduced-motion:** Green checkmark with subtle glow, no particles.

---

### T3-14: Animated Status Transitions

**Where:** TerminalSession state changes (not_started → running → ready → finished)
**What:** When session status changes, the status chip morphs smoothly: color transitions, icon changes with crossfade, optional ripple effect outward.

```
○ Not Started → [morph] → 🔵 Running → [morph] → ✅ Ready → [morph] → ✓ Finished
```

Tech: Framer Motion `AnimatePresence` + custom variants per state.

**Impact:** High — status changes are key moments, making them feel significant.
**Reduced-motion:** Instant chip swap.

---

### T3-15: Parallax Depth on Dashboard Cards

**Where:** Projects Dashboard
**What:** Subtle parallax tilt on project cards based on mouse position (3D card effect). Card tilts slightly toward cursor, creating depth illusion.
**Reference:** Apple product cards, Stripe dashboard.

Tech: Mouse event → `transform: perspective(1000px) rotateX(Xdeg) rotateY(Ydeg)`.

**Impact:** Low — premium feel, but can be distracting for daily use. Consider: enable only for first-time visitors or on landing page.
**Reduced-motion:** No tilt.

---

## Tier 4 — Three.js / WebGL (Heavy Dependencies)

Estimated effort: 1-3 weeks per item. Requires react-three-fiber (~150 KB).
Consider: landing page only, lazy-loaded, not in main app bundle.

### T4-01: 3D Agent Network Graph

**Where:** Company Overview / Architecture visualization
**What:** Interactive 3D force-directed graph showing relationships:
- **Nodes:** Agents (colored by type), Tools (hexagonal), MCPs (diamond), Projects (square)
- **Edges:** Connections between them (agent uses tool, project has MCP)
- **Interaction:** Rotate, zoom, click node to navigate
- **Animation:** Nodes gently orbit, edges pulse when active

**Reference:** Observed Three.js r182 on Factory.ai.

Tech: react-three-fiber + @react-three/drei + force simulation.

**Impact:** High visual impact — "wow" factor for demos and enterprise prospects. Low daily utility.
**Reduced-motion:** Static 2D graph (d3-force).
**Recommendation:** Landing page / marketing only. Lazy load.

---

### T4-02: Globe Visualization for Distributed Agents

**Where:** Analytics / Company overview (if multi-region support added)
**What:** Rotating 3D globe showing where agent sessions are running (data centers). Arcs connect user locations to compute locations.
**Reference:** Vercel globe visualization, GitHub Copilot globe.

Tech: react-three-fiber + globe geometry + point markers.

**Impact:** Medium — impressive visualization, but only useful with multi-region.
**Reduced-motion:** Static world map.
**Recommendation:** Future, when multi-region is real.

---

### T4-03: Particle Background Canvas

**Where:** Login page, Dashboard background (very subtle)
**What:** Floating particles/dots that drift slowly, react to cursor proximity (repel/attract). Connected by thin lines when close to each other (constellation effect).
**Reference:** Factory.ai background particles, common in tech sites.

Tech: Canvas 2D (actually — Three.js is overkill for this). `requestAnimationFrame` loop with ~100 particles.

**Impact:** Low — atmosphere/mood only. Can feel "2018" if overdone.
**Reduced-motion:** Static or no particles.
**Recommendation:** Login page only, very subtle (opacity: 0.1-0.2).

---

### T4-04: Container Lifecycle 3D Visualization

**Where:** Admin panel / Debug view
**What:** 3D representation of container lifecycle phases (pull → create → start → exec → cleanup) as a pipeline of 3D objects. Containers are visualized as boxes moving through phases.

**Impact:** Low daily utility — cool for demos/debugging.
**Reduced-motion:** 2D phase diagram.
**Recommendation:** Experimental/demo only.

---

### T4-05: WebGL Shader Background

**Where:** Login page, Hero section of landing page
**What:** Animated gradient shader — smooth flowing colors that shift over time. Not interactive, just atmospheric. Similar to Apple's iOS mesh gradient but animated.
**Reference:** Vercel hero gradient, Stripe gradient backgrounds.

Tech: Simple fragment shader, minimal geometry (fullscreen quad).

**Impact:** Low — atmosphere only. But very premium looking.
**Reduced-motion:** Static gradient.
**Recommendation:** Landing/login only.

---

## Tier 5 — Interaction Design Patterns (No Specific Library)

These are interaction patterns, not animations per se, but they create motion and responsiveness.

### T5-01: Optimistic UI Updates

**Where:** All CRUD operations (create workflow, add tool, save config, delete session)
**What:** UI updates immediately before server confirms. If server rejects, roll back with shake animation + error toast.

**Impact:** Very High — app feels instant. Combined with T1-09 (toast) and T3-14 (status morph).

---

### T5-02: Keyboard Shortcut Hints

**Where:** Buttons, menu items, Command Palette entries
**What:** Keyboard shortcut badges that fade in after cursor hovers for 1 second. On key press, the triggered UI element briefly highlights.
**Reference:** Raycast shortcut hints, VS Code keybindings.

**Impact:** Medium — trains keyboard usage, power-user feel.

---

### T5-03: Smart Loading Waterfall

**Where:** Any page with multiple data sources
**What:** Instead of single loading state, show content as it arrives: skeleton → header arrives → tabs appear → list items stagger in. Each section transitions independently.

**Impact:** High — perceived performance dramatically improves.

---

### T5-04: Cursor-Following Context Menu

**Where:** Right-click context menus
**What:** Context menu appears at cursor position with spring animation (scale from 0.9 to 1.0). Sub-menus slide out smoothly.
**Reference:** Linear right-click menus, macOS context menus.

**Impact:** Low-Medium — platform-native feel.

---

### T5-05: Infinite Scroll with Fade-In

**Where:** Long lists (session logs, terminal output, artifact lists)
**What:** New items load and fade in at bottom as user scrolls. Loading indicator at bottom is a skeleton row, not a spinner.

**Impact:** Medium — smooth data loading experience.

---

### T5-06: Command Palette with Fuzzy Search Animation

**Where:** Cmd+K Command Palette
**What:** Results animate as search query changes — items that no longer match shrink out, new matches slide in, remaining items reorder smoothly.
**Reference:** Raycast command palette, VS Code command palette.

Tech: Framer Motion `AnimatePresence` + `layout` on results list.

**Impact:** High — Command Palette is a core interaction, smooth filtering makes it feel magical.
**Reduced-motion:** Instant filter results.

---

### T5-07: Real-Time Presence Indicators

**Where:** Workflow Run view, Project Overview
**What:** Avatar bubbles showing who is currently viewing the same page. Avatars fade in/out smoothly as people join/leave. Cursor-like indicators for collaborative awareness.
**Reference:** Figma multiplayer cursors, Google Docs presence.

Tech: ActionCable (already in stack) + Framer Motion for avatar enter/exit.

**Impact:** Medium-High — collaborative awareness is a Aixle differentiator.
**Reduced-motion:** Static avatar list.

---

### T5-08: Session Reconnection Animation

**Where:** Session View — when WebSocket reconnects
**What:** When connection drops: overlay with "Reconnecting..." text + connecting dots animation (·· → ··· → ····). On reconnect: overlay dissolves, terminal resumes.

**Impact:** Medium — critical for perceived reliability.
**Reduced-motion:** Static text.

---

---

## Implementation Priority Matrix

| ID | Name | Tier | Impact | Effort | Priority |
|----|------|------|--------|--------|----------|
| T1-01 | Status Pulse | T1 | High | 1h | **P0** |
| T1-02 | Card Hover Lift | T1 | Medium | 1h | **P0** |
| T1-03 | Scroll Fade-In | T1 | High | 2h | **P0** |
| T1-04 | Skeleton Shimmer | T1 | High | 3h | **P0** |
| T1-05 | Tab Transitions | T1 | Medium | 2h | **P0** |
| T1-09 | Toast Slide-In | T1 | Medium | 1h | **P0** |
| T1-13 | Progress Bar | T1 | Medium | 1h | **P0** |
| T1-15 | Cursor Blink | T1 | Medium | 30m | **P0** |
| T2-01 | Route Transitions | T2 | High | 4h | **P1** |
| T2-02 | Staggered Lists | T2 | High | 3h | **P1** |
| T2-03 | Number Counter | T2 | High | 3h | **P1** |
| T2-05 | Modal Animation | T2 | Medium | 2h | **P1** |
| T2-07 | Typewriter Effect | T2 | High | 2h | **P1** |
| T2-09 | Stepper Connectors | T2 | High | 4h | **P1** |
| T3-01 | Pipeline Visualization | T3 | Very High | 2w | **P2** |
| T3-06 | Terminal Boot Sequence | T3 | Very High | 1w | **P1** |
| T3-11 | Provenance Path | T3 | High | 1w | **P2** |
| T3-14 | Status Transitions | T3 | High | 3d | **P1** |
| T5-01 | Optimistic UI | T5 | Very High | 1w | **P1** |
| T5-03 | Loading Waterfall | T5 | High | 3d | **P1** |
| T5-06 | Command Palette Filter | T5 | High | 3d | **P2** |
| T5-07 | Presence Indicators | T5 | Medium-High | 1w | **P2** |

### Phase Plan

**Phase 0 — Foundation (1-2 days):**
All T1 items (P0). Zero dependencies, pure CSS. Immediately elevates perceived quality.

**Phase 1 — Core Motion (1 week):**
Add Framer Motion. Implement T2-01, T2-02, T2-03, T2-05, T2-07, T2-09. Plus T3-06 (Terminal Boot) and T3-14 (Status Transitions). Implement T5-01 (Optimistic UI) and T5-03 (Loading Waterfall).

**Phase 2 — Differentiators (2-3 weeks):**
T3-01 (Pipeline Visualization), T3-11 (Provenance Path), T5-06 (Command Palette), T5-07 (Presence). These are Aixle's unique animations.

**Phase 3 — Polish (ongoing):**
Remaining T2/T3 items as time allows. T1-06 through T1-14.

**Phase 4 — Marketing/Landing (when needed):**
T4 items, T3-04 (Sticky Scroll), T3-07 (Rive Mascot). Only for public-facing pages. Lazy-loaded, not in main bundle.

---

## Global Animation Guidelines

### Duration Standards

| Animation Type | Duration | Easing |
|----------------|----------|--------|
| Micro (hover, focus) | 100-200ms | ease |
| Standard (fade, slide) | 200-300ms | ease-out |
| Complex (layout, route) | 300-500ms | ease-in-out |
| Emphasis (celebration, boot) | 500-1000ms | custom spring |
| Continuous (pulse, float) | 1-3s | ease-in-out, infinite |

### Spring Defaults (Framer Motion)

```tsx
const springs = {
  snappy: { type: "spring", stiffness: 300, damping: 30 },
  gentle: { type: "spring", stiffness: 200, damping: 25 },
  bouncy: { type: "spring", stiffness: 400, damping: 20 },
};
```

### Accessibility (prefers-reduced-motion)

Every animation MUST have a reduced-motion fallback:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

In React, use a hook:

```tsx
function usePrefersReducedMotion() {
  const [prefersReduced, setPrefersReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    setPrefersReduced(mq.matches);
    const handler = (e) => setPrefersReduced(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);
  return prefersReduced;
}
```

### Performance Budget

| Metric | Target |
|--------|--------|
| Animation JS bundle (additional) | < 50 KB gzipped |
| Max concurrent animations | 3-5 |
| Frame rate | 60 fps minimum |
| Main thread blocking | < 16ms per frame |
| Canvas elements per page | ≤ 2 |

### Theme Integration

All animation colors must reference theme tokens, not hardcoded values:

```tsx
const theme = useTheme();
// ✅ Do:
animate={{ borderColor: theme.palette.primary.main }}
// ❌ Don't:
animate={{ borderColor: '#3B82F6' }}
```

---

## References

| Source | URL | Key Takeaway |
|--------|-----|-------------|
| Factory.ai | https://factory.ai | GSAP + Three.js + Rive, conveyor animation, sticky scroll carousel |
| Linear | https://linear.app | Clean transitions, staggered lists, keyboard-first, isometric illustrations |
| Vercel | https://vercel.com | Gradient shaders, globe viz, analytics counters, deployment log animation |
| GitHub | https://github.com | Actions workflow viz, contribution heatmap, PR timeline |
| Raycast | https://raycast.com | Command palette animation, instant feel, spring physics |
