# Text Input [inp-001]

**Type:** Form
**Category:** Input
**Library:** Mantine `TextInput`
**Purpose:** Single-line text entry with optional label and search icon

---

## Overview

TextInput is the most widely used form component across the application. It appears in search bars, modal forms, settings pages, and inline editing contexts. Standard size is `sm` for consistency.

---

## Variants

| Variant | Use Case | Props |
|---------|----------|-------|
| Default | Form fields | `size="sm"`, `label`, `placeholder` |
| Search | Search/filter bars | `size="sm"`, `leftSection={<IconSearch />}` |
| Compact | Dense table inline | `size="compact-xs"` (MCP server form) |

---

## States

**Required States:**

- `default` — empty or with value
- `focus` — border highlight
- `error` — red border, error message
- `disabled` — grayed, non-interactive

**Optional States:**

- `with-value` — populated state
- `loading` — paired with external loader

---

## Styling

### Design Tokens

```yaml
input-height:       2.5rem (sm)
input-font-family:  var(--app-font-body) / Inter
input-font-size:    14px (sm)
input-border:       var(--mantine-color-dark-4)
input-border-focus: var(--mantine-color-blue-6)
input-border-error: var(--mantine-color-red-6)
input-bg:           transparent (inherits)
input-radius:       var(--mantine-radius-md)
```

---

## Behavior

### Validation

Two validation patterns coexist:

1. **Inertia `useForm` + Zod** — Login, Profile, Settings
2. **`@mantine/form` + `zodResolver`** — Workflow builders, resource modals

Both display errors below the field in red.

---

## Accessibility

**ARIA Attributes:**
- `aria-invalid="true"` when error
- `aria-describedby` → error message element
- `id` + `label` → `htmlFor` association (Mantine built-in)

**Keyboard Support:**
- `Tab` → focus
- `Escape` → blur (browser default)

---

## Used In

**Pages:** 20+

**Examples:**

- Search bars (Projects, Workflows, Sessions)
- Modal forms (Create Project, Invite User, Config Items)
- Settings (project name, description)
- Profile (name, email)

---

## Related Components

- `Textarea` [inp-002] — multi-line variant
- `PasswordInput` [inp-003] — masked variant
- `Select` [inp-004] — dropdown variant
- `Autocomplete` [inp-007] — suggestion variant

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
