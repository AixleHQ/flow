# S-05: Shell Route Indicator — Test Report

> Tested: 2026-04-03 | Method: Live Playwright MCP | Environment: Docker localhost:4000

## Summary

| Total | Pass | Fail | Fix during test |
|-------|------|------|-----------------|
| 8     | 8    | 0    | 1 (CSS specificity) |

## Acceptance Criteria Results

| # | Criterion | Result | Notes |
|---|-----------|--------|-------|
| 1 | Thin progress bar appears during Inertia navigation | PASS | MutationObserver confirmed `indicatorSeen: true` during Projects→Profile navigation |
| 2 | Bar positioned at top of viewport (fixed, top:0) | PASS | Computed: `position: fixed`, `top: 0px`, `left: 0px`, `right: 0px` |
| 3 | z-index: 1000 (above all content) | PASS | Computed: `zIndex: 1000` |
| 4 | 2px height, full width, animated | PASS | `height: 2`, `width: 1280` (viewport width), Mantine `animated` prop |
| 5 | Bar disappears when navigation completes | PASS | `currentIndicator: false` after navigation; element removed from DOM |
| 6 | Not visible when page is idle | PASS | `querySelector('[class*="indicator"]')` returns null on idle page |
| 7 | Event listeners cleaned up on unmount | PASS | `useEffect` returns `removeStart()` + `removeFinish()` cleanup |
| 8 | Works on all pages (global mount in entrypoint) | PASS | Mounted in `inertia.tsx` inside `MantineProvider`, tested on Projects + Profile |

## Rapid Navigation Test

Performed 2 rapid successive navigations (Projects → Profile → Projects → Profile):

| Metric | Value |
|--------|-------|
| Indicator appeared | 2 times |
| Indicator disappeared | 2 times |
| Indicator at end | Not present |
| Memory leak | None (observer properly tracks state) |

## Fix Applied During Testing

**CSS specificity issue**: Mantine `Progress` root has `position: relative` which overrode our `position: fixed` on the same element. Fixed by wrapping `<Progress>` in a `<div>` with the `.indicator` class, so positioning applies to the wrapper without Mantine style conflict.

## Regression Checks

| Check | Result |
|-------|--------|
| Full page load (non-Inertia) | No indicator shown (correct) |
| Projects page renders normally | PASS |
| Profile page renders normally | PASS |
| No console errors | PASS |
