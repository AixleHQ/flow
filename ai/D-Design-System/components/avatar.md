# Avatar [avt-001]

**Type:** Data Display
**Category:** Identity
**Library:** Mantine `Avatar`
**Purpose:** Visual representation of users and projects

---

## Overview

Avatars display user photos, initials, or project icons. Used in project cards, board task cards, and member lists.

---

## Variants

| Variant | Use Case | Props |
|---------|----------|-------|
| Image | User with photo | `src={url}`, `alt` |
| Initials | User without photo | `color`, children = initials |
| Project | Project icon | `radius="xl"`, `size="md"` |

---

## States

**Required States:**

- `default` — image loaded or initials displayed
- `fallback` — placeholder when image fails

---

## Styling

### Design Tokens

```yaml
avatar-size-sm: 24px
avatar-size-md: 36px
avatar-size-lg: 48px
avatar-radius:  var(--mantine-radius-xl)  # circular
avatar-border:  none (default) or 2px solid for stacked
```

---

## Used In

**Pages:** 5+

**Examples:**

- ProjectCard → project avatar
- BoardPage → assignee avatars on tasks
- MembersPage → member list avatars
- Header → user avatar (if implemented)

---

## Related Components

- `ThemeIcon` [ico-001] — icon containers (non-user)
- `Badge` [bdg-001] — often paired for status

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
