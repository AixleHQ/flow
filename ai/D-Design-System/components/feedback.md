# Feedback Components

---

## Loader [ldr-001]

**Type:** Feedback
**Category:** Loading
**Library:** Mantine `Loader`
**Purpose:** Indicates ongoing operation

### Variants

| Size | Use Case |
|------|----------|
| `sm` | Inline loading (buttons, fields) |
| `md` | Section loading |
| `lg` | Full-page loading |

### Used In

Onboarding (auto-save), EditRepositoryModal (data fetch), BoardPage (column load), Profile (save), Aixle Builder (session loading).

---

## Notification [ntf-001]

**Type:** Feedback
**Category:** Toast
**Library:** `@mantine/notifications` → `notifications.show()`
**Purpose:** Transient success/error messages

### Pattern

```tsx
notifications.show({
  title: 'Success',
  message: 'Item saved successfully',
  color: 'green',
});

notifications.show({
  title: 'Error',
  message: 'Something went wrong',
  color: 'red',
});
```

### Colors

| Color | Use Case |
|-------|----------|
| `green` | Success operations |
| `red` | Error states |
| `blue` | Info messages |

### Provider

`<Notifications />` rendered at `inertia.tsx` root level.

---

## Alert [crd-003]

**Type:** Feedback
**Category:** Inline Message
**Library:** Mantine `Alert`
**Purpose:** Persistent status/warning messages within page flow

### Used In

CreateProjectModal (info), Workflow builders (validation warnings), Session Artifacts (status).

---

## Skeleton [skl-001]

**Type:** Feedback
**Category:** Placeholder
**Library:** Mantine `Skeleton`
**Purpose:** Content loading placeholder

### Used In

BoardPage (column skeletons), AnalyticsPage (chart placeholders).

---

## Progress [prg-001]

**Type:** Feedback
**Category:** Progress Indicator
**Library:** Mantine `Progress`
**Purpose:** Linear progress display

### Variants

| Use | Props |
|-----|-------|
| Route indicator | `size={2}`, `animated`, fixed top |
| Asset upload | Value bar with percentage |
| Overview stats | Value bar for metrics |

### Route Indicator

```css
position: fixed;
top: 0;
left: 0;
right: 0;
z-index: 1000;
```

Implemented as `InertiaRouteIndicator.tsx` — shows during page transitions.

---

## Stepper [stp-001]

**Type:** Feedback
**Category:** Multi-Step
**Library:** Mantine `Stepper`
**Purpose:** Multi-step process visualization

### Used In

OnboardingPage — 4-step wizard with step validation and animated transitions.

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
