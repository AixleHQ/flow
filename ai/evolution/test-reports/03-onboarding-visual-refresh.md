# Test Report: S-03 Onboarding Visual Refresh

> **Tested:** 2026-04-03
> **Spec:** `ai/evolution/specs/03-onboarding-visual-refresh.md`
> **Method:** Live Playwright MCP (separate browser context, user test@test.com, company "Test")
> **Environment:** Docker dev (localhost:4000)

---

## Summary

**13/14 criteria passed.** 1 fix applied during testing (color bar CSS specificity).

---

## Results

| # | Criterion | Steps | Expected | Actual | Pass? |
|---|-----------|-------|----------|--------|-------|
| 1 | Company name in welcome | Navigate to /onboarding | "Welcome to {companyName}!" | "Welcome to Test!" | ✅ |
| 2 | Company logo (if present) | Login as Dualboot user | Logo image above welcome | Dualboot Partners logo shown | ✅ |
| 2b | No logo when absent | Login as Test user | No logo, company name still shown | Correct — no logo, "Welcome to Test!" | ✅ |
| 3 | Gradient background | Visual check | Radial gradient visible | Dark-7→dark-9 gradient confirmed | ✅ |
| 4 | Card fadeSlideUp animation | Page load | Card fades in and slides up | Animation renders on load | ✅ |
| 5 | Auto-save Step 1 | Change Position → check DB | position saved after 300ms | DB: position="dev", lang="en" | ✅ |
| 6 | Auto-save Step 2 | Toggle agents → check DB | agents saved after 300ms | DB: ["claude_code","cursor_cli"] | ✅ |
| 7 | 4 agents listed | View Step 2 | Claude Code, Cursor CLI, Codex, Gemini CLI | All 4 visible in 2-column grid | ✅ |
| 8 | Agent cards with color bars | Inspect borderLeftColor | Left border = agent theme color | ✅ after fix (see Issues) |
| 9 | Validation Step 1 | Click Continue without fields | Yellow warning | "⚠ Please fill in all required fields" | ✅ |
| 10 | Validation Step 2 | Click Continue without agents | Yellow warning | "⚠ Select at least one agent" | ✅ |
| 11 | Step 4 agent summary cards | Navigate to Step 4 | Cards with color bars and auth badges | Orange/purple bars + yellow "NOT AUTHENTICATED" | ✅ |
| 12 | Step transition animation | Navigate between steps | Fade on step change | Card re-animates on each step | ✅ |
| 13 | SharedProps types used | Code review | No local type duplication | Imports AgentType, SharedProps from shared/ui-inertia | ✅ |
| 14 | Reduced motion respected | Emulate prefers-reduced-motion | animationName = "none" | Confirmed: animation: none | ✅ |

---

## Issues Found

### 1. Color bar CSS specificity (FIXED)

**Severity:** Medium (visual)
**Description:** Mantine `Card withBorder` sets `border` shorthand via CSS which overrides inline `borderLeft` style. All agent cards showed the default gray border instead of agent color.
**Fix:** Added `border-left-width: 4px !important; border-left-style: solid !important;` to `.agentCard` CSS module class. Changed inline style from `borderLeft` to `borderLeftColor`.
**Status:** Fixed and verified.

### 2. Auto-save via fetch (FIXED pre-test)

**Severity:** High (functional)
**Description:** Original auto-save used `router.patch` which triggers Inertia redirect cycle, causing page re-render and form state loss.
**Fix:** Changed to plain `fetch` with CSRF token — saves data without triggering Inertia redirect.
**Status:** Fixed and verified.

---

## Edge Cases Verified

| Case | Result |
|------|--------|
| Company without logo | ✅ Logo hidden, company name displayed |
| Complete with no auth agents | ✅ AASM guard prevents completion (expected) |
| User refresh mid-step | ✅ Backend state preserved |
| Reduced motion | ✅ All animations disabled |

---

## Recommendation

**Pass.** All 14 acceptance criteria met. 2 issues found and fixed during testing.
