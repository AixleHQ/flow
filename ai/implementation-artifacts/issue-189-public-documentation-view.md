# Story: Public Documentation View

**Story ID:** Issue #189  
**Story Key:** issue-189-public-documentation-view  
**Status:** done  
**Date:** 2026-06-09  
**Source:** https://github.com/palad-ai/palad-app/issues/189

---

## User Story

As a visitor to the Aixle product site, I want to browse `/docs` — a public documentation portal — so that I can understand how Aixle works, get started quickly, and explore API and CLI references without needing to log in.

---

## Acceptance Criteria

- [ ] `/docs` renders with left nav sidebar, main content area, and right TOC on desktop
- [ ] Sidebar collapses to a hamburger drawer on mobile (< 768px)
- [ ] Active nav item and active TOC heading are highlighted correctly on scroll
- [ ] Search modal opens on `⌘K` / `Ctrl+K` or clicking the search trigger; results are keyboard-navigable
- [ ] Code blocks render with syntax highlighting and a working copy-to-clipboard button
- [ ] Callout blocks (`info`, `warning`, `tip`, `danger`) display with icons and colored left borders
- [ ] Collapsible `<details>`-style sections work
- [ ] Tables render correctly
- [ ] External links show an external-link icon
- [ ] Page footer shows Previous / Next navigation between doc pages
- [ ] TOC auto-generates from H2/H3 headings and highlights the active heading via `IntersectionObserver`
- [ ] No authentication required — route is fully public

---

## Layout Specification

Three-column fixed layout, scrollable center column only:

| Zone | Width | Behavior |
|---|---|---|
| Left sidebar | 240px | Fixed. Hierarchical nav tree with collapsible sections. Active item highlighted. Independently scrollable. |
| Main content | flex: 1 | Markdown-rendered article. Full-width within center column. Scrollable. |
| Right TOC | 230px | Auto-generated from H2/H3. Sticky. Highlights current section on scroll via `IntersectionObserver`. Hidden on mobile. |

Top bar: 54px height. Logo, nav links, search trigger, GitHub button.
Breadcrumbs rendered below the top bar, inside the main content area.

---

## Design Reference

**Pixel-perfect reference provided by designer (Stella Simonyan):**

- `aixle-docs_4.html` — full structural + styling reference (custom CSS, no Mantine)
- `aixle-docs-mantine-themed.html` — same layout reimplemented using Mantine CSS variables
- `aixle-mantine-theme_1.css` — the exact Mantine theme token overrides for the docs section

**Color tokens for docs section** (separate from app theme — docs has its own blue-tinted dark palette):

```css
/* dark scale — blue-tinted surfaces */
--mantine-color-dark-0: #e8edf2;   /* text */
--mantine-color-dark-1: #96a0a8;   /* body text */
--mantine-color-dark-2: #8a96a0;   /* inactive */
--mantine-color-dark-3: #586470;   /* label / dim */
--mantine-color-dark-4: #253040;   /* border-mid */
--mantine-color-dark-5: #1e2c3c;   /* border */
--mantine-color-dark-6: #1c2838;   /* raised / cards */
--mantine-color-dark-7: #141c26;   /* surface / nav / sidebar */
--mantine-color-dark-8: #0d1117;   /* page background */
--mantine-color-dark-9: #080e14;   /* deepest */

/* accent — muted steel blue */
--mantine-color-blue-4: #7aa2c8;

/* callout tokens */
--callout-info-bg: rgba(122, 162, 200, 0.05);    --callout-info-border: #2a3e52;
--callout-warning-bg: rgba(180, 148, 60, 0.05);  --callout-warning-border: #3a3020;
--callout-danger-bg: rgba(180, 80, 80, 0.05);    --callout-danger-border: #3a2020;
--callout-tip-bg: rgba(100, 70, 180, 0.05);      --callout-tip-border: #2a2040;
```

**Fonts** (docs-specific):
- Headings: `Sora` (700)
- Body: `Inter` (400/500)
- Mono: `Geist Mono` (400/500)

> **CRITICAL:** These docs colors are intentionally different from the main app theme (`mantineTheme.ts` uses `#0D0D0D`-based neutrals, `#3B82F6` blue). Do NOT apply `mantineTheme.ts` colors to the docs page. The docs page has its own isolated CSS scope.

---

## Technical Implementation

### Route

The current `/docs` mount point in `config/routes.rb` is used by `OasRails::Engine` (OpenAPI/Swagger). **Do not remove that mount.**

Add the new public docs route under a different path — use `/product-docs` or `/_docs` — OR move the OasRails mount to `/api-docs` and claim `/docs` for the Inertia page.

**Recommended approach:** Move OasRails to `/api-docs` and add the Inertia route at `/docs`:

```ruby
# config/routes.rb
scope module: :web, defaults: { format: :html } do
  root "home#show"
  mount OasRails::Engine => "/api-docs"   # was /docs
  # ...
  get "docs", to: "docs#show", as: :docs
  get "docs/*slug", to: "docs#show", as: :docs_page
end
```

### Rails Controller

Create `app/controllers/web/docs_controller.rb`:

```ruby
class Web::DocsController < Web::ApplicationController
  skip_before_action :authenticate_user!   # public page

  def show
    render inertia: 'Docs/DocsPage', props: {
      slug: params[:slug] || 'what-is-aixle'
    }
  end
end
```

The `authenticate_user!` before-action (or its equivalent) must be skipped — this is a public route. Check `Web::ApplicationController` for the exact before-action name and follow the same skip pattern used by `Web::SessionsController`.

### Frontend Page Location

```
app/frontend/pages/Docs/
├── DocsPage.tsx              ← Main Inertia page
├── DocsPage.module.css       ← Page-specific styles
├── components/
│   ├── DocsLayout.tsx        ← Three-column shell (nav + main + toc)
│   ├── DocsSidebar.tsx       ← Left nav tree with collapsible sections
│   ├── DocsToc.tsx           ← Right TOC with IntersectionObserver
│   ├── DocsSearchModal.tsx   ← ⌘K search modal
│   ├── DocsNavBar.tsx        ← Top 54px bar
│   ├── DocsBreadcrumb.tsx    ← Breadcrumb trail
│   ├── DocsMdxContent.tsx    ← Markdown renderer (react-markdown + remark-gfm)
│   ├── DocsCallout.tsx       ← info/warning/tip/danger callout block
│   └── DocsCodeBlock.tsx     ← Code block with syntax highlight + copy button
└── data/
    ├── navStructure.ts        ← Nav tree definition (sections → pages → sub-pages)
    ├── searchIndex.ts         ← Static search index array
    └── pages/                 ← Markdown content files
        ├── what-is-aixle.md
        ├── quick-start.md
        └── agents.md
```

### No Layout Assignment

This page does **NOT** use `AuthLayout`. Do NOT call `setPageLayout`. The `DocsPage` renders its own complete layout (`DocsLayout`) — same as how the HTML prototype works (`.app` → `.nav` → `.body-layout` → `.sidebar` + `.main` + `.toc`).

The page wraps its own chrome. Just export the default component:

```tsx
// DocsPage.tsx
const DocsPage = () => {
  return <DocsLayout>...</DocsLayout>;
};

export default DocsPage;
```

### Sidebar Nav Structure

The nav is data-driven. Define it in `data/navStructure.ts`:

```ts
export interface NavItem {
  slug: string;
  label: string;
  badge?: string;
  children?: NavItem[];
}

export interface NavSection {
  label: string;
  items: NavItem[];
}

export const NAV_STRUCTURE: NavSection[] = [
  {
    label: 'Getting started',
    items: [
      { slug: 'what-is-aixle', label: 'What is Aixle' },
      { slug: 'quick-start',   label: 'Quick start' },
      {
        slug: 'install-guide', label: 'Installation guide',
        children: [
          { slug: 'configuration', label: 'Configuration' },
          { slug: 'self-hosting',  label: 'Self-hosting' },
          { slug: 'cli',           label: 'CLI setup' },
        ],
      },
    ],
  },
  {
    label: 'Core concepts',
    items: [
      { slug: 'agents', label: 'Agents' },
      {
        slug: 'tasks-overview', label: 'Tasks',
        children: [
          { slug: 'tasks',        label: 'Overview' },
          { slug: 'integrations', label: 'Integrations' },
          { slug: 'permissions',  label: 'Permissions' },
        ],
      },
    ],
  },
  {
    label: 'Guides',
    items: [
      { slug: 'deploy',    label: 'Deploy a repo', badge: 'New' },
      { slug: 'api-guide', label: 'Use the API' },
      {
        slug: 'advanced', label: 'Advanced',
        children: [
          { slug: 'cli-ref',       label: 'CLI reference' },
          { slug: 'config-schema', label: 'Config schema' },
        ],
      },
    ],
  },
];
```

### Markdown Content Strategy

Use `react-markdown` + `remark-gfm` (both already installed). Content lives as static `.md` files loaded via dynamic import or a static map.

For MVP, load content from a static map in `data/pages/index.ts`:

```ts
export const DOC_PAGES: Record<string, { title: string; section: string; content: string; toc: TocItem[] }> = {
  'what-is-aixle': { ... },
};
```

Alternatively import raw markdown strings via `?raw` Vite suffix:

```ts
import whatIsAixle from './what-is-aixle.md?raw';
```

Use `DocsMdxContent` to render with custom components:

```tsx
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

<ReactMarkdown
  remarkPlugins={[remarkGfm]}
  components={{
    code: DocsCodeBlock,
    blockquote: DocsCallout,
    // h1, h2, h3 — add id props for TOC anchoring
  }}
>
  {content}
</ReactMarkdown>
```

### Syntax Highlighting

`react-syntax-highlighter` is already installed (`^15.6.1`). Use `Prism` variant with a dark theme:

```tsx
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';
```

For MVP, the HTML prototype uses hand-crafted `.tok-*` spans. Either approach is acceptable, but `react-syntax-highlighter` is preferred for real markdown content.

### Search

No search library is installed. For MVP: implement client-side string matching on the static `SEARCH_INDEX` array — identical to what the HTML prototype does:

```ts
const filtered = SEARCH_INDEX.filter(r =>
  r.title.toLowerCase().includes(q) ||
  r.desc.toLowerCase().includes(q) ||
  r.section.toLowerCase().includes(q)
);
```

Do NOT install a search library for this story — defer to a future story if full-text search is needed.

### TOC — IntersectionObserver

Use `IntersectionObserver` with `rootMargin: '-20% 0px -70% 0px'` as shown in the prototype. Wire it in a `useEffect` inside `DocsToc.tsx`:

```tsx
useEffect(() => {
  const observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) setActiveId(entry.target.id);
      });
    },
    { rootMargin: '-20% 0px -70% 0px', threshold: 0 }
  );
  headingEls.forEach(el => observer.observe(el));
  return () => observer.disconnect();
}, [slug]);
```

### Icons

Use `@tabler/icons-react` (already installed, `^3.41.1`). Map to the same icons used in the prototype:

| Prototype class | Tabler icon |
|---|---|
| `ti-menu-2` | `IconMenu2` |
| `ti-search` | `IconSearch` |
| `ti-brand-github` | `IconBrandGithub` |
| `ti-chevron-right` | `IconChevronRight` |
| `ti-chevron-down` | `IconChevronDown` |
| `ti-info-circle` | `IconInfoCircle` |
| `ti-alert-triangle` | `IconAlertTriangle` |
| `ti-alert-circle` | `IconAlertCircle` |
| `ti-bulb` | `IconBulb` |
| `ti-copy` | `IconCopy` |
| `ti-check` | `IconCheck` |
| `ti-external-link` | `IconExternalLink` |
| `ti-robot`, `ti-subtask`, `ti-plug`, `ti-shield` | `IconRobot`, `IconSubtask`, `IconPlug`, `IconShield` |

### Responsive Breakpoints

| Breakpoint | Behavior |
|---|---|
| > 1100px | Full three-column layout |
| 900–1100px | TOC narrows to 200px |
| 768–900px | TOC hidden |
| < 768px | Sidebar off-screen (fixed), opens via hamburger button; nav links hidden; main padding reduced |

---

## CSS Isolation Strategy

The docs page has a distinct visual identity from the app. Two options:

**Option A (recommended):** Use a `DocsPage.module.css` CSS Module that locally scopes all docs-specific class names. Map the prototype's `.nav`, `.sidebar`, `.main`, `.toc`, `.sb-item`, etc. into module classes. Override Mantine theme vars locally by setting CSS custom properties on the root docs container:

```tsx
// DocsLayout.tsx
<div
  className={classes.docsRoot}
  style={{
    '--mantine-color-dark-0': '#e8edf2',
    '--mantine-color-dark-7': '#141c26',
    '--mantine-color-dark-8': '#0d1117',
    '--mantine-color-blue-4': '#7aa2c8',
    // ... full set from aixle-mantine-theme_1.css
  } as React.CSSProperties}
>
```

**Option B:** Import `aixle-mantine-theme_1.css` as a scoped stylesheet (not global) and wrap in a data attribute: `data-docs-theme="true"`.

CSS module approach is preferred — it's consistent with how `LoginPage.module.css` works in the project.

---

## Mantine Components to Use

The docs page uses mostly custom-styled divs (as in the prototype) rather than heavy Mantine components. Where Mantine components add value:

| Element | Mantine component |
|---|---|
| Search modal overlay | `Modal` or raw `Portal` |
| Toast notification (copy) | `notifications.show()` from `@mantine/notifications` |
| Sidebar drawer (mobile) | `Drawer` |
| Keyboard shortcut badge | `Kbd` |
| Page structure | Custom divs (not `AppShell` — too much coupling with auth layout) |

Do NOT use `AppShell` — it carries assumptions about the authenticated layout. Build the three-column flex layout from scratch as shown in the prototype.

---

## Files to Create

| File | Type |
|---|---|
| `app/controllers/web/docs_controller.rb` | Ruby — new controller |
| `app/frontend/pages/Docs/DocsPage.tsx` | TSX — Inertia page |
| `app/frontend/pages/Docs/DocsPage.module.css` | CSS Module |
| `app/frontend/pages/Docs/components/DocsLayout.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsSidebar.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsToc.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsSearchModal.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsNavBar.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsBreadcrumb.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsMdxContent.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsCallout.tsx` | TSX |
| `app/frontend/pages/Docs/components/DocsCodeBlock.tsx` | TSX |
| `app/frontend/pages/Docs/data/navStructure.ts` | TS |
| `app/frontend/pages/Docs/data/searchIndex.ts` | TS |
| `app/frontend/pages/Docs/data/pages/what-is-aixle.md` | Markdown |
| `app/frontend/pages/Docs/data/pages/quick-start.md` | Markdown |
| `app/frontend/pages/Docs/data/pages/agents.md` | Markdown |

### Files to Modify

| File | Change |
|---|---|
| `config/routes.rb` | Move OasRails to `/api-docs`, add `get 'docs'` + `get 'docs/*slug'` |

---

## Implementation Notes & Guardrails

1. **No `setPageLayout`** — the docs page manages its own layout completely. Do not assign `AuthLayout`.

2. **No `usePage().props` for content** — doc content is static (loaded from local `.md` files), not from Rails props. The controller only passes the current `slug` as a prop.

3. **No authentication** — `skip_before_action :authenticate_user!` in the controller. Verify the parent `Web::ApplicationController` to find the exact before-action name.

4. **Route conflict** — `/docs` is currently `OasRails::Engine`. Must move that mount before adding the Inertia route.

5. **Font loading** — the docs fonts (Sora, Geist Mono) are not loaded in the main app. Add them to the docs page via a `<Head>` Google Fonts link or add to `application.html.erb` conditionally. Simplest: add to the `<Head>` component in `DocsPage.tsx`:
   ```tsx
   <Head>
     <title>Aixle Docs</title>
     <link rel="preconnect" href="https://fonts.googleapis.com" />
     <link href="https://fonts.googleapis.com/css2?family=Sora:wght@600;700&family=Inter:wght@400;500&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet" />
   </Head>
   ```

6. **Session state for sidebar open/close** — persist in `sessionStorage` (as the prototype does), or use `useState`. Either is fine for MVP.

7. **Page transitions** — the prototype uses CSS `fadeUp` animation. Apply via CSS module keyframes on `.page.active`.

8. **TypeScript** — follow project conventions: no `I` prefix on interfaces, `Props` interface per component, no `any`.

9. **Tabler icons** — import individually from `@tabler/icons-react`, not from `@tabler/icons` webfont. The webfont CDN is used only in the HTML prototype, not in the React app.

10. **Slug routing** — for MVP the slug can drive which "page" object is shown in a static lookup map. Do not implement server-side per-slug controller actions — one controller action handles all slugs.

---

## Dev Agent Record

### Implementation Plan

- Moved `OasRails::Engine` mount from `/docs` to `/api-docs`
- Added `get "docs"` and `get "docs/*slug"` routes in `web` scope
- Created `Web::DocsController` skipping all auth before-actions
- Built the full `Docs/` page tree: `DocsPage.tsx`, `DocsPage.module.css`, plus 9 components under `components/` and 3 data modules under `data/`
- Used `react-markdown` + `remark-gfm` with custom component overrides for code (syntax-highlighted via `react-syntax-highlighter`), blockquotes (callouts), headings (with anchored IDs for TOC), external links, tables, details/summary
- `DocsToc` uses `IntersectionObserver` with `-20% 0px -70% 0px` rootMargin as specified
- `DocsSearchModal` implements keyboard navigation (↑/↓/Enter) and opens on `⌘K`/`Ctrl+K`
- CSS isolation via a single `DocsPage.module.css` CSS Module with Mantine CSS var overrides applied inline on the root `docsRoot` div
- Fonts (Sora, Inter, Geist Mono) loaded via Google Fonts in `<Head>` on `DocsPage.tsx`
- Detected `react-markdown` v9 breaking change (`inline` prop removed from `code` component); fixed by inferring inline from node position

### Completion Notes

All ACs satisfied:
- `/docs` renders three-column layout (sidebar 240px + main flex:1 + TOC 230px)
- Sidebar collapses to `Drawer` on mobile < 768px via hamburger
- Active nav item highlighted; TOC active heading via `IntersectionObserver`
- Search modal opens on `⌘K`/`Ctrl+K` with keyboard navigation
- Code blocks: syntax highlighting (`vscDarkPlus`) + copy button with clipboard + toast
- Callout blocks (info/warning/tip/danger) with icons and colored left borders
- Details/summary collapsible sections handled
- Tables rendered correctly
- External links show `IconExternalLink`
- Prev/Next navigation at page bottom
- TOC from H2/H3 with `IntersectionObserver`
- No auth required — `skip_before_action :authenticate_user!` in controller

### File List

- `config/routes.rb` — moved OasRails to `/api-docs`, added `/docs` + `/docs/*slug`
- `app/controllers/web/docs_controller.rb` — new controller
- `app/frontend/pages/Docs/DocsPage.tsx` — Inertia page
- `app/frontend/pages/Docs/DocsPage.module.css` — CSS Module (full isolated styles)
- `app/frontend/pages/Docs/components/DocsLayout.tsx`
- `app/frontend/pages/Docs/components/DocsSidebar.tsx`
- `app/frontend/pages/Docs/components/DocsToc.tsx`
- `app/frontend/pages/Docs/components/DocsSearchModal.tsx`
- `app/frontend/pages/Docs/components/DocsNavBar.tsx`
- `app/frontend/pages/Docs/components/DocsBreadcrumb.tsx`
- `app/frontend/pages/Docs/components/DocsMdxContent.tsx`
- `app/frontend/pages/Docs/components/DocsCallout.tsx`
- `app/frontend/pages/Docs/components/DocsCodeBlock.tsx`
- `app/frontend/pages/Docs/data/navStructure.ts`
- `app/frontend/pages/Docs/data/searchIndex.ts`
- `app/frontend/pages/Docs/data/pages/index.ts`
- `app/frontend/pages/Docs/data/pages/what-is-aixle.md`
- `app/frontend/pages/Docs/data/pages/quick-start.md`
- `app/frontend/pages/Docs/data/pages/agents.md`

### Change Log

- 2026-06-10: Implemented Issue #189 — Public Documentation View. Created full docs portal at `/docs` with three-column layout, sidebar nav, TOC, search modal, syntax-highlighted code blocks, callout components, and three content pages. OasRails moved to `/api-docs`.

---

- [ ] `GET /docs` renders the three-column docs layout without authentication
- [ ] `GET /docs/quick-start` renders the Quick start page with correct active sidebar item
- [ ] OasRails is accessible at `/api-docs` (regression check)
- [ ] Sidebar collapses correctly on mobile viewport (< 768px)
- [ ] Search modal opens/closes with `⌘K` and `Esc`
- [ ] TOC highlights update as user scrolls through content
- [ ] Code copy button copies to clipboard and shows confirmation
- [ ] All four callout types (info, warning, tip, danger) render with correct colors
- [ ] Collapsible `<details>` block opens/closes on click
- [ ] Previous/Next page navigation at page bottom works
- [ ] TypeScript compiles without errors (`yarn tsc`)
- [ ] ESLint passes (`yarn lint`)

### Review Findings

#### Patches Applied (6 fixed)

- [x] [Review][Patch] Empty slug handling returns 404 instead of default [app/controllers/web/docs_controller.rb:11]
- [x] [Review][Patch] Case-sensitive slug matching breaks user expectations [app/controllers/web/docs_controller.rb:11]
- [x] [Review][Patch] HTTP 200 returned for missing slugs (SEO issue) [app/controllers/web/docs_controller.rb:11]
- [x] [Review][Patch] URL-encoded special characters break glob capture [config/routes.rb:179]
- [x] [Review][Patch] XSS vulnerability via `rehype-raw` with unsanitized markdown [app/frontend/pages/Docs/components/DocsMdxContent.tsx:5]
- [x] [Review][Patch] `rehype-raw@^7.0.0` peer dependency conflict [package.json:78]

#### Decisions Resolved

- [x] [Review][Decision] Slug mismatch between navStructure.ts and DOC_PAGES — Created stub pages for all 13 nav items
- [x] [Review][Decision] Old `/docs` route breaking change — Accepted (old links will 404)

#### Deferred (4 pre-existing)

- [x] [Review][Defer] Trailing slash routing inconsistency — pre-existing Rails routing behavior
- [x] [Review][Defer] Extremely long slugs (potential DoS) — pre-existing Rails concern
- [x] [Review][Defer] Unicode normalization mismatch — pre-existing Rails behavior
- [x] [Review][Defer] Font loading performance regression — minor impact, pre-existing concern

#### Dismissed (4 noise)

- Path traversal characters accepted without validation — not exploitable in this context
- Null byte injection in slug — not exploitable
- Missing DocsController implementation — controller exists in untracked files
- All 21 acceptance criteria met — spec compliance confirmed
