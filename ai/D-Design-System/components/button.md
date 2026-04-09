# Button [btn-001]

**Type:** Interactive
**Category:** Action
**Library:** Mantine `Button`
**Purpose:** Primary interactive element for triggering actions

---

## Overview

Buttons are used across the entire application for form submissions, navigation triggers, and action confirmations. The app uses three Mantine button components: `Button` (standard), `ActionIcon` (icon-only), and `UnstyledButton` (custom-styled).

---

## Variants

### Button (btn-001)

| Variant | Use Case | Example |
|---------|----------|---------|
| `filled` | Primary actions | Submit, Save, Create |
| `outline` | Secondary / Cancel actions | Cancel, Back |
| `subtle` | Tertiary / Navigation | Header nav, toolbar actions |
| `light` | Soft emphasis | Less prominent secondary |
| `default` | Neutral | Google login button |

### ActionIcon (btn-002)

| Variant | Use Case | Example |
|---------|----------|---------|
| `subtle` | Icon-only actions | Edit, Delete, Refresh |
| `subtle` + `color="red"` | Destructive icon action | Delete row |

### UnstyledButton (btn-003)

Custom-styled clickable areas: project cards, sidebar items, emoji picker.

---

## States

**Required States:**

- `default` — resting appearance
- `hover` — cursor over, slight bg change
- `active` — pressed state
- `disabled` — grayed out, no interaction
- `loading` — spinner replaces content

**Optional States:**

- `focus-visible` — keyboard focus ring (Mantine built-in)

---

## Styling

### Sizes

```yaml
xs:         compact buttons in dense UIs
sm:         standard form buttons
compact-md: header navigation buttons
md:         default, general purpose
```

### Common Props

```yaml
leftSection:  icon before label (e.g., IconPlus)
rightSection: icon after label (e.g., IconChevronRight)
fullWidth:    spans container width (modals, login)
loading:      shows Loader, disables interaction
color:        'red' for destructive, default blue
```

### Design Tokens

```yaml
button-font-family:   var(--mantine-font-family)   # Poppins
button-font-weight:   600
button-border-radius: var(--mantine-radius-md)
button-transition:    150ms ease
```

---

## Behavior

### Interactions

- Click → triggers `onClick` handler or form submit
- Loading state → replaces label with `Loader`, disables click
- Disabled → cursor: not-allowed, reduced opacity

### Animations

- Hover: subtle background shift (Mantine built-in)
- Active: slight scale reduction

---

## Accessibility

**ARIA Attributes:**
- `role="button"` (implicit on `<button>`)
- `aria-disabled="true"` when disabled
- `aria-busy="true"` when loading

**Keyboard Support:**
- `Enter` / `Space` → trigger action
- `Tab` → focus navigation

---

## Usage

### When to Use

- Triggering any form submission
- Navigating to a new context (paired with router)
- Confirming/canceling modal actions

### When Not to Use

- In-table row actions → use `ActionIcon`
- Card-level click targets → use `UnstyledButton`
- Links that navigate to external URLs → use `Anchor`

---

## Used In

**Pages:** 25+

**Examples:**

- Login → Submit button (filled, fullWidth, loading)
- Onboarding → Step navigation (outline, filled)
- Workflow Builder → Save, Run, Add Step (filled, outline, subtle)
- Board → Column actions (ActionIcon subtle)
- Modals → Confirm/Cancel pair (filled + outline)
- Header → Nav items (subtle, compact-md)
- Settings → Save (filled), Cancel (outline)

---

## Related Components

- `ActionIcon` [btn-002] — icon-only variant
- `UnstyledButton` [btn-003] — custom-styled
- `Loader` [ldr-001] — loading state
- `Tooltip` [tip-001] — often wraps ActionIcon

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
