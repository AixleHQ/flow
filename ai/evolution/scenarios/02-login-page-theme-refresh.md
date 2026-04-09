# S-02: Login Page + Theme Refresh

> **Priority:** Low (visual-only, no behavior change)
> **Size:** S
> **Created:** 2026-04-03
> **Analysis source:** `ai/evolution/analysis/page-by-page-evolution.md`, section 2
> **Legacy spec:** `ai/epics/legacy-spa-detailed-spec.md`, section 2

---

## Target

Bringing the Login page to feature parity with the legacy MUI and applying UX improvements: gradient background, password visibility toggle, form appearance animation, client-side Zod validation, theme update (component proportions and colors).

---

## Current State

### What exists (Inertia / Mantine)

1. **Page** `Auth/LoginPage.tsx` (116 LOC) — full-screen `Center` with `Paper` max-width 420px
2. **Elements:** Logo, GoogleLoginButton (white outlined), "OR" divider, email + password TextInputs, "Sign in" Button, footer tagline
3. **Styling:** `LoginPage.module.css` — dark background (`dark-8`), card (`dark-7`), inputs (`dark-8`, focus `blue-5`), Inter font for fields
4. **Errors:** Inertia `errors` from the server + `notifications.show()` for OAuth params
5. **Theme:** `mantineTheme.ts` — custom color tuples (blue, green, red, amber, dark), Poppins, `defaultColorScheme: "dark"`, CSS variables via `cssVariablesResolver`

### What does NOT work / is missing

| # | Gap | Source |
|---|-----|----------|
| 1 | No client-side Zod validation (email format + required fields) | Legacy spec §2 |
| 2 | No password visibility toggle | Analysis §2 UX |
| 3 | Flat dark background without visual branding | Analysis §2 UX |
| 4 | No form appearance animation | Analysis §2 UX |
| 5 | Google OAuth button is stylistically weakly emphasized (white on dark — looks out of place) | Analysis §2 UX |
| 6 | Auto-redirect on authorization — the server performs the redirect, but if it is an SPA mount with a server session — verify | Legacy spec §2 |

---

## Desired State

### After the changes the user sees:

1. **Background** — a subtle radial gradient (dark-9 → dark-8) or a CSS noise pattern that adds depth
2. **Card** — fade-in + slide-up animation on mount (CSS transition, ~300ms)
3. **Google OAuth** — visually emphasized as the primary action: fill (subtle variant or outlined with accent), hover effect
4. **Fields** — inline Zod validation (red border + message "Invalid email" / "Password is required" before server submit)
5. **Password** — eye toggle (`PasswordInput` from Mantine instead of `TextInput type=password`)
6. **Submit** — stays as is (loading state via Inertia processing)
7. **Theme** — update of `mantineTheme.ts`:
   - Add Inter as a secondary font (for body text / inputs)
   - Refine `other.background` CSS variables for the login-specific gradient
   - Card radius/shadow consistency check

---

## User Journey

### Entry Point
- The user opens `/login` (direct URL or redirect from the auth guard)
- The server checks `signed_in?` → if so, redirect to `/company/projects` or `/onboarding`
- If not — renders `Auth/LoginPage` via Inertia

### Current Flow
1. The page appears instantly (without animation) on a flat dark background
2. The user sees Logo → Google button → OR → form fields → Sign in
3. Fills in email/password → clicks Sign in
4. If there is an error — Inertia redirect with `errors` (shown under the fields)
5. If `?error=X` — notification at the top right

### Pain Points
- **Visual flatness**: the background and the card blend together, no depth
- **Google button**: white on dark — high contrast, but not aligned with dark theme guidelines
- **No inline validation**: you only learn about an email format error after a roundtrip to the server
- **Password**: no way to check that you are typing correctly

### Proposed Flow
1. The page loads → the card appears with a fade-in slide-up (300ms ease-out)
2. Background — subtle gradient, the card stands out as a "floating" element
3. Google button is visually primary (larger, accent color)
4. When entering email — instant validation (Zod: email format)
5. Password — toggle visibility, "required" validation on blur
6. Submit → Inertia POST (no changes in logic)

---

## Success Criteria

| # | Criterion | How to verify |
|---|----------|---------------|
| 1 | Zod validation of email format before submit | Enter "abc" → inline error |
| 2 | Password visibility toggle works | Click the eye icon → password visible |
| 3 | Card animation on mount | Visual check — card appears smoothly |
| 4 | Background with gradient | Visual check — not flat |
| 5 | Google button styling | Visual check — emphasized as primary |
| 6 | All legacy features preserved | OAuth error handling, server errors, redirect logic — not broken |
| 7 | Theme updated | `mantineTheme.ts` contains Inter font, refined variables |

---

## Scope

### Pages Affected
- `app/frontend/pages-inertia/Auth/LoginPage.tsx`
- `app/frontend/pages-inertia/Auth/LoginPage.module.css`
- `app/frontend/pages-inertia/Auth/GoogleLoginButton.tsx`
- `app/frontend/shared/theme/mantineTheme.ts`

### Components Touched
| Component | Change |
|-----------|--------|
| `LoginPage` | Zod schema, PasswordInput, animation class, gradient bg |
| `LoginPage.module.css` | Gradient background, card animation keyframes, updated input styles |
| `GoogleLoginButton` | Restyle: dark-theme-friendly variant, hover state |
| `mantineTheme.ts` | Add Inter fontFamily for body/inputs, review card defaults |

### Data Changes
- **No.** No changes to the API, controllers, or models. Fully frontend-only.

### Dependencies
- `zod` — already in the project (check `package.json`)
- `@mantine/core` `PasswordInput` — already available via Mantine

### Risk Level
**Low** — visual changes + client-side validation. Server logic does not change. Regression risk is minimal.

---

## Implementation Notes

### Zod Schema
```typescript
import { z } from 'zod';

const loginSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  password: z.string().min(1, 'Password is required'),
});
```

### PasswordInput (Mantine)
Replace `TextInput type="password"` with `PasswordInput` — built-in toggle visibility out of the box.

### Card Animation (CSS)
```css
@keyframes fadeSlideUp {
  from { opacity: 0; transform: translateY(16px); }
  to   { opacity: 1; transform: translateY(0); }
}

.formCard {
  animation: fadeSlideUp 0.3s ease-out;
}
```

### Background Gradient
```css
/* instead of flat dark-8 */
background: radial-gradient(ellipse at 50% 0%, var(--mantine-color-dark-7) 0%, var(--mantine-color-dark-9) 70%);
```
