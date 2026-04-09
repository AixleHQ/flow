# Component Library Configuration

**Library:** Mantine
**Version:** ^9.0.0
**Default Color Scheme:** dark
**Last Updated:** 2026-04-03

---

## Installation

```bash
npm install @mantine/core @mantine/hooks @mantine/form @mantine/notifications @mantine/dates
npm install @tabler/icons-react
npm install mantine-form-zod-resolver zod
```

## Packages Used

| Package | Purpose |
|---------|---------|
| `@mantine/core` | Core components, theme, CSS variables |
| `@mantine/form` | Form state management with Zod validation |
| `@mantine/notifications` | Toast notifications |
| `@mantine/dates` | Date components (styles loaded, not yet used) |
| `@mantine/hooks` | Utility hooks (available, not yet used) |
| `@tabler/icons-react` | Icon library (68 icons in use) |
| `mantine-form-zod-resolver` | Zod schema → Mantine form resolver |

## Style Imports

```tsx
import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import '@mantine/dates/styles.css';
```

## Provider Configuration

```tsx
<MantineProvider
  theme={mantineTheme}
  defaultColorScheme="dark"
  cssVariablesResolver={cssVariablesResolver}
>
  <Notifications />
  {children}
</MantineProvider>
```

---

## Component Mappings

**Format:** `WDS Component → Mantine Component`

### Layout Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Page Layout | `Box` + CSS Modules | Custom shell, not AppShell |
| Content Stack | `Stack` | `gap="md"` default |
| Inline Group | `Group` | Horizontal alignment |
| Grid | `SimpleGrid` / `Grid` | Responsive columns |
| Scroll Container | `ScrollArea` | Sidebar, long panels |
| Center | `Center` | Vertical/horizontal centering |
| Container | `Container` | Guest layout wrapper |
| Divider | `Divider` | Section separators |

### Interactive Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Button [btn-001] | `Button` | Variants: filled, outline, subtle, light |
| Icon Button [btn-002] | `ActionIcon` | `variant="subtle"`, sizes xs/sm |
| Unstyled Button [btn-003] | `UnstyledButton` | Custom-styled interactive areas |

### Form Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Text Input [inp-001] | `TextInput` | `size="sm"` standard |
| Textarea [inp-002] | `Textarea` | `autosize`, `minRows` |
| Password Input [inp-003] | `PasswordInput` | Login only |
| Select [inp-004] | `Select` | Dropdown with data |
| Multi Select [inp-005] | `MultiSelect` | Tags / multi value |
| Number Input [inp-006] | `NumberInput` | Workflow builders |
| Autocomplete [inp-007] | `Autocomplete` | Suggestions |
| Checkbox [inp-008] | `Checkbox` | `size="sm"` |
| Switch [inp-009] | `Switch` | `size="sm"` |
| Segmented Control [inp-010] | `SegmentedControl` | Filter/mode toggles |

### Surface Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Card [crd-001] | `Card` | Default bg: `var(--app-bg-paper)` |
| Paper [crd-002] | `Paper` | Forms, panels |
| Alert [crd-003] | `Alert` | Status / warnings |

### Data Display Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Table [tbl-001] | `Table` | Thead/Tbody/Tr/Td pattern |
| Badge [bdg-001] | `Badge` | Variants: filled, outline, light, dot |
| Avatar [avt-001] | `Avatar` | User/project |
| Skeleton [skl-001] | `Skeleton` | Loading placeholders |
| Progress [prg-001] | `Progress` | Route indicator, stats |
| Image [img-001] | `Image` | Logo |

### Feedback Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Loader [ldr-001] | `Loader` | `size="sm"` |
| Notification [ntf-001] | `notifications.show` | Toast, green/red |
| Stepper [stp-001] | `Stepper` | Multi-step onboarding |

### Overlay Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Modal [mdl-001] | `Modal` | `centered`, sizes sm–xl |
| Drawer [drw-001] | `Drawer` | Board task panel |
| Menu [mnu-001] | `Menu` | Context actions |
| Popover [pop-001] | `Popover` | Emoji picker |
| Tooltip [tip-001] | `Tooltip` | Action hints |

### Navigation Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| NavLink [nav-001] | `NavLink` | Sidebar navigation |
| Tabs [tab-001] | `Tabs` | Content switching |
| Accordion [acc-001] | `Accordion` | `variant="contained"` |

### Typography Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| Text [txt-001] | `Text` | Body copy |
| Title [txt-002] | `Title` | Page/section headings |

### Decoration Components

| WDS | Mantine | Notes |
|-----|---------|-------|
| ThemeIcon [ico-001] | `ThemeIcon` | Variants: light, gradient |

---

## Theme Source File

**Location:** `app/frontend/shared/theme/mantineTheme.ts`

**Exports:**
- `mantineTheme` — createTheme configuration
- `cssVariablesResolver` — custom CSS variables mapper

---

## Library Documentation

**Official Docs:** https://mantine.dev
**Component Gallery:** https://mantine.dev/core/button
**GitHub:** https://github.com/mantinedev/mantine
