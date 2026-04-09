# Layout Components

---

## Application Shell

**Type:** Layout
**Category:** Structure
**Custom Implementation** (not Mantine AppShell)

### Overview

The app uses a custom layout built with `Box` + CSS Modules instead of Mantine's `AppShell`. This provides full control over the dark-theme chrome.

### Structure

```
InertiaAuthLayout
├── AppHeader (48px, fixed top)
│   ├── Logo
│   ├── Project Switcher
│   ├── Navigation (home, projects)
│   └── User Menu (avatar, settings, logout)
├── Body Row (flex)
│   ├── AppSidebar (220px / 56px collapsed)
│   │   ├── Project name
│   │   ├── NavLinks (ScrollArea)
│   │   └── Collapse toggle
│   └── Main Content
│       ├── <main> with padding 24px 32px
│       └── Optional Footer (Logo + "Powered by")
└── Flash → Notifications
```

### Guest Layout

```
InertiaGuestLayout
└── Center (full viewport)
    └── Container size="xs"
        └── {children}
```

### Login Layout

Custom full-viewport centered layout with radial gradient background (not using InertiaGuestLayout).

---

## Stack [layout-stack]

**Library:** Mantine `Stack`
**Purpose:** Vertical content arrangement

```yaml
default-gap: 'md' (16px)
usage:       form fields, page sections, modal content
```

---

## Group [layout-group]

**Library:** Mantine `Group`
**Purpose:** Horizontal content arrangement

```yaml
common-gaps:  'xs' (10px), 'sm' (12px), 'md' (16px)
justify:      'flex-start' (default), 'flex-end' (action bars), 'space-between' (headers)
usage:        button groups, action bars, inline labels
```

---

## SimpleGrid [layout-grid]

**Library:** Mantine `SimpleGrid`
**Purpose:** Auto-responsive grid

```yaml
common-cols: { base: 1, sm: 2, lg: 3 }
usage:       project cards, workflow cards, dashboard stat blocks
```

---

## ScrollArea [layout-scroll]

**Library:** Mantine `ScrollArea`
**Purpose:** Custom scrollbar container

```yaml
usage: sidebar navigation, long form panels, code output views
```

---

## Center [layout-center]

**Library:** Mantine `Center`
**Purpose:** Center content vertically and horizontally

```yaml
usage: loading states, empty states, guest layout
```

---

## Divider [layout-divider]

**Library:** Mantine `Divider`
**Purpose:** Visual separator between sections

```yaml
color:  var(--mantine-color-dark-4)
usage:  login form sections, profile sections, sidebar groups
```

---

## Layout Tokens

```yaml
page-bg:         var(--app-bg-default) / #0D0D0D
header-height:   48px
header-bg:       var(--app-bg-paper) / #141414
header-border:   1px solid var(--app-border-default)
sidebar-width:   220px
sidebar-collapsed: 56px
sidebar-bg:      var(--app-bg-elevated) / #1A1A1A
sidebar-border:  1px solid var(--app-border-default)
main-padding-v:  24px
main-padding-h:  32px
footer-height:   auto
```

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
