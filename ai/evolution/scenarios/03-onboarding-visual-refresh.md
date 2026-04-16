# S-03: Onboarding Visual Refresh

> **Priority:** Medium (UX + feature parity)
> **Size:** M
> **Created:** 2026-04-03
> **Analysis source:** `ai/evolution/analysis/page-by-page-evolution.md`, section 3
> **Legacy spec:** `ai/epics/legacy-spa-detailed-spec.md`, section 3

---

## Target

Bringing the Onboarding page up to feature parity with the legacy MUI version and visual consistency with the updated Login page (S-02). Company branding, auto-save, animations, validation, agent cards with color bars, adding Gemini CLI.

---

## Current State

### What exists (Inertia / Mantine)
1. 4-step Stepper with AASM backend (step1 → step4 → completed)
2. Step 1: Profile — Position + Language Select
3. Step 2: Agent selection — 3 agent cards (SimpleGrid), checkboxes
4. Step 3: Authenticate — split layout (agent list 280px + terminal iframe)
5. Step 4: Summary — position, language, agent badges
6. Server redirect to `/onboarding` if not completed

### Issues
1. **Generic branding** — "Welcome to the Platform" instead of company name + logo
2. **Flat visuals** — no gradient bg, no card animation (Login is already updated)
3. **No auto-save** — data is saved only when Continue is clicked
4. **3 agents** instead of 4 — no Gemini CLI
5. **Agent cards without color bars** — no visual distinction between agents
6. **No validation warnings** — errors are not shown inline
7. **Step 4 is sparse** — just text + badges, no agent summary cards
8. **No transition animation** — steps switch instantly
9. **Local types** — duplicate SharedUser/SharedCompany from shared/ui-inertia/types

---

## Desired State

1. **Company branding** — logo (if available) + "Welcome to {companyName}!" + subtitle
2. **Gradient background** — radial gradient like on Login (dark-7 → dark-9)
3. **Card animation** — fadeSlideUp on mount of each step
4. **Auto-save** — debounced 300ms `router.patch` on field changes (Step 1, Step 2)
5. **4 agents** — Claude Code, Cursor CLI, Codex, Gemini CLI
6. **Agent cards with color bars** — left border in the agent's color, hover effect
7. **Inline validation** — "Please fill in all required fields" / "Select at least one agent"
8. **Step 4 redesign** — agent summary cards with color bars and auth status
9. **Step transition** — CSS fade/slide when switching steps
10. **SharedProps** — use types from `shared/ui-inertia/types`

---

## User Journey

### Entry Point
- User logs in → redirect to `/onboarding` (if onboarding_state ≠ completed)
- Or the direct URL `/onboarding`

### Current Flow
1. A generic "Welcome to the Platform" appears instantly
2. Stepper without a progress bar
3. Step 1 → Step 2 → Step 3 → Step 4 → redirect

### Pain Points
- Faceless welcome — does not create a sense of belonging to the company
- Visual flatness — differs from the Login page
- No feedback on field changes (saved or not)
- No Gemini CLI — the user cannot select it

### Proposed Flow
1. The page appears with a gradient background and an animated card
2. Welcome section with company logo + name
3. Step 1: auto-save on field changes, validation warnings
4. Step 2: 4 agent cards with color bars, auto-save selections
5. Step 3: unchanged (already works with terminal)
6. Step 4: summary cards with color bars + auth badges

---

## Success Criteria

| # | Criterion | How to verify |
|---|----------|---------------|
| 1 | Company name in welcome | We see "Welcome to {companyName}!" |
| 2 | Company logo (if present) | Logo is displayed above the welcome text |
| 3 | Gradient background | Radial gradient, not flat |
| 4 | Card fadeSlideUp animation | Card appears smoothly on load |
| 5 | Auto-save Step 1 | Change Position -> after 300ms `router.patch` |
| 6 | Auto-save Step 2 | Toggle agent -> after 300ms `router.patch` |
| 7 | 4 agents in the list | Claude Code, Cursor CLI, Codex, Gemini CLI |
| 8 | Agent cards with color bars | Left border = agent color |
| 9 | Inline validation Step 1 | Click Continue with no fields -> warning |
| 10 | Inline validation Step 2 | Click Continue with no agents -> warning |
| 11 | Step 4 agent summary cards | Cards with color bars, auth badges |
| 12 | Step transition animation | Fade when switching steps |
| 13 | SharedProps types | No type duplication, SharedUser is used |
| 14 | Reduced motion | Animations are disabled when `prefers-reduced-motion` |

---

## Scope

### Pages Affected
- `app/frontend/pages-inertia/Onboarding/OnboardingPage.tsx`

### New Files
- `app/frontend/pages-inertia/Onboarding/OnboardingPage.module.css`

### Components Touched
| Component | Change |
|-----------|--------|
| `OnboardingPage` | Rewrite: SharedProps, company branding, auto-save, validation, 4 agents, animations |
| `OnboardingPage.module.css` | New: gradient bg, card animation, agent cards, step transitions |

### Data Changes
- **No.** The backend controller does not change. Company data is already available via `inertia_share` (`current_user.company`).

### Dependencies
- `@mantine/core` — all components are already available
- `shared/ui-inertia/types` — SharedUser, SharedCompany, SharedProps

### Risk Level
**Low** — frontend-only, visual changes + UX. The backend does not change.
