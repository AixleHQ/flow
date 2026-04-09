# Form Controls

---

## Textarea [inp-002]

**Type:** Form
**Category:** Input
**Library:** Mantine `Textarea`
**Purpose:** Multi-line text entry

### Common Props

```yaml
autosize:  true (most instances)
minRows:   2–4
size:      'sm'
```

### Used In

Workflow builders (step descriptions), Board (comments), Profile (bio), Settings (descriptions), resource modals (notes, configs).

---

## PasswordInput [inp-003]

**Type:** Form
**Category:** Input
**Library:** Mantine `PasswordInput`
**Purpose:** Masked password entry

### Used In

Login page only. Features built-in visibility toggle.

---

## Select [inp-004]

**Type:** Form
**Category:** Input
**Library:** Mantine `Select`
**Purpose:** Single-value dropdown selection

### Common Props

```yaml
data:        Array<{value, label}> or string[]
size:        'sm'
searchable:  optional
clearable:   optional
```

### Used In

Onboarding (role selection), Workflows (trigger type), Board (assignee, status), Profile (timezone), Members (role), Sessions (model, agent), Assets (type filter).

---

## MultiSelect [inp-005]

**Type:** Form
**Category:** Input
**Library:** Mantine `MultiSelect`
**Purpose:** Multi-value tag selection

### Used In

Workflow builders (tags, tool selection), RunWorkflowModal (parameters), ToolFormModal (capabilities).

---

## NumberInput [inp-006]

**Type:** Form
**Category:** Input
**Library:** Mantine `NumberInput`
**Purpose:** Numeric value entry

### Used In

Workflow builders only (timeout, retry count, max steps).

---

## Autocomplete [inp-007]

**Type:** Form
**Category:** Input
**Library:** Mantine `Autocomplete`
**Purpose:** Text input with suggestion dropdown

### Used In

Workflow builder (step references), ConfigItemValueField (key suggestions).

---

## Checkbox [inp-008]

**Type:** Form
**Category:** Toggle
**Library:** Mantine `Checkbox`
**Purpose:** Binary on/off selection

### Common Props: `size="sm"`

### Used In

Onboarding (feature selection), RunWorkflowModal (boolean params), Session Artifacts (selection).

---

## Switch [inp-009]

**Type:** Form
**Category:** Toggle
**Library:** Mantine `Switch`
**Purpose:** Boolean toggle for settings

### Common Props: `size="sm"`

### Used In

Workflow builders (enable/disable features), Session New (advanced options), McpServerFormModal (SSL toggle).

---

## SegmentedControl [inp-010]

**Type:** Form
**Category:** Selector
**Library:** Mantine `SegmentedControl`
**Purpose:** Exclusive option selection (radio-like)

### Used In

AnalyticsPage (time range), Session New pages (model/mode selector), McpServersContent (transport filter), ToolsContent (type filter).

---

## Form Patterns

### Pattern A: Inertia useForm + Zod

```tsx
const { data, setData, post, processing, errors } = useForm({ ... });
const schema = z.object({ ... });

// Validation on submit
const parsed = schema.safeParse(data);
if (!parsed.success) { /* set errors */ }
post(route, { onSuccess: () => ... });
```

**Used in:** LoginPage, Profile, Settings

### Pattern B: @mantine/form + zodResolver

```tsx
const form = useForm({
  initialValues: { ... },
  validate: zodResolver(schema),
});

form.onSubmit((values) => { /* API call */ });
```

**Used in:** Workflow modals, Board, all resource modals (Config, Tools, MCP, Agents, Skills)

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
