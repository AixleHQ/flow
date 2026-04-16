# Paper [crd-002]

**Type:** Surface
**Category:** Container
**Library:** Mantine `Paper`
**Purpose:** Lightweight elevated surface for forms, panels, and stat blocks

---

## Overview

Paper is used as a lighter alternative to Card for form containers, dashboard stat blocks, and login panels. Unlike Card, Paper does not have a theme-level default override — it uses Mantine's built-in styling directly.

---

## Variants

| Variant | Use Case | Styling |
|---------|----------|---------|
| Default with border | Form containers, settings | `withBorder`, `radius="md"` |
| Elevated (Login) | Login card | Custom shadow: `0 8px 32px rgba(0,0,0,0.4)` |
| Stat block | Dashboard tiles | `radius="md"`, `withBorder`, `p="md"` |
| Workflow panel | Builder sections | `withBorder`, nested content |

---

## States

**Required States:**

- `default` — resting surface

---

## Styling

### Design Tokens

```yaml
paper-bg:           var(--mantine-color-dark-7) or var(--app-bg-paper)
paper-border:       1px solid var(--mantine-color-dark-4)
paper-radius:       var(--mantine-radius-md)
paper-shadow-login: 0 8px 32px rgba(0, 0, 0, 0.4)
paper-padding:      md–xl (varies by context)
```

---

## Used In

**Pages:** 10+

**Examples:**

- Login → Main form container (shadow, centered)
- Workflow builders → Section panels
- Run Workflow Modal → Parameter groups
- Board → Task details
- Settings → Form sections
- Dashboard → Stat tiles

---

## Related Components

- `Card` [crd-001] — heavier surface with theme override
- `Alert` [crd-003] — status messaging surface

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
