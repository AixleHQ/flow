# Typography Components

---

## Text [txt-001]

**Type:** Typography
**Category:** Body Copy
**Library:** Mantine `Text`
**Purpose:** General text rendering with built-in styling props

### Overview

The most frequently used component across the app. Every page uses `Text` for labels, descriptions, values, and inline content.

### Common Props

| Prop | Values | Use Case |
|------|--------|----------|
| `size` | `xs`, `sm`, `md`, `lg`, `xl` | Size control |
| `fw` | 400, 500, 600, 700 | Weight control |
| `c` | `dimmed`, `red`, `blue`, color name | Color control |
| `truncate` | `true`, `"end"` | Overflow handling |
| `ta` | `center`, `right` | Alignment |
| `tt` | `uppercase` | Transform |
| `span` | `true` | Render as `<span>` |

### Font Resolution

- Default: `Poppins` (from `theme.fontFamily`)
- Body text in CSS modules: `var(--app-font-body)` → `Inter`
- Code blocks: `JetBrains Mono`

---

## Title [txt-002]

**Type:** Typography
**Category:** Heading
**Library:** Mantine `Title`
**Purpose:** Page and section headings

### Common Props

| Prop | Values | Use Case |
|------|--------|----------|
| `order` | 1–6 | Heading level (h1–h6) |
| `size` | Mantine sizes | Override size |
| `fw` | 600, 700 | Weight |

### Used In

Profile page, Members page, resource content pages (repositories, integrations, config items).

---

## Typography Scale

| Level | Element | Font | Size | Weight | Use |
|-------|---------|------|------|--------|-----|
| Page title | `Title order={2}` | Poppins | 24px+ | 700 | Page headers |
| Section title | `Title order={3}` | Poppins | 20px | 600 | Card/section headers |
| Body | `Text size="sm"` | Poppins/Inter | 14px | 400 | Content |
| Label | `Text size="sm" fw={500}` | Poppins | 14px | 500 | Form labels |
| Caption | `Text size="xs"` | Poppins | 12px | 400 | Hints, metadata |
| Muted | `Text c="dimmed"` | — | — | — | Secondary information |

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
