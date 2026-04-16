# User Profile Page — Update Specification

> **Scenario:** Direct from analysis — `ai/evolution/analysis/page-by-page-evolution.md`, section 27
> **Created:** 2026-04-03
> **Risk:** Low (frontend-only, no API/controller changes)

---

## Change Summary

Polish the Inertia Profile page: add visual section separation (titled Card groups for Profile / Defaults / Credentials), client-side Zod validation for the profile form, fix hardcoded `c="white"` → theme token, make agent credential cards responsive, and replace raw `fetch()` in CredentialModelRow with a proper pattern that handles errors gracefully.

---

## Before

```
┌───────────────────────────────────────────────────────┐
│  (flat bg var(--app-bg-default))                      │
│                                                       │
│  My Profile  ← c="white" hardcoded                    │
│                                                       │
│  ┌────────────────────────────────┐  ← Card, no title │
│  │  🔒 Email (read-only)          │                    │
│  │  Display Name [ input       ]  │                    │
│  │  Agent Language [ select    ]  │                    │
│  │  🔒 Company (read-only)        │                    │
│  │  Role [Badge]                  │                    │
│  │  [ Save Changes ]              │                    │
│  └────────────────────────────────┘                    │
│                                                        │
│  ┌────────────────────────────────┐  ← Card, no title  │
│  │  Default Agent Runtime          │  (title inside)    │
│  │  [ select ]                     │                    │
│  └────────────────────────────────┘                    │
│                                                        │
│  ┌────────────────────────────────┐  ← Card, no title  │
│  │  Default Models                 │  (title inside)    │
│  │  Claude Code   [ select ]       │                    │
│  │  Cursor CLI    [ select ]       │                    │
│  └────────────────────────────────┘                    │
│                                                        │
│  Agent Runtimes (loose title)                          │
│  ┌─ card ──────────────────────────┐                   │
│  │ ▊ Claude Code   ... [Connected] [Re-auth]  │ ← flex │
│  └─────────────────────────────────┘           │ breaks │
│  ┌─ card ──────────────────────────┐           │ on     │
│  │ ▊ Cursor CLI    ... [Re-auth]   │           │ mobile │
│  └─────────────────────────────────┘                   │
│  ...                                                   │
└───────────────────────────────────────────────────────┘
```

### Problems

1. **No visual sections** — Profile form, Default Agent, Models, and Agent Runtimes flow as a flat list without clear grouping. Hard to scan.
2. **No client-side validation** — name can be empty string, no min-length check before submit. Inertia sends patch, server may reject.
3. **Hardcoded `c="white"`** on page title — will break on light theme, inconsistent with other pages using CSS variables.
4. **Agent cards not responsive** — flex row layout with color bar + text + badge + button breaks on viewport < 500px.
5. **Raw fetch in CredentialModelRow** — `fetch('/api/v1/agent_models?...')` with no error UI, no retry, no loading skeleton on failure.

---

## After

```
┌───────────────────────────────────────────────────────┐
│  (bg var(--app-bg-default))                           │
│                                                       │
│  My Profile  ← c="var(--app-text-primary)"            │
│                                                       │
│  ┌── SECTION: Personal Information ───────────┐       │
│  │  Title order={4} "Personal Information"     │       │
│  │  Divider mb="md"                            │       │
│  │                                             │       │
│  │  🔒 Email (read-only)                       │       │
│  │  Display Name [ input ] ← Zod min(2)        │       │
│  │  Agent Language [ select ] ← Zod enum        │       │
│  │  🔒 Company (read-only)                      │       │
│  │  Role [Badge]                                │       │
│  │                                             │       │
│  │  [ Save Changes ] ← disabled when !dirty    │       │
│  │                     OR !valid               │       │
│  └─────────────────────────────────────────────┘       │
│                                                        │
│  ┌── SECTION: Default Agent Runtime ──────────┐       │
│  │  Title + description (as now)               │       │
│  │  [ select ]                                 │       │
│  └─────────────────────────────────────────────┘       │
│                                                        │
│  ┌── SECTION: Default Models ─────────────────┐       │
│  │  Title + description (as now)               │       │
│  │  Claude Code   [ select ] ← error state     │       │
│  │  Cursor CLI    [ select ]                   │       │
│  └─────────────────────────────────────────────┘       │
│                                                        │
│  ┌── SECTION: Agent Runtimes ─────────────────┐       │
│  │  Title + description (as now)               │       │
│  │                                             │       │
│  │  ┌─ card ───────────────────────────┐       │       │
│  │  │ ▊ Claude Code                     │       │       │
│  │  │   Description text                │       │       │
│  │  │   Configured May 2, 2026          │       │       │
│  │  │   [Connected] [Re-authenticate]   │ ← wrap│       │
│  │  └──────────────────────────────────┘       │       │
│  │  ...                                        │       │
│  └─────────────────────────────────────────────┘       │
└───────────────────────────────────────────────────────┘
```

---

## Components

### 1. `Show.tsx` — Section structure + Zod validation

**1a. Section wrapping**

Wrap each logical group in a `Card` with a section `Title` + `Divider`:

```tsx
<Card p={24}>
  <Title order={4} mb={4}>Personal Information</Title>
  <Divider mb="md" />
  <form onSubmit={handleSubmit}>
    {/* email, name, language, company, role, save button */}
  </form>
</Card>
```

The Default Agent, Default Models, and Agent Runtimes sections already live in their own cards with titles — they stay as-is structurally.

**1b. Zod schema + client-side validation**

Add validation state alongside Inertia form:

```typescript
import { z } from 'zod';

const profileSchema = z.object({
  name: z.string().min(2, 'Name must be at least 2 characters').max(100, 'Name must be less than 100 characters'),
  preferred_agent_language: z.string().min(1, 'Language is required'),
});

type ProfileFormErrors = Partial<Record<keyof z.infer<typeof profileSchema>, string>>;
```

Add local error state:

```typescript
const [clientErrors, setClientErrors] = useState<ProfileFormErrors>({});
```

Update `handleSubmit`:

```typescript
const handleSubmit = (e: React.FormEvent) => {
  e.preventDefault();
  const result = profileSchema.safeParse(data.profile);
  if (!result.success) {
    const fieldErrors: ProfileFormErrors = {};
    for (const issue of result.error.issues) {
      const field = issue.path[0] as keyof ProfileFormErrors;
      if (!fieldErrors[field]) fieldErrors[field] = issue.message;
    }
    setClientErrors(fieldErrors);
    return;
  }
  setClientErrors({});
  patch('/profile', { preserveScroll: true });
};
```

Show merged errors (client + server):

```tsx
<TextInput
  label="Display Name"
  value={data.profile.name}
  onChange={(e) => {
    setData('profile', { ...data.profile, name: e.currentTarget.value });
    if (clientErrors.name) setClientErrors((prev) => ({ ...prev, name: undefined }));
  }}
  error={clientErrors.name || errors['profile.name']}
  disabled={processing}
/>
```

Disable save when form is not valid (client-side):

```tsx
const isFormValid = data.profile.name.trim().length >= 2 && data.profile.preferred_agent_language;

<Button type="submit" disabled={!isDirty || !isFormValid || processing} loading={processing}>
  Save Changes
</Button>
```

**1c. Fix hardcoded title color**

Before:
```tsx
<Title order={2} fz={32} fw={600} c="white" mb={24}>
```

After:
```tsx
<Title order={2} fz={32} fw={600} c="var(--app-text-primary)" mb={24}>
```

---

### 2. `Show.module.css` — Responsive agent cards

Add responsive breakpoint for agent cards:

```css
@media (max-width: 540px) {
  .agentCardContent {
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }

  .agentActions {
    width: 100%;
    justify-content: flex-start;
  }
}
```

---

### 3. `CredentialModelRow` (inside Show.tsx) — Error handling for model fetch

**Before:** Raw `fetch()` with `.catch(() => setFetched(true))` — silently fails, user sees empty dropdown.

**After:** Add error state and show inline error:

```typescript
const [fetchError, setFetchError] = useState(false);

const fetchModels = useCallback(() => {
  if (!fetched) {
    setLoading(true);
    setFetchError(false);
    fetch(`/api/v1/agent_models?agent_runtime=${credential.agent_type}`, {
      credentials: 'same-origin',
      headers: { Accept: 'application/json' },
    })
      .then((r) => {
        if (!r.ok) throw new Error('fetch failed');
        return r.json();
      })
      .then((data) => {
        if (Array.isArray(data)) setModels(data);
        setFetched(true);
      })
      .catch(() => {
        setFetchError(true);
        setFetched(true);
      })
      .finally(() => setLoading(false));
  }
}, [fetched, credential.agent_type]);
```

Show error state:

```tsx
<Select
  ...
  error={fetchError ? 'Failed to load models' : undefined}
  rightSection={loading ? <Loader size={14} /> : undefined}
/>
```

Allow retry on next dropdown open:

```typescript
const handleRetry = useCallback(() => {
  setFetched(false);
  setFetchError(false);
}, []);
```

```tsx
{fetchError && (
  <Text size="xs" c="red" style={{ cursor: 'pointer' }} onClick={handleRetry}>
    Failed to load models. Click to retry.
  </Text>
)}
```

---

## Responsive Behavior

| Breakpoint | Behavior |
|------------|----------|
| Desktop (>540px) | Agent cards: horizontal flex row (color bar + info + actions) |
| Mobile (≤540px) | Agent cards: stack vertically, actions full width below info |
| All sizes | Cards/sections stack vertically, max-width 600px centered |

No changes to profile form or select components — Mantine handles them responsively by default.

---

## Files Changed (summary)

| File | Change Type |
|------|-------------|
| `app/frontend/pages-inertia/Profile/Show.tsx` | Section Card wrappers, Zod validation, fix `c="white"`, model fetch error handling |
| `app/frontend/pages-inertia/Profile/Show.module.css` | Responsive agent card styles |

---

## Acceptance Criteria

| # | Criterion | Test |
|---|-----------|------|
| 1 | Profile form has "Personal Information" section title | Visual: card shows `Title order={4}` + `Divider` above form fields |
| 2 | Default Agent card retains its existing title | Visual: "Default Agent Runtime" title visible |
| 3 | Default Models card retains its existing title | Visual: "Default Models" title visible |
| 4 | Agent Runtimes wrapped in section card | Visual: section has Card wrapper with title + description |
| 5 | Zod: empty name → inline error | Clear name field → see "Name must be at least 2 characters" |
| 6 | Zod: 1-char name → inline error | Type "A" → see validation error |
| 7 | Zod: valid name → no error, save enabled | Type "Artem" → no error, button enabled when dirty |
| 8 | Save disabled when form pristine | Page load → Save button disabled |
| 9 | Save disabled when client validation fails | Name="" → Save disabled |
| 10 | Page title uses theme token | Inspect `Title` → `color: var(--app-text-primary)`, not hardcoded `white` |
| 11 | Agent cards responsive ≤540px | Viewport 375px → cards stack vertically, no horizontal overflow |
| 12 | Model fetch error → "Failed to load models" | Block `/api/v1/agent_models` in DevTools → open dropdown → see error |
| 13 | Model fetch retry works | Click retry text → dropdown tries to fetch again |
| 14 | Server errors still work | Submit with server-invalid data → see server error on field |
| 15 | Flash notifications work | Save profile → see green "Profile updated successfully" notification |

---

## Edge Cases

| Case | Expected |
|------|----------|
| Name with 100+ characters | Zod rejects at max(100), inline error shown |
| Name with only spaces | `.trim()` check: "  " → length 0 → validation error |
| No agent credentials configured | Default Agent shows "No credentials configured" message |
| API returns non-array for models | Models list stays empty, no crash |
| `profile.company` is null | Shows "Platform Administrator" fallback (existing behavior preserved) |
| `prefers-reduced-motion` | No animations on this page currently — no action needed |
