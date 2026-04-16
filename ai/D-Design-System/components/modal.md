# Modal [mdl-001]

**Type:** Overlay
**Category:** Dialog
**Library:** Mantine `Modal`
**Purpose:** Focused interactions requiring user attention (create, edit, confirm, delete)

---

## Overview

Modals are the primary overlay pattern for all CRUD operations, confirmations, and focused workflows. The app uses 17+ unique modals covering project creation, resource management, workflow configuration, and delete confirmations.

---

## Variants

| Size | Use Case | Examples |
|------|----------|---------|
| `sm` | Delete confirmations | DeleteAgentModal, DeleteToolModal |
| `md` | Simple CRUD | CreateProjectModal, InviteUserModal |
| `lg` | Complex forms | RunWorkflowModal, ToolFormModal, McpServerFormModal |
| `xl` | Rich editors | Board settings, SkillFormModal |

---

## States

**Required States:**

- `opened` — visible with backdrop overlay
- `closed` — hidden, removed from DOM

**Optional States:**

- `loading` — form submission in progress
- `error` — validation errors displayed

---

## Styling

### Common Props

```yaml
centered:     true (all modals)
title:        string or ReactNode
size:         'sm' | 'md' | 'lg' | 'xl'
overlayProps: { backgroundOpacity: 0.55, blur: 3 } (Mantine default)
```

### Design Tokens

```yaml
modal-bg:           var(--mantine-color-dark-7)
modal-border:       var(--mantine-color-dark-4)
modal-radius:       var(--mantine-radius-md)
modal-padding:      var(--mantine-spacing-lg)
modal-overlay-bg:   rgba(0, 0, 0, 0.55)
modal-overlay-blur: 3px
```

### Internal Layout Pattern

```tsx
<Modal centered title="..." size="md" opened={opened} onClose={close}>
  <Stack gap="md">
    {/* Form fields */}
    <Group justify="flex-end" mt="md">
      <Button variant="outline" onClick={close}>Cancel</Button>
      <Button loading={loading}>Submit</Button>
    </Group>
  </Stack>
</Modal>
```

---

## Behavior

### Interactions

- `Escape` → close modal
- Overlay click → close modal
- Close button → close modal
- Form submit → loading state → success toast → close

### Validation

- Zod schemas for form validation (`@mantine/form` + `zodResolver`)
- Error messages displayed inline below fields

---

## Accessibility

**ARIA Attributes:**
- `role="dialog"` (Mantine built-in)
- `aria-modal="true"`
- `aria-labelledby` → title element

**Keyboard Support:**
- `Escape` → close
- `Tab` → trap focus within modal
- `Enter` → submit form (when button focused)

---

## Used In

**Modals:** 17+

**Examples:**

- CreateProjectModal — project creation
- RunWorkflowModal — workflow execution with params
- InviteUserModal — member invitation
- ConfigItemFormModal — config key/value editing
- ToolFormModal — tool configuration
- McpServerFormModal — MCP server setup
- AgentFormModal / SkillFormModal — resource management
- EditRepositoryModal — repository editing
- DeleteMcpServerModal, DeleteToolModal, DeleteAgentModal, DeleteSkillModal — confirmations
- Board settings modal (inline in BoardPage)

---

## Related Components

- `Drawer` [drw-001] — side panel alternative
- `Button` [btn-001] — action triggers
- `Stack` / `Group` — internal layout

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
