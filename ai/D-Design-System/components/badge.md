# Badge [bdg-001]

**Type:** Data Display
**Category:** Status Indicator
**Library:** Mantine `Badge`
**Purpose:** Compact label for status, categories, and metadata

---

## Overview

Badges are used extensively for status indication (workflow runs, sessions), categorization (tools, agents), and metadata display (counts, types). They support dynamic colors mapped to entity states.

---

## Variants

| Variant | Use Case | Example |
|---------|----------|---------|
| `filled` | Primary status | Running (blue), Completed (green) |
| `outline` | Secondary labels | Categories, types |
| `light` | Soft emphasis | Tag-like labels |
| `dot` | Minimal status | Dot + label |

---

## States

**Required States:**

- `default` — static display

---

## Styling

### Sizes

```yaml
xs: compact badges in tables
sm: standard badges in cards/lists
```

### Common Props

```yaml
size:        'xs' | 'sm'
variant:     'filled' | 'outline' | 'light' | 'dot'
color:       dynamic based on status (green, blue, red, amber)
leftSection: optional icon
```

### Dynamic Color Mapping

```yaml
completed:  green   → status-completed (#22C55E)
running:    blue    → status-running (#3B82F6)
pending:    gray    → status-pending (#666666)
error:      red     → status-error (#EF4444)
warning:    amber   → status-running-other (#F59E0B)
```

### Design Tokens

```yaml
badge-font-size-xs:  10px
badge-font-size-sm:  12px
badge-font-weight:   600
badge-border-radius: var(--mantine-radius-xl) / pill shape
badge-padding-x:     8px–12px
badge-height-xs:     18px
badge-height-sm:     22px
```

---

## Accessibility

**ARIA Attributes:**
- Semantic text content (no `aria-label` needed for text badges)
- `dot` variant: visual-only indicator, text label provides context

---

## Used In

**Pages:** 15+

**Examples:**

- Workflow runs → status badges (completed/running/error/pending)
- Sessions → session status
- Board → task labels, priority
- Profile → agent tool badges
- Analytics → metric labels
- Assets → file type badges
- Run Workflow Modal → parameter type badges

---

## Related Components

- `ThemeIcon` [ico-001] — decorative icon containers
- `Avatar` [avt-001] — user/entity representation
- `Text` [txt-001] — inline status text alternative

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
