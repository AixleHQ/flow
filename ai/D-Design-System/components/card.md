# Card [crd-001]

**Type:** Surface
**Category:** Container
**Library:** Mantine `Card`
**Purpose:** Primary surface for grouping related content

---

## Overview

Cards are the main surface component for content grouping. The Mantine `Card` is extended in the theme to use `var(--app-bg-paper)` (#141414) as the default background, ensuring consistency with the dark theme.

---

## Variants

| Variant | Use Case | Styling |
|---------|----------|---------|
| Default | Content groups, lists | `bg: var(--app-bg-paper)`, `withBorder` |
| Project Card | Project list items | Custom CSS module: 12px radius, hover lift |
| Onboarding Card | Step cards | Hover shadow animation |

---

## States

**Required States:**

- `default` — resting appearance

**Optional States:**

- `hover` — elevated shadow + border color change (project cards)
- `loading` — skeleton placeholder content

---

## Styling

### Visual Properties

```yaml
background:    var(--app-bg-paper) / #141414
border:        1px solid var(--app-border-default) / #2A2A2A
border-radius: var(--mantine-radius-md) or 12px (custom)
padding:       24px–32px (varies by context)
```

### Design Tokens

```yaml
card-bg:            var(--app-bg-paper)
card-border:        var(--app-border-default)
card-radius:        var(--mantine-radius-md)
card-radius-custom: 12px        # ProjectCard, SettingsCard
card-padding:       spacing-lg  # 20px standard
card-padding-large: 32px        # Profile, settings
```

### Project Card Hover

```css
border-color: var(--mantine-color-blue-6);
transform: translateY(-2px);
box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
transition: all 200ms ease;
```

---

## Behavior

### Interactions

- Project cards: full-card click via `UnstyledButton` wrapper
- Settings cards: static containers (no click)
- Content cards: optional expand/collapse

---

## Accessibility

**ARIA Attributes:**
- Clickable cards: `role="button"`, `tabIndex={0}`
- Static cards: semantic `<section>` or `<article>`

**Keyboard Support:**
- Clickable: `Enter` / `Space` → navigate
- `Tab` → focus navigation

---

## Used In

**Pages:** 15+

**Examples:**

- Projects List → ProjectCard (clickable, hover effects)
- Onboarding → Step cards with ThemeIcon
- Workflows → Workflow list items
- Sessions → Session list items
- Repositories → Repository cards
- Integrations → Integration cards

---

## Related Components

- `Paper` [crd-002] — lighter surface for forms/panels
- `Badge` [bdg-001] — often placed inside cards
- `Avatar` [avt-001] — project/user avatars in cards

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
