# Aixle — Design Tokens

**Last Updated:** 2026-04-03
**Source:** `app/frontend/shared/theme/mantineTheme.ts`
**Token Count:** 94
**Color Scheme:** Dark (default)

---

## Colors

### Blue (Primary)

```yaml
blue-0: '#e7f0ff'
blue-1: '#cddcfb'
blue-2: '#9bb6f3'
blue-3: '#6590ec'
blue-4: '#3B82F6'   # ← main accent
blue-5: '#2570e4'
blue-6: '#1d66dc'
blue-7: '#1255c4'
blue-8: '#064bb0'
blue-9: '#003f9b'
```

**CSS:** `var(--mantine-color-blue-4)` through `var(--mantine-color-blue-9)`

### Green (Success)

```yaml
green-0: '#e5fbed'
green-1: '#cef5da'
green-2: '#9eeab5'
green-3: '#6bdf8c'
green-4: '#22C55E'   # ← main
green-5: '#2db854'
green-6: '#26a94a'
green-7: '#1a953d'
green-8: '#0d8534'
green-9: '#007327'
```

### Red (Error / Danger)

```yaml
red-0: '#ffe7e7'
red-1: '#fecece'
red-2: '#f99c9c'
red-3: '#f46565'
red-4: '#EF4444'   # ← main
red-5: '#ec2525'
red-6: '#eb1414'
red-7: '#d20707'
red-8: '#bc0003'
red-9: '#a40000'
```

### Amber (Warning)

```yaml
amber-0: '#fff8e1'
amber-1: '#ffefcb'
amber-2: '#ffdd9a'
amber-3: '#ffcb64'
amber-4: '#F59E0B'   # ← main
amber-5: '#f0a700'
amber-6: '#db9800'
amber-7: '#c08400'
amber-8: '#aa7500'
amber-9: '#906200'
```

### Dark (UI Chrome)

```yaml
dark-0: '#C1C2C5'
dark-1: '#A6A7AB'
dark-2: '#909296'
dark-3: '#5C5F66'
dark-4: '#373A40'
dark-5: '#2C2E33'
dark-6: '#1A1A1A'   # ← elevated
dark-7: '#141414'   # ← paper
dark-8: '#0D0D0D'   # ← default bg
dark-9: '#0A0A0A'   # ← deepest
```

### Semantic Backgrounds (Custom)

```yaml
--app-bg-default:  '#0D0D0D'   # Page background
--app-bg-paper:    '#141414'   # Cards, panels
--app-bg-elevated: '#1A1A1A'   # Raised surfaces, sidebar
--app-bg-deep:     '#0A0A0A'   # Deepest layer
```

### Semantic Borders (Custom)

```yaml
--app-border-default: '#2A2A2A'   # Standard borders
--app-border-subtle:  '#1F1F1F'   # Minimal separation
--app-border-strong:  '#3A3A3A'   # Emphasized borders
```

### Semantic Text (Custom)

```yaml
--app-text-primary:   '#FFFFFF'   # Primary content
--app-text-secondary: '#A0A0A0'   # Secondary, descriptions
--app-text-muted:     '#666666'   # Hints, placeholders
```

### Action States (Custom)

```yaml
--app-action-hover:    'rgba(255, 255, 255, 0.08)'   # Hover overlay
--app-action-selected: 'rgba(59, 130, 246, 0.16)'    # Selected state (blue tint)
```

### Status Colors

```yaml
status-completed:    '#22C55E'   # Green
status-running:      '#3B82F6'   # Blue
status-running-other: '#F59E0B'  # Amber
status-pending:      '#666666'   # Muted
status-error:        '#EF4444'   # Red
```

### Agent Brand Colors

```yaml
agent-codex:      '#10A37F'   # OpenAI Codex green
agent-cursor-cli: '#7C3AED'   # Cursor purple
agent-gemini-cli: '#3B82F6'   # Gemini blue
agent-claude-code: '#D97706'  # Claude amber
```

---

## Typography

### Font Families

```yaml
--mantine-font-family: 'Poppins, sans-serif'       # Headings + UI chrome
--app-font-body:       'Inter, sans-serif'          # Body text, forms, labels
font-mono:             'JetBrains Mono, monospace'  # Code blocks (loaded per-page)
```

**Font Loading (Google Fonts):**
- Inter: weights 300–700
- Poppins: full weight range

### Font Sizes (Mantine scale)

```yaml
text-xs:   0.75rem    # 12px — badges, hints
text-sm:   0.875rem   # 14px — body, labels, descriptions
text-md:   1rem       # 16px — standard
text-lg:   1.125rem   # 18px
text-xl:   1.25rem    # 20px — section titles
text-2xl:  1.5rem     # 24px
text-3xl:  1.875rem   # 30px
text-4xl:  2.25rem    # 36px — page titles
```

### Font Weights

```yaml
font-normal:   400   # Body text
font-medium:   500   # Labels
font-semibold: 600   # Active nav, headings
font-bold:     700   # Page titles
```

### Common In-Code Sizes

```yaml
sidebar-nav:     13px / font-weight 600 (active)
header-buttons:  13px
settings-title:  20px
settings-desc:   14px
board-code:      JetBrains Mono
```

---

## Spacing

### Mantine Spacing Scale

```yaml
xs:  0.625rem    # 10px
sm:  0.75rem     # 12px
md:  1rem        # 16px
lg:  1.25rem     # 20px
xl:  1.5rem      # 24px
```

### Layout Spacing (Custom)

```yaml
main-padding-v:      24px    # Main content vertical
main-padding-h:      32px    # Main content horizontal
header-padding-h:    16px    # Header horizontal
sidebar-nav-margin:  8px     # Nav item margin
sidebar-link-pad-h:  12px    # Link horizontal padding
settings-field-mb:   20px    # Form field margin-bottom
settings-actions-mt: 24px    # Actions margin-top
card-padding:        32px    # Profile, settings cards
```

---

## Layout

### Breakpoints (Mantine defaults)

```yaml
xs:  36em     # 576px
sm:  48em     # 768px
md:  62em     # 992px
lg:  75em     # 1200px
xl:  88em     # 1408px
```

### Shell Dimensions

```yaml
header-height:       48px
sidebar-width:       220px
sidebar-collapsed:   56px
```

---

## Effects

### Border Radius

```yaml
--mantine-radius-xs:   0.125rem   # 2px
--mantine-radius-sm:   0.25rem    # 4px — sidebar, header chrome
--mantine-radius-md:   0.5rem     # 8px — default (theme.defaultRadius)
--mantine-radius-lg:   1rem       # 16px
--mantine-radius-xl:   2rem       # 32px — avatars, ThemeIcon
radius-project-card:   12px       # Custom card radius
radius-settings-card:  12px       # Custom card radius
radius-code-block:     3px–6px    # Board markdown
```

### Shadows

```yaml
--mantine-shadow-xs:    '0 1px 3px rgba(0, 0, 0, 0.05), ...'
--mantine-shadow-sm:    '0 1px 3px rgba(0, 0, 0, 0.05), rgba(0, 0, 0, 0.05) 0 10px 15px -5px, ...'
--mantine-shadow-md:    '...'     # Menus, popovers
--mantine-shadow-lg:    '...'     # Draggable cards

# Custom shadows
shadow-login-card:      '0 8px 32px rgba(0, 0, 0, 0.4)'
shadow-project-hover:   '0 8px 24px rgba(0, 0, 0, 0.3)'
shadow-onboard-hover:   '0 4px 12px rgba(0, 0, 0, 0.3)'
```

### Transitions

```yaml
transition-fast:  150ms    # Hover states
transition-base:  200ms    # Standard interactions
transition-slow:  300ms    # Complex animations
```

### Animations

```yaml
fadeSlideUp:      translateY(20px) → translateY(0), opacity 0→1   # Login card
workflowPulse:    Board column header keyframes
route-indicator:  Progress bar animated stripe (InertiaRouteIndicator)
```

**Accessibility:** All animations respect `@media (prefers-reduced-motion: reduce)`.

---

## CSS Variables Summary

### Custom App Variables (via cssVariablesResolver)

| Variable | Value | Category |
|----------|-------|----------|
| `--app-font-body` | `Inter, sans-serif` | Typography |
| `--app-bg-default` | `#0D0D0D` | Background |
| `--app-bg-paper` | `#141414` | Background |
| `--app-bg-elevated` | `#1A1A1A` | Background |
| `--app-bg-deep` | `#0A0A0A` | Background |
| `--app-border-default` | `#2A2A2A` | Border |
| `--app-border-subtle` | `#1F1F1F` | Border |
| `--app-border-strong` | `#3A3A3A` | Border |
| `--app-text-primary` | `#FFFFFF` | Text |
| `--app-text-secondary` | `#A0A0A0` | Text |
| `--app-text-muted` | `#666666` | Text |
| `--app-action-hover` | `rgba(255,255,255,0.08)` | Action |
| `--app-action-selected` | `rgba(59,130,246,0.16)` | Action |

### Mantine Built-in Variables (frequently used in CSS modules)

| Variable | Usage |
|----------|-------|
| `--mantine-color-dark-*` | Borders, backgrounds in dark mode |
| `--mantine-color-blue-*` | Accent highlights |
| `--mantine-radius-*` | Border radius |
| `--mantine-shadow-*` | Elevation |
| `--mantine-spacing-*` | Gaps, padding |

---

**Tokens are extracted from the live codebase and reflect the current Inertia + Mantine implementation.**
