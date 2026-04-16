# Table [tbl-001]

**Type:** Data Display
**Category:** Data
**Library:** Mantine `Table`
**Purpose:** Tabular data display for resource lists with actions

---

## Overview

Tables are used for all resource listing pages (sessions, assets, config items, tools, agents, skills, MCP servers). They follow the Mantine compound component pattern: `Table.Thead`, `Table.Tbody`, `Table.Tr`, `Table.Th`, `Table.Td`.

---

## Variants

| Variant | Use Case | Features |
|---------|----------|----------|
| Resource table | CRUD list pages | Headers + rows + action column |
| Simple table | Read-only data | No actions column |

---

## States

**Required States:**

- `default` — populated with data
- `empty` — empty state message
- `loading` — skeleton rows

---

## Styling

### Common Pattern

```yaml
layout:       full-width
row-hover:    subtle background change (Mantine built-in)
action-col:   right-aligned ActionIcon buttons
```

### Design Tokens

```yaml
table-bg:         transparent (inherits from page)
table-border:     var(--mantine-color-dark-4)
table-header-bg:  slightly elevated
table-row-hover:  var(--app-action-hover)
table-font-size:  sm (14px)
```

### Action Column Pattern

```tsx
<Table.Td>
  <Group gap="xs" justify="flex-end">
    <Tooltip label="Edit">
      <ActionIcon variant="subtle" size="sm">
        <IconEdit size={16} />
      </ActionIcon>
    </Tooltip>
    <Tooltip label="Delete">
      <ActionIcon variant="subtle" size="sm" color="red">
        <IconTrash size={16} />
      </ActionIcon>
    </Tooltip>
  </Group>
</Table.Td>
```

---

## Behavior

### Interactions

- Row hover → highlight
- Action icons → tooltip on hover, modal on click
- Sortable headers (future)
- Search/filter bar above table

---

## Accessibility

**ARIA Attributes:**
- Semantic `<table>` structure (Mantine built-in)
- `<thead>` / `<tbody>` for screen readers
- Action buttons with `Tooltip` labels

**Keyboard Support:**
- `Tab` → navigate action buttons
- Focus management within rows

---

## Used In

**Pages:** 10+

**Examples:**

- Sessions list → columns: name, status, duration, actions
- Assets → columns: name, type, size, actions
- Config Items → columns: key, value, scope, actions
- Tools → columns: name, type, status, actions
- Agents → columns: name, model, status, actions
- Skills → columns: name, description, actions
- MCP Servers → columns: name, transport, status, actions
- Members → columns: name, email, role, actions

---

## Related Components

- `ActionIcon` [btn-002] — row actions
- `Badge` [bdg-001] — status in cells
- `Tooltip` [tip-001] — action hints
- `Skeleton` [skl-001] — loading state

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
