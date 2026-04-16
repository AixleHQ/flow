# Login Page + Theme Refresh — Update Specification

> **Scenario:** `ai/evolution/scenarios/02-login-page-theme-refresh.md`
> **Created:** 2026-04-03
> **Risk:** Low (frontend-only, no API changes)

---

## Change Summary

Login page update: adding client-side Zod validation, replacing TextInput with PasswordInput with a visibility toggle, applying a gradient background and a card appearance animation, restyling the Google OAuth button for the dark theme, loading the Inter font in the Inertia layout and registering it in the theme.

---

## Before

```
┌──────────────────────────────────────────────────┐
│  (flat #0D0D0D background, no depth)             │
│                                                  │
│  ┌──────────────────────────────┐                │
│  │  [Logo 120px]                │                │
│  │                              │                │
│  │  ┌──────────────────────┐   │                │
│  │  │ 🔲 Sign in with Google│   │ ← white bg,    │
│  │  │    (white button)    │   │   contrastingly │
│  │  └──────────────────────┘   │                │
│  │  ─────── OR ─────────       │                │
│  │  "Enter your credentials…"  │                │
│  │                              │                │
│  │  Email                       │                │
│  │  [ you@company.com        ] │                │
│  │  Password                    │                │
│  │  [ ••••••••               ] │ ← no toggle    │
│  │                              │                │
│  │  [ Sign in ]                 │                │
│  │                              │                │
│  │  AI Agent Orchestration …    │                │
│  └──────────────────────────────┘                │
│   (card dark-7, border dark-4, appears instant)  │
└──────────────────────────────────────────────────┘
```

### Problems
1. Flat background — card and bg blend together, there is no visual depth
2. Google button — white on dark, does not fit the dark theme
3. No client-side validation — you only see an email format error after a roundtrip
4. No password visibility — you cannot check what you are typing
5. Inter font — declared in CSS, but not loaded in the Inertia layout (falls back to sans-serif)
6. The card appears without animation

---

## After

```
┌──────────────────────────────────────────────────┐
│  (radial gradient: dark-7 center → dark-9 edges) │
│                                                  │
│  ┌──────────────────────────────┐ ← fadeSlideUp  │
│  │  [Logo 120px]                │   300ms        │
│  │                              │                │
│  │  ┌──────────────────────┐   │                │
│  │  │ G  Sign in with Google│   │ ← dark button  │
│  │  │    (dark-6 bg, white) │   │   with accent  │
│  │  └──────────────────────┘   │                │
│  │  ─────── OR ─────────       │                │
│  │  "Enter your credentials…"  │                │
│  │                              │                │
│  │  Email                       │                │
│  │  [ you@company.com        ] │ ← Zod inline   │
│  │  Password                    │                │
│  │  [ ••••••••           👁 ] │ ← toggle       │
│  │                              │                │
│  │  [ Sign in ]                 │                │
│  │                              │                │
│  │  AI Agent Orchestration …    │                │
│  └──────────────────────────────┘                │
│   (card dark-7, subtle shadow, Inter loaded)     │
└──────────────────────────────────────────────────┘
```

---

## Components

### 1. `inertia.html.haml` — Add Inter font

**Change:** Add an Inter Google Font link next to Poppins.

```haml
%link{href: "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Poppins:ital,wght@0,100;0,200;0,300;0,400;0,500;0,600;0,700;0,800;0,900;1,100;1,200;1,300;1,400;1,500;1,600;1,700;1,800;1,900&display=swap", rel: "stylesheet"}/
```

**Why:** Inter is used in 30+ files with `ff='"Inter", sans-serif'`, but falls back to sans-serif. Loading it will ensure consistency.

---

### 2. `mantineTheme.ts` — Theme update

**Changes:**

| Property | Before | After |
|----------|--------|-------|
| `fontFamilyMonospace` | _(not set)_ | `'JetBrains Mono, monospace'` |
| `other.fontFamily.body` | _(not set)_ | `'Inter, sans-serif'` |

Add:
```typescript
other: {
  fontFamily: {
    body: 'Inter, sans-serif',
  },
  // ...existing keys
}
```

And in `cssVariablesResolver`:
```typescript
'--app-font-body': theme.other.fontFamily.body,
```

**Scope:** Do not change `fontFamily` (Poppins) — it is for headings and UI chrome. Inter — for body text, inputs, labels. Each component selects it itself via the CSS variable.

---

### 3. `LoginPage.module.css` — Visual refresh

**Full replacement:**

```css
/* ── Background ────────────────────────────── */
.pageBackground {
  background: radial-gradient(
    ellipse at 50% 0%,
    var(--mantine-color-dark-7) 0%,
    var(--mantine-color-dark-9) 70%
  );
}

/* ── Card ──────────────────────────────────── */
@keyframes fadeSlideUp {
  from {
    opacity: 0;
    transform: translateY(16px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.formCard {
  background-color: var(--mantine-color-dark-7);
  border: 1px solid var(--mantine-color-dark-4);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
  animation: fadeSlideUp 0.3s ease-out both;
}

/* ── Inputs ────────────────────────────────── */
.input {
  background-color: var(--mantine-color-dark-8);
  border-color: var(--mantine-color-dark-4);
  color: var(--mantine-color-gray-1);
  font-family: var(--app-font-body, 'Inter', sans-serif);
  font-size: 14px;
  padding: 12px 16px;
  height: auto;
}

.input::placeholder {
  color: var(--mantine-color-dark-2);
}

.input:focus {
  border-color: var(--mantine-color-blue-5);
}

/* PasswordInput inner toggle */
.visibilityToggle {
  color: var(--mantine-color-dark-2);
}

.visibilityToggle:hover {
  color: var(--mantine-color-gray-3);
}

/* ── Submit ────────────────────────────────── */
.submitButton {
  font-family: var(--app-font-body, 'Inter', sans-serif);
  font-size: 14px;
  font-weight: 500;
}
```

**Key changes:**
- `pageBackground` — a new class for `Center` (radial gradient instead of inline `bg`)
- `formCard` — added `box-shadow` and `animation`
- `input` — `font-family` via CSS variable
- `visibilityToggle` — styles for the eye icon in PasswordInput

---

### 4. `LoginPage.tsx` — Component updates

**4a. Zod schema + client validation**

Add:
```typescript
import { z } from 'zod';

const loginSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  password: z.string().min(1, 'Password is required'),
});
```

Add state for client-side errors:
```typescript
const [clientErrors, setClientErrors] = useState<Record<string, string>>({});
```

In `handleSubmit`:
```typescript
const handleSubmit = (e: React.FormEvent) => {
  e.preventDefault();
  const result = loginSchema.safeParse(data);
  if (!result.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of result.error.issues) {
      const field = issue.path[0] as string;
      if (!fieldErrors[field]) fieldErrors[field] = issue.message;
    }
    setClientErrors(fieldErrors);
    return;
  }
  setClientErrors({});
  post('/login', {
    onSuccess: () => {
      notifications.show({ message: 'Welcome back!', color: 'green' });
    },
  });
};
```

Displaying errors — merge server + client:
```typescript
error={clientErrors.email || errors.email}
```

Clearing on input:
```typescript
onChange={(e) => {
  setData('email', e.currentTarget.value);
  if (clientErrors.email) setClientErrors((prev) => ({ ...prev, email: undefined }));
}}
```

**4b. PasswordInput instead of TextInput**

```typescript
import { PasswordInput } from '@mantine/core';
```

Replace the password `TextInput` with:
```tsx
<PasswordInput
  label="Password"
  value={data.password}
  onChange={(e) => {
    setData('password', e.currentTarget.value);
    if (clientErrors.password) setClientErrors((prev) => ({ ...prev, password: undefined }));
  }}
  placeholder="••••••••"
  error={clientErrors.password || errors.password}
  autoComplete="current-password"
  classNames={{ input: classes.input, visibilityToggle: classes.visibilityToggle }}
  visibilityToggleButtonProps={{ 'aria-label': 'Toggle password visibility' }}
/>
```

Remove the `<Box>` + `<Text>` label wrapper for password — `PasswordInput` has a built-in `label` prop. Similarly for email — `TextInput` also supports `label`:

```tsx
<TextInput
  label="Email"
  value={data.email}
  onChange={...}
  placeholder="you@company.com"
  error={clientErrors.email || errors.email}
  autoComplete="username"
  classNames={{ input: classes.input }}
/>
```

Remove all `<Box>` + `<Text size="xs" ...>` label wrappers — use the components' native label props. Style labels via `classNames={{ label: classes.label }}` if customization is needed.

**4c. Background gradient**

Replace:
```tsx
<Center mih="100vh" bg="var(--mantine-color-dark-8)" p={32}>
```
With:
```tsx
<Center mih="100vh" className={classes.pageBackground} p={32}>
```

**4d. Remove the `ff` prop**

Remove all `ff='"Inter", sans-serif'` from `<Text>` — Inter will be applied globally via a CSS class or CSS variable. Add a label class:

```css
.label {
  font-family: var(--app-font-body, 'Inter', sans-serif);
}

.subtitle {
  font-family: var(--app-font-body, 'Inter', sans-serif);
}
```

---

### 5. `GoogleLoginButton.tsx` — Dark theme restyle

**Before:** White background (#FFFFFF), gray text (#757575) — a "light mode" button on a dark page.

**After:** Semi-transparent dark button that feels native to dark theme.

```tsx
export const GoogleLoginButton = (props: Omit<ButtonProps, 'component'>) => (
  <Button
    component="a"
    href={GOOGLE_AUTH_PATH}
    variant="outline"
    fullWidth
    size="lg"
    leftSection={<GoogleIcon />}
    classNames={{ root: classes.googleButton }}
    {...props}
  >
    Sign in with Google
  </Button>
);
```

CSS in `LoginPage.module.css`:
```css
.googleButton {
  background-color: var(--mantine-color-dark-6);
  color: var(--mantine-color-gray-1);
  border-color: var(--mantine-color-dark-4);
  font-family: var(--app-font-body, 'Inter', sans-serif);
  font-size: 14px;
  font-weight: 500;
  transition: background-color 150ms ease, border-color 150ms ease;
}

.googleButton:hover {
  background-color: var(--mantine-color-dark-5);
  border-color: var(--mantine-color-dark-3);
}
```

**GoogleLoginButton.tsx** — remove the inline `styles` prop, import `classes` from `LoginPage.module.css` (or move it to its own CSS module).

**Decision:** Move the Google button styles into `LoginPage.module.css` and pass `className` via a prop, since GoogleLoginButton already accepts ButtonProps. Or create `GoogleLoginButton.module.css`.

**Recommendation:** Use `LoginPage.module.css` — the button is used only on the login page, a separate file is not justified.

---

## Responsive Behavior

| Breakpoint | Behavior |
|-----------|----------|
| Desktop (>480px) | Card max-width 420px, centered |
| Mobile (<480px) | Card fills width minus padding 16px, `p="lg"` instead of `p="xl"` |

**Add:**
```css
@media (max-width: 480px) {
  .formCard {
    padding: var(--mantine-spacing-lg);
  }
}
```

The background gradient works on all sizes. The animation — unchanged.

---

## Files Changed (summary)

| File | Change Type |
|------|-------------|
| `app/views/layouts/inertia.html.haml` | Add Inter font link |
| `app/frontend/shared/theme/mantineTheme.ts` | Add `other.fontFamily.body` + CSS variable |
| `app/frontend/pages-inertia/Auth/LoginPage.tsx` | Zod validation, PasswordInput, remove Box/Text wrappers, gradient class |
| `app/frontend/pages-inertia/Auth/LoginPage.module.css` | Gradient bg, animation, shadow, visibility toggle, google button, responsive |
| `app/frontend/pages-inertia/Auth/GoogleLoginButton.tsx` | Remove inline styles, use CSS module class |

---

## Acceptance Criteria

| # | Criterion | Test |
|---|-----------|------|
| 1 | Zod: invalid email → inline error before submit | Type "abc" → tab away or click Sign in → see "Invalid email format" |
| 2 | Zod: empty fields → inline error | Click Sign in with empty fields → see "Email is required" and "Password is required" |
| 3 | Zod: valid → server roundtrip | Type valid email + password → Sign in → Inertia POST happens |
| 4 | Server errors still work | Wrong password → see server error under fields |
| 5 | OAuth errors still work | Visit `/login?error=deactivated` → see red notification |
| 6 | Password toggle | Click eye icon → password revealed, click again → masked |
| 7 | Card animation | On page load, card fades in and slides up over ~300ms |
| 8 | Background gradient | Page background shows radial gradient (not flat dark) |
| 9 | Google button dark | Google button has dark-6 background, not white |
| 10 | Inter font loaded | Inspect text in DevTools → font-family resolves to Inter |
| 11 | Mobile: card fills width | Viewport 375px → card uses full width with padding |
| 12 | Auto-redirect preserved | Authenticated user visiting /login → redirected (server-side, untouched) |

---

## Edge Cases

| Case | Expected |
|------|----------|
| Very long email (200+ chars) | Input scrolls horizontally, Zod validates format |
| Password with special chars | Visibility toggle shows them correctly |
| JS disabled | Form submits normally (Inertia requires JS, so N/A) |
| Slow network | `processing` state shows "Signing in..." + button disabled |
| OAuth redirect with unknown error param | Fallback message "Authentication failed. Please try again." |
| `prefers-reduced-motion` | Card animation should respect: add `@media (prefers-reduced-motion: reduce)` rule |
