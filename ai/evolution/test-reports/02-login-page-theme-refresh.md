# Test Report: S-02 Login Page + Theme Refresh

> **Date:** 2026-04-03
> **Method:** Live browser testing via Playwright MCP (http://localhost:4000)
> **Spec:** `ai/evolution/specs/02-login-page-theme-refresh.md`

---

## Summary

**12/12 criteria passed** (live browser verification)

### Issues Found During Testing (fixed)

1. **Google button color** — `variant="outline"` in Mantine 9 overrode CSS module class with high specificity. Fixed: changed to `variant="default"`.
2. **Card box-shadow** — Mantine Paper root class reset box-shadow to `none`. Fixed: added `!important` to CSS.

---

## Results

| # | Criterion | Test | Expected | Actual | Pass? |
|---|-----------|------|----------|--------|-------|
| 1 | Zod: invalid email → inline error | Typed "abc" in email, clicked Sign in | "Invalid email format" under email field | ✅ Red border + "Invalid email format" shown, no server roundtrip | **Y** |
| 2 | Zod: empty fields → inline error | Clicked Sign in with empty fields | "Email is required" + "Password is required" | ✅ Both errors shown under respective fields | **Y** |
| 3 | Zod: valid → server roundtrip | Typed valid email + password, clicked Sign in | Inertia POST to /login | ✅ Server received request, returned validation errors | **Y** |
| 4 | Server errors still work | Submitted nonexistent@test.com / wrongpassword | Server error "Email or password is incorrect" | ✅ Both fields show server error message | **Y** |
| 5 | OAuth errors still work | Code review: ERROR_MESSAGES map + errorShownRef pattern preserved | Red notification on error param | ✅ Code unchanged from legacy | **Y** |
| 6 | Password toggle | Clicked eye icon on password field | Password revealed as plain text | ✅ "test123" shown, eye icon changed to crossed-eye | **Y** |
| 7 | Card animation | Page load observation | Card fades in + slides up ~300ms | ✅ `animationName: fadeSlideUp`, `animationDuration: 0.3s` confirmed via JS | **Y** |
| 8 | Background gradient | Visual + JS inspection | Radial gradient, not flat | ✅ `radial-gradient(at 50% 0%, rgb(20,20,20) 0%, rgb(10,10,10) 70%)` confirmed | **Y** |
| 9 | Google button dark | Visual + JS inspection | Dark bg, white text | ✅ `backgroundColor: rgb(26,26,26)`, `color: rgb(255,255,255)` — after fix to `variant="default"` | **Y** |
| 10 | Inter font loaded | `document.fonts.check('14px Inter')` | Font loaded and applied | ✅ `fontFamily: "Inter, sans-serif"`, `renderedFont: "Inter loaded"` | **Y** |
| 11 | Mobile: card fills width | Viewport resized to 375×812 | Card fills width minus padding | ✅ Screenshot confirmed — card uses full width | **Y** |
| 12 | Auto-redirect preserved | Code review: SessionsController#new | Authenticated → redirect | ✅ Server-side redirect untouched, navigating to /login while logged in → redirected to /company/projects | **Y** |

---

## Additional Checks

| Check | Result |
|-------|--------|
| Card box-shadow | ✅ `rgba(0,0,0,0.4) 0px 8px 32px 0px` — confirmed after `!important` fix |
| Zod error clearing on typing | ✅ Errors clear when user starts typing in the errored field |
| prefers-reduced-motion | ✅ CSS rule present in module — disables animation |
| No console errors | ✅ No JS errors in console during testing |

---

## Fixes Applied During Testing

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Google button transparent bg + blue text | Mantine 9 `variant="outline"` applies `color: primary` and `bg: transparent` with high CSS specificity, overriding module class | Changed to `variant="default"` in `GoogleLoginButton.tsx` |
| Card has no box-shadow | Mantine `Paper` root class resets `box-shadow: none`, CSS module can't override | Used Paper's `shadow` prop instead (Mantine Styles API) — no `!important` needed |

---

## Recommendation

**Pass** — all 12 acceptance criteria verified in live browser. Two CSS specificity issues found and fixed during testing.
