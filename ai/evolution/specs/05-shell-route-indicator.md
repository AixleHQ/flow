# Application Shell — Route Pending Indicator

> **Scenario:** Direct from analysis — `ai/evolution/analysis/page-by-page-evolution.md`, section 1
> **Created:** 2026-04-03
> **Risk:** Low (frontend-only, 2 files, no API changes)

---

## Change Summary

Add a route transition indicator to the Inertia app shell. A thin progress bar appears at the top of the viewport when Inertia navigates between pages, providing visual feedback that something is happening. Uses Inertia's `router.on('start'/'finish')` events and Mantine's `Progress` component.

---

## Before

```
┌──────────────────────────────────────────────┐
│ [Header]                                     │
├──────────┬───────────────────────────────────┤
│ Sidebar  │  Content                          │
│          │                                   │
│          │  (user clicks nav item)           │
│          │  ...nothing happens for 200-500ms │
│          │  (page appears suddenly)          │
│          │                                   │
└──────────┴───────────────────────────────────┘
```

### Problem
No visual feedback during Inertia page transitions. User clicks a nav item and nothing happens for 200-500ms until the new page renders. Feels broken on slow connections.

---

## After

```
┌══════════════════════════════════════════════┐ ← 2px Progress bar
│ [Header]                                     │   (blue, animated)
├──────────┬───────────────────────────────────┤
│ Sidebar  │  Content                          │
│          │                                   │
│          │  (user clicks nav item)           │
│          │  → blue progress bar animates     │
│          │  (page renders, bar disappears)   │
│          │                                   │
└──────────┴───────────────────────────────────┘
```

---

## Components

### 1. `InertiaRouteIndicator.tsx` — New component

**Location:** `app/frontend/shared/ui-inertia/InertiaRouteIndicator.tsx`

Small component that listens to Inertia router events:

```tsx
import { router } from '@inertiajs/react';
import { Progress } from '@mantine/core';
import { useEffect, useState } from 'react';

import classes from './InertiaRouteIndicator.module.css';

export const InertiaRouteIndicator = () => {
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const removeStart = router.on('start', () => setLoading(true));
    const removeFinish = router.on('finish', () => setLoading(false));
    return () => {
      removeStart();
      removeFinish();
    };
  }, []);

  if (!loading) return null;

  return (
    <Progress
      value={100}
      size={2}
      color="blue"
      animated
      className={classes.indicator}
    />
  );
};
```

**CSS module:** `InertiaRouteIndicator.module.css`

```css
.indicator {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 1000;
}
```

**Why this approach:**
- Mantine `Progress` with `animated` gives the indeterminate shimmer effect
- `value={100}` fills the bar, `animated` adds the stripe animation → visually similar to MUI `LinearProgress` indeterminate
- Fixed position at z-index 1000 (above header at default z-index, below modals at 200+)
- Component self-cleans event listeners on unmount

### 2. `inertia.tsx` — Mount indicator at app root

Add `InertiaRouteIndicator` inside the MantineProvider, above `<App />`:

```tsx
import { InertiaRouteIndicator } from 'shared/ui-inertia/InertiaRouteIndicator';

// Inside setup():
<MantineProvider ...>
  <Notifications position="top-right" />
  <InertiaRouteIndicator />
  <App {...props} />
</MantineProvider>
```

**Why at app root (not in InertiaAuthLayout):**
- Works on ALL pages including login, onboarding
- Single instance — no duplicate listeners
- Doesn't depend on auth state

### 3. `shared/ui-inertia/index.ts` — Export

Add export:

```typescript
export { InertiaRouteIndicator } from './InertiaRouteIndicator';
```

---

## Responsive Behavior

No breakpoint-specific behavior. The 2px bar spans full viewport width at all sizes.

---

## Files Changed (summary)

| File | Change Type |
|------|-------------|
| `app/frontend/shared/ui-inertia/InertiaRouteIndicator.tsx` | **New** — route indicator component |
| `app/frontend/shared/ui-inertia/InertiaRouteIndicator.module.css` | **New** — fixed positioning styles |
| `app/frontend/shared/ui-inertia/index.ts` | **Modified** — add export |
| `app/frontend/entrypoints/inertia.tsx` | **Modified** — mount indicator |

---

## Acceptance Criteria

| # | Criterion | Test |
|---|-----------|------|
| 1 | Progress bar appears on Inertia navigation | Click any nav link → blue animated bar visible at top |
| 2 | Progress bar disappears when page loads | Bar gone after page renders |
| 3 | Bar is fixed at viewport top | Scroll down → bar still at top edge |
| 4 | Bar appears on all pages (including login redirect) | Navigate between pages, verify bar on each transition |
| 5 | No duplicate bars | Navigate rapidly → only one bar, no stacking |
| 6 | Bar doesn't appear on instant navigations | Already-cached page → bar may flash briefly or not appear (acceptable) |
| 7 | No linter errors | 0 TypeScript/ESLint errors in new/modified files |
| 8 | Event listeners cleaned up | Component unmount → no memory leak (verify via code review) |

---

## Edge Cases

| Case | Expected |
|------|----------|
| Rapid navigation (click 5 links fast) | Only one bar visible, `finish` event hides it |
| Navigation cancelled (e.g., beforeunload) | `finish` event fires with `cancelled` detail — bar hides |
| Server error (500) | `finish` event fires with error — bar hides |
| External link (non-Inertia) | No Inertia events — bar doesn't appear (correct) |
| Page with no layout (error page) | Bar still works — mounted at app root |
