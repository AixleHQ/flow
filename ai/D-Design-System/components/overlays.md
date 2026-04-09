# Overlay Components

---

## Drawer [drw-001]

**Type:** Overlay
**Category:** Side Panel
**Library:** Mantine `Drawer`
**Purpose:** Slide-in panel for detailed content

### Used In

BoardPage — task detail panel (slides from right).

---

## Tooltip [tip-001]

**Type:** Overlay
**Category:** Hint
**Library:** Mantine `Tooltip`
**Purpose:** Context information on hover

### Overview

Tooltips are the most widely used overlay — virtually every `ActionIcon` is wrapped in a `Tooltip` for accessibility.

### Pattern

```tsx
<Tooltip label="Edit">
  <ActionIcon variant="subtle" size="sm">
    <IconEdit size={16} />
  </ActionIcon>
</Tooltip>
```

### Used In

All resource tables, workflow builders, board, header, sidebar, profile page.

---

## Popover [pop-001]

**Type:** Overlay
**Category:** Anchored Content
**Library:** Mantine `Popover`
**Purpose:** Floating content anchored to trigger

### Used In

EmojiPicker — emoji grid anchored to trigger button.

---

## Menu [mnu-001]

**Type:** Overlay
**Category:** Context Menu
**Library:** Mantine `Menu`
**Purpose:** Dropdown action list

### Pattern

```tsx
<Menu shadow="md">
  <Menu.Target>
    <ActionIcon><IconDotsVertical /></ActionIcon>
  </Menu.Target>
  <Menu.Dropdown>
    <Menu.Item leftSection={<IconEdit />}>Edit</Menu.Item>
    <Menu.Item color="red" leftSection={<IconTrash />}>Delete</Menu.Item>
  </Menu.Dropdown>
</Menu>
```

### Used In

- AppHeader → user menu, project switcher
- RepositoriesContent → row actions
- MembersContent → role management
- IntegrationsContent → integration actions

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
