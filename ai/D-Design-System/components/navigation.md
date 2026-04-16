# Navigation Components

---

## NavLink [nav-001]

**Type:** Navigation
**Category:** Sidebar
**Library:** Mantine `NavLink`
**Purpose:** Sidebar navigation items with active state

### Overview

NavLink is used exclusively in `AppSidebar` for project-level navigation. Each link has an icon (`leftSection`), label, and active state tracking.

### Styling

```yaml
nav-height:       36px
nav-font-size:    13px
nav-font-active:  font-weight 600
nav-radius:       4px (var(--mantine-radius-sm))
nav-padding-h:    12px
nav-margin:       0 8px
nav-hover-bg:     var(--app-action-hover)
nav-active-bg:    var(--app-action-selected)
nav-active-color: var(--mantine-color-blue-4)
```

### Sidebar Structure

```
AppSidebar (220px / 56px collapsed)
├── Project name + switcher
├── NavLink: Overview
├── NavLink: Board
├── NavLink: Workflows
├── NavLink: Sessions
├── NavLink: Aixle Builder
├── NavLink: Analytics
├── Divider
├── NavLink: Agents
├── NavLink: Tools
├── NavLink: Skills
├── NavLink: MCP Servers
├── NavLink: Config Items
├── NavLink: Integrations
├── NavLink: Repositories
├── NavLink: Assets
├── Divider
├── NavLink: Members
└── NavLink: Settings
```

---

## Tabs [tab-001]

**Type:** Navigation
**Category:** Content Switching
**Library:** Mantine `Tabs`
**Purpose:** Switch between content panels within a page

### Overview

Tabs are used for in-page content switching: Board views, tool form sections, workflow run details, and Aixle Builder panels.

### Styling

```yaml
tabs-border:      var(--mantine-color-dark-4)
tabs-active:      var(--mantine-color-blue-6) underline
tabs-font-size:   14px
```

### Used In

- BoardPage → task views
- ToolFormModal → configuration tabs
- WorkflowRuns ShowPage → output tabs
- Aixle Builder SessionPage → context panels

---

## Accordion [acc-001]

**Type:** Navigation
**Category:** Expandable
**Library:** Mantine `Accordion`
**Purpose:** Collapsible content sections

### Variant

`variant="contained"` — used in both workflow builder pages for step configuration.

---

## Menu [mnu-001]

**Type:** Overlay
**Category:** Context Actions
**Library:** Mantine `Menu`
**Purpose:** Dropdown context menus for entity actions

### Used In

- RepositoriesContent → row actions
- MembersContent → role management
- IntegrationsContent → integration actions
- AppHeader → user menu, project switcher

---

## Version History

**Created:** 2026-04-03
**Last Updated:** 2026-04-03
