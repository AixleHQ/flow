# Frontend Stack: Inertia.js + UI Library Comparison

> Research for migrating from the current SPA stack (Rails API + React Router + Redux + MUI) to Inertia.js + a new UI library.
>
> Date: April 2, 2026

---

## Contents

1. [Current stack and problems](#current-stack-and-problems)
2. [Inertia.js for Rails](#inertiajs-for-rails)
3. [Comparison of UI libraries](#comparison-of-ui-libraries)
4. [Detailed analysis of each library](#detailed-analysis-of-each-library)
5. [Context: the Hexlet experience](#context-the-hexlet-experience)
6. [Recommendations](#recommendations)
7. [Advanced Inertia.js + Rails patterns](#advanced-inertiajs--rails-patterns)
   - [WebSockets and Live Updates via ActionCable](#websockets-and-live-updates-via-actioncable)
   - [Partial Reloads and Deferred Props](#partial-reloads-and-deferred-props)
   - [Typelizer: automatic TypeScript types from Rails](#typelizer-automatic-typescript-types-from-rails)
   - [Modal windows without state management](#modal-windows-without-state-management)
   - [Navigation: JsRoutes instead of ts_routes](#navigation-jsroutes-instead-of-ts_routes)

---

## Current stack and problems

### What we have now

| Layer | Technology |
|------|-----------|
| Backend | Rails 8.1, Vite Rails 3.0 |
| Frontend framework | React 19 |
| Routing | TanStack Router (client-side) |
| State | Redux Toolkit + Zustand |
| UI | MUI 6 + Emotion |
| Forms | React Hook Form + Zod |
| Styling | Tailwind CSS v4 + SCSS |
| API layer | Axios + `ts_routes` + `active_model_serializers` |
| Templates (legacy) | HAML (via `gon` for passing data) |

### Key pain points

1. **Dual routing** — routes are defined both in Rails (`routes.rb`) and on the client (TanStack Router). Synchronization via `ts_routes`, but it is unreliable.
2. **API + Serializers** — each view needs an endpoint + a serializer. A lot of boilerplate.
3. **State management overhead** — Redux + Zustand + react-hook-form — three layers of state management.
4. **MUI bundle size** — @mui/material + @emotion/react + @emotion/styled ≈ 300KB+ gzipped. Heavy.
5. **HAML + React hybrid** — part of the application is on HAML (via gon), part is an SPA. There is no unified approach.

---

## Inertia.js for Rails

### What it is

Inertia.js is a bridge between a server framework (Rails) and a client one (React/Vue/Svelte). Not an SPA, not an MPA — a hybrid: **server-side routing + client-side components**.

### Architectural model

```
Request → Rails Router → Controller → render inertia: 'Page', props: {...}
                                          ↓
                                    The React component receives props
                                    (no API, no Redux, no client routing)
```

### Key capabilities (v3, March 2026)

| Capability | Description |
|------------|----------|
| **Server-side routing** | A single source of truth — `routes.rb`. No TanStack Router. |
| **Props from the controller** | Data is passed directly into the React component. No serializers or API endpoints needed. |
| **Shared data** | Global data (auth, flash) via `inertia_share` in the controller. |
| **SSR** | Built-in, works automatically through Vite in dev mode without a separate Node process. |
| **View Transitions** | Native CSS View Transitions for smooth transitions between pages. |
| **Forms** | Built-in `useForm` with reactive state (`processing`, `errors`, `progress`, `isDirty`). |
| **useHttp** (v3) | Standalone HTTP hook for API calls without a page visit (search, autocomplete). |
| **Optimistic updates** (v3) | The UI updates instantly, with rollback on error. |
| **Layout Props** (v3) | `useLayoutProps` / `setLayoutProps` for data between page and layout. |
| **Vite plugin** (v3) | `@inertiajs/vite` — automatic page resolution and SSR configuration. |
| **~15KB lighter** | Axios replaced by a built-in XHR client. |

### Installation (Rails + React + TypeScript)

```bash
bundle add inertia_rails

rails generate inertia:install --framework=react --typescript --vite --tailwind --no-interactive
```

### Controller example

```ruby
class EventsController < ApplicationController
  inertia_share do
    { user: current_user, notifications: current_user&.unread_notifications_count } if user_signed_in?
  end

  def show
    event = Event.find(params[:id])
    render inertia: 'Event/Show', props: {
      event: event.as_json(only: [:id, :title, :start_date, :description])
    }
  end
end
```

### React page example

```tsx
import { usePage } from '@inertiajs/react'

interface Props {
  event: { id: number; title: string; start_date: string; description: string }
}

export default function Show({ event }: Props) {
  const { user } = usePage().props

  return (
    <article>
      <h1>{event.title}</h1>
      <p>{event.description}</p>
    </article>
  )
}
```

### Error handling

```ruby
class ApplicationController < ActionController::Base
  rescue_from StandardError, with: :inertia_error_page

  private

  def inertia_error_page(exception)
    raise exception if Rails.env.local?
    status = ActionDispatch::ExceptionWrapper.new(nil, exception).status_code
    render inertia: 'ErrorPage', props: { status: }, status: status
  end
end
```

### What Inertia replaces

| Before | After |
|------|-------|
| TanStack Router (client-side routing) | `routes.rb` (server-side) |
| Redux / Zustand (state) | Props from the controller + `inertia_share` |
| Axios + ts_routes (API) | Not needed — data arrives as props |
| active_model_serializers | `as_json` or simple hashes in the controller |
| gon (HAML → JS) | Not needed — a single unified approach |

### What Inertia does NOT replace

- The UI library (MUI, Mantine, shadcn) — components are still needed
- Tailwind — styling stays
- Zod — client-side validation for forms
- Complex client-side state (for example, realtime via ActionCable) — here you use Zustand or useHttp

---

## Comparison of UI libraries

### Summary table

| Criterion | MUI | Mantine | shadcn/ui | Tailwind (no library) |
|----------|-----|---------|-----------|--------------------------|
| **Approach** | npm package, runtime | npm package, CSS modules | Copy-paste, the code is yours | Utility classes, no components |
| **Components** | 100+ (core) + MUI X (grid, date pickers) | 120+ (core) + Schedule, Charts, RichText, Notifications | ~50 (basic) | 0 (classes only) |
| **Styling** | Emotion (CSS-in-JS) → migrating to Pigment CSS | CSS Modules + CSS Variables (v7+) | Tailwind CSS (required) | Tailwind CSS |
| **Bundle size** | ~300KB+ gzipped | ~60-200KB gzipped | ~0KB runtime (5-10KB/component) | ~0KB (utilities in CSS) |
| **TypeScript** | Full, but verbose generics | Excellent, ergonomic API | Full (the code is yours — you edit the types yourself) | N/A |
| **Forms** | None (react-hook-form) | `@mantine/form` (built-in) | None (react-hook-form) | N/A |
| **DataGrid** | MUI X DataGrid (best, but $$) | None built-in (TanStack Table) | None built-in (TanStack Table) | N/A |
| **Date Picker** | MUI X DatePicker (powerful) | `@mantine/dates` (built-in) | None (a separate library is needed) | N/A |
| **Rich Text** | None | `@mantine/tiptap` (built-in) | None | N/A |
| **Notifications** | None (notistack) | `@mantine/notifications` (built-in) | None (sonner) | N/A |
| **Hooks** | None | 100+ hooks (`@mantine/hooks`) | None | N/A |
| **Schedule/Calendar** | None | `@mantine/schedule` (v9, March 2026) | None | N/A |
| **Customization** | Theme + sx prop + styled() | Theme + CSS Variables + classNames | Full (the code is yours) | Full (utilities) |
| **Accessibility** | WAI-ARIA | WAI-ARIA | Radix UI (excellent a11y) | Manual |
| **License** | MIT (core), commercial (X Pro/Premium) | MIT | MIT | MIT |
| **GitHub Stars** | ~93K | ~28K | ~80K | ~86K |
| **Community** | Largest, enterprise | Fast-growing, active | Very active | Huge |
| **SSR** | Supported (but heavy CSS-in-JS) | Excellent (CSS modules, no runtime) | Excellent (Tailwind is CSS, no runtime) | Excellent |
| **AI-friendliness** | Medium (many abstractions) | High (LLM docs, simple API) | High (code is visible, few abstractions) | High (utilities are simple) |

### MUI X pricing

| Plan | Price | Included |
|-------|------|---------|
| Community | Free | DataGrid (basic), DatePicker (basic) |
| Pro | $180/dev/year | DataGrid Pro, Date Range Picker, Tree View |
| Premium | $600/dev/year | DataGrid Premium (group, pivot, excel export) |

Mantine, shadcn, Tailwind are completely free (MIT).

---

## Detailed analysis of each library

### MUI (Material UI)

**Strengths:**
- The most mature React component ecosystem (since 2014)
- MUI X DataGrid — objectively the best React data grid on the market
- Huge community, thousands of answers on StackOverflow
- Material Design — recognizable, consistent design
- Enterprise-ready: used by Spotify, Netflix, NASA

**Weaknesses:**
- **Heavy bundle** (~300KB+). Emotion runtime on every render.
- **CSS-in-JS overhead** — worse SSR performance. Pigment CSS (zero-runtime) is still in beta.
- **Verbose API** — `sx` prop, `styled()`, theme overrides — lots of boilerplate for customization.
- **Material Design lock-in** — looks "Google-ish". Customizing it to your own design is a lot of work.
- **Paid advanced components** — DataGrid Pro/Premium $180-600/dev/year.
- **Our current stack** — we are already on MUI and feel its weight.

**Verdict for our project:** We are already on MUI. The bundle size and verbose API issues are the reason to consider alternatives.

---

### Mantine

**Strengths:**
- **Everything included** — 120+ components, forms, date pickers, notifications, rich text, charts, schedule (v9). No need to assemble from 10 libraries.
- **Excellent DX** — TypeScript-first, props instead of classes, ergonomic API.
- **CSS Modules** (since v7) — no CSS-in-JS runtime. Excellent SSR compatibility.
- **100+ hooks** — `useForm`, `useDisclosure`, `useClipboard`, `useHotkeys`, `useIntersection`, etc.
- **`@mantine/schedule`** (v9, March 2026) — a full-featured calendar with drag-and-drop.
- **LLM-friendly docs** — dedicated documentation for AI tools (Cursor, Copilot).
- **Active development** — v9 was released on March 31, 2026, the community is growing.

**Weaknesses:**
- **Smaller community** than MUI (~28K vs ~93K stars). Fewer ready-made solutions on SO.
- **Larger bundle than shadcn** (~60-200KB vs ~5-10KB/component).
- **Its own design language** — not Material, not your own. You need to customize the theme to your brand.
- **No DataGrid at the MUI X level** — for complex tables you still need TanStack Table.
- **Breaking changes between major versions** — migrating 7→8→9 takes effort.

**Verdict for our project:** A strong candidate. Covers most needs out of the box. Especially good for admin panels and dashboards with forms. The hooks will cut down boilerplate.

---

### shadcn/ui

**Strengths:**
- **The code is yours.** Not an npm dependency. Copy-paste components that you fully control.
- **Tailwind-native** — fits perfectly into our Tailwind v4 stack.
- **Radix UI under the hood** — excellent accessibility out of the box.
- **Minimal bundle** — only what you use (~5-10KB/component).
- **Highly customizable** — you edit the component code directly, no theme overrides.
- **Huge ecosystem** — thousands of community components on shadcn.io.
- **AI-friendly** — the code is simple, and LLMs generate shadcn components very well.

**Weaknesses:**
- **~50 base components** — no DatePicker, DataGrid, RichText, Notifications, Charts. You need to assemble these from third-party libraries.
- **Tailwind required** — there is no alternative.
- **Manual updates** — no `npm update`. You have to track and merge changes yourself.
- **No built-in forms** — react-hook-form + zod (which we already have).
- **No hooks** — utility hooks must be written yourself or pulled in separately.
- **Requires Tailwind expertise** — an entry barrier for new developers.

**Verdict for our project:** Good for custom design. But for our project with admin panels, forms, and tables, you would have to assemble a lot from various libraries, which Mantine provides out of the box.

---

### Tailwind CSS (without a component library)

**What it is:** A utility-first CSS framework. Not a component library — only CSS classes.

**Tailwind v4 (current):**
- Rust-based Oxide engine — full builds 3.78x faster, HMR 96% faster
- CSS-first configuration via `@theme` (no JavaScript config)
- Native container queries, 3D transforms, subgrid
- P3 color palette, CSS Variables

**Strengths:**
- Maximum freedom — you write whatever you want.
- Minimal bundle — only the classes you use.
- We already use it — a familiar tool.

**Weaknesses:**
- **No components** — everything from scratch: buttons, modals, selects, tables.
- **No logic** — accessibility, keyboard navigation, focus management — all by hand.
- **Velocity** — much slower development compared to a ready-made library.

**Verdict:** Tailwind is a styling tool, not an alternative to MUI/Mantine/shadcn. We use it and will continue to — the question is what to build on top of it.

---

## Context: the Hexlet experience (post by Kirill Mokevnin)

Kirill Mokevnin (former CTO) described the result of a year-long Hexlet refactoring:

### What was done
1. **Migrated from server-side templates to Inertia.js + React** — not via `API + frontend state + client-side routing`, but via Inertia (server-side routing, no API, no client-side state).
2. **Replaced Bootstrap with Mantine** — "what truly increases efficiency are ready-made React component libraries, where we get not only the look but also ready functionality out of the box."
3. **TypeScript + typed i18next** — maximum typing.
4. **DTO instead of code in templates** — server-side logic now lives in DTOs, easier to refactor.

### Key quotes
> "Life has shown that we made the right choice — Inertia not only became more popular, but the team also released a third version"

> "Take the grid, for example — building it with all the features like filters, sorting, and inline editing is quite a challenge"

> "I never stop praising Mantine, which turned out to be head and shoulders above all other ready-made component libraries"

> "This separation brought order to the backend, because instead of code in templates, everything is now collected in DTOs"

### Upgrade to Inertia v3 + Mantine v9
- View Transitions — smooth transitions between pages.
- Mantine v9 (March 31, 2026) — `@mantine/schedule` (calendar with drag-and-drop), collapse horizontal, React 19.2+ requirement.

### Relevance for us
Hexlet is a Rails application, similar in scale. Their path `HAML → Inertia.js + Mantine` is exactly what we are considering. A year of operation confirmed the choice.

---

## Recommendations

### Recommended stack: Inertia.js + Mantine

**Why Inertia.js:**
1. Eliminates the main pain points — dual routing, API layer, synchronization via ts_routes.
2. Rails 8.1 + Vite Rails 3.0 — perfect compatibility.
3. Proven in production (Hexlet, the Laravel ecosystem).
4. v3 is mature — SSR, optimistic updates, useHttp, View Transitions.
5. Removes Redux/Zustand for most cases — props from the controller.

**Why Mantine (rather than shadcn or staying on MUI):**
1. **vs MUI** — lighter (~60-200KB vs ~300KB+), no CSS-in-JS runtime, better SSR, free DataPicker/Notifications. MUI X DataGrid is the only advantage, but it costs money.
2. **vs shadcn** — more ready-made components (120+ vs ~50), built-in forms, date pickers, RichText, notifications, hooks. For our project (admin panels, forms, tables) — faster development.
3. **vs Tailwind alone** — Tailwind remains for utility styles, but Mantine provides components with logic (a11y, keyboard nav, focus).
4. Confirmed by the Hexlet experience — a year in production.
5. Excellent TypeScript support, LLM-friendly docs.

### What we add (Ruby)

| Gem | Purpose |
|-----|-----------|
| `inertia_rails` | Rails ↔ React bridge |
| `alba` | Serializer (AMS replacement), faster, simpler DSL |
| `typelizer` | Auto-generation of TypeScript interfaces from Alba serializers |
| `js-routes` | Generation of JS helpers for Rails named routes |

### What we remove

| Package | Reason |
|-------|---------|
| `@tanstack/react-router` | Replaced by Inertia (server-side routing) |
| `@reduxjs/toolkit` + `react-redux` | Props from the controller, `inertia_share` |
| `zustand` | For most cases — props from the controller |
| `@mui/material` + `@mui/icons-material` + `@mui/lab` | Replaced by Mantine |
| `@emotion/react` + `@emotion/styled` | MUI dependency, no longer needed |
| `axios` | Inertia v3 built-in HTTP client + `useHttp` |
| `gon` | No longer needed — Inertia passes data as props |
| `active_model_serializers` | Replaced by Alba + Typelizer |
| `ts_routes` | Replaced by JsRoutes (or not needed at all) |
| `notistack` | `@mantine/notifications` |
| `react-hook-form` + `@hookform/resolvers` | `@mantine/form` (or keep — a matter of preference) |

### What we keep

| Package | Reason |
|-------|---------|
| `tailwindcss` v4 | Utility styles. Mantine + Tailwind combine perfectly. |
| `zod` | Schema validation — useful with `@mantine/form` too |
| `@tanstack/react-table` | If an advanced grid is needed (Mantine has no DataGrid) |
| `@dnd-kit/*` | Drag-and-drop will still be needed |
| `@xterm/*`, `@uiw/codemirror-*` | Specialized components |
| `recharts` | Charts (or migration to `@mantine/charts`) |

### Migration plan (high-level)

1. **Phase 0: Preparation** — add `inertia_rails` to the Gemfile, configure the Vite plugin, create a base layout.
2. **Phase 1: New pages on Inertia + Mantine** — all new features are written via Inertia. Old pages keep working.
3. **Phase 2: Migrating existing pages** — port page by page from MUI to Mantine, from React Router to Inertia.
4. **Phase 3: Removing legacy** — remove MUI, Redux, Router, gon, HAML templates.

### Risks

| Risk | Mitigation |
|------|-----------|
| Large migration scope | Incremental approach — Inertia and the current SPA can coexist |
| Mantine learning curve | Excellent documentation + LLM-friendly |
| Loss of MUI X DataGrid | TanStack Table + Mantine Table component. Or keep MUI X only for the grid. |
| Inertia lock-in | Inertia is a thin layer. If a rollback is needed — controllers simply return JSON instead of Inertia responses. |
| Mantine breaking changes | Pin to v9, watch the changelog |

---

## Advanced Inertia.js + Rails patterns

> Based on the article [Evil Martians: Simplicity, vanished?!](https://evilmartians.com/chronicles/simplicity-vanished-solving-the-mystery-with-inertia-js-and-rails)

### WebSockets and Live Updates via ActionCable

Key question: how does realtime work if Inertia is not a classic SPA with client-side state?

**Answer:** ActionCable stays as is. The difference is in how the UI is updated.

#### Three update strategies

**1. Full reload (simplest)** — on receiving a signal over WebSocket, `router.reload()` is called. Inertia re-requests all props from the controller. Simple, but reloads all data.

```js
import { router } from "@inertiajs/react"
import { consumer } from "utils/cable"

const chatChannel = consumer.subscriptions.create(
  { channel: "ChatChannel", room_id: roomId },
  {
    received(data) {
      router.reload()
    }
  }
)
```

**2. Partial reload (more efficient)** — reload only the needed props. The controller is the single source of truth, but we request only `messages`.

```js
received(data) {
  router.reload({ only: ["messages"] })
}
```

**3. Direct prop update (most efficient)** — update props directly via `router.replace`, without hitting the server. Data arrives straight through the WebSocket.

```js
received(data) {
  router.replace({
    props: (current) => ({
      ...current,
      messages: [...current.messages, data.message]
    })
  })
}
```

#### Server side — standard ActionCable

```ruby
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room_id]}"
  end
end

class Message < ApplicationRecord
  after_create_commit :broadcast_new_message

  private

  def broadcast_new_message
    ActionCable.server.broadcast("chat_#{chat_room_id}", {
      type: "message_created",
      message: self.as_json
    })
  end
end
```

#### InertiaCable — a specialized library

[InertiaCable](https://github.com/cole-robertson/inertia-cable) automates the "WebSocket signal → partial reload" pattern:

```ruby
class Message < ApplicationRecord
  broadcasts_to :chat  # automatic broadcast on create/update/destroy
end
```

On the client, the `useInertiaCable` hook subscribes to the channel and automatically calls `router.reload({ only: [...] })`.

#### Context of our project

We already have `@rails/actioncable` in our dependencies and terminal sessions over WebSocket (the `TerminalSession` model). **All current ActionCable channels will keep working** — Inertia does not break the WebSocket infrastructure. Instead of updating the Redux store on receiving a message, we simply call `router.reload({ only: [...] })` or `router.replace(...)`.

---

### Partial Reloads and Deferred Props

Inertia allows fine-grained control over which data is loaded and when.

#### Optional Props — data on demand

Expensive computations are not performed on the first load. Only when the client explicitly requests them:

```ruby
class PostsController < ApplicationController
  def show
    render inertia: 'Post/Show', props: {
      post: serialize_post(@post),
      comments: InertiaRails.optional {
        serialize_comments(@post.comments.includes(:user))
      }
    }
  end
end
```

```tsx
import { Link } from "@inertiajs/react"

export default function PostShow({ post, comments }: Props) {
  return (
    <div>
      <h1>{post.title}</h1>
      {comments === undefined ? (
        <Link only={["comments"]}>Load comments</Link>
      ) : (
        <CommentsList comments={comments} />
      )}
    </div>
  )
}
```

#### Deferred Props (v2+) — automatic loading after render

```ruby
class DashboardController < ApplicationController
  def index
    render inertia: 'Dashboard', props: {
      user: current_user.as_json,
      stats: InertiaRails.defer { compute_expensive_stats },
      recent_activity: InertiaRails.defer { load_activity_feed }
    }
  end
end
```

The page renders instantly with `user`, while `stats` and `recent_activity` are loaded automatically in the background.

#### Partial Reloads via Link

```tsx
<Link href="/users?active=true" only={['users']}>
  Show active
</Link>
```

Inertia will request only the `users` prop from the controller, without reloading the rest of the data.

---

### Typelizer: automatic TypeScript types from Rails

The main problem with Rails + React: **there is no type safety at the backend-frontend boundary**. Change a field in the model — the frontend breaks without warning. Typelizer solves this.

#### How it works

```
Rails Model → Serializer (Alba) → Typelizer → TypeScript Interface → React Component
     ↓              ↓                  ↓              ↓
  DB schema    attributes/types    auto-generate    compile-time check
```

#### Installation

```ruby
# Gemfile
gem "typelizer"
gem "alba"        # recommended serializer
gem "listen"      # for auto-regeneration in dev
```

#### Basic example

```ruby
class ApplicationResource
  include Alba::Resource
  include Typelizer::DSL
end

class PostResource < ApplicationResource
  attributes :id, :title, :body, :published_at
  has_one :author, serializer: AuthorResource
end

class AuthorResource < ApplicationResource
  typelize_from User  # infers types from the User model
  attributes :id, :name

  typelize :string, nullable: true, comment: "Author's avatar URL"
  attribute :avatar do
    "https://example.com/avatar.png" if active?
  end
end
```

Generation:

```bash
rails typelizer:generate
```

Result:

```typescript
// app/javascript/types/serializers/Post.ts
export interface Post {
  id: number;
  title: string;
  body: string;
  published_at: string | null;
  author: Author;
}

// app/javascript/types/serializers/Author.ts
export interface Author {
  id: number;
  name: string;
  avatar?: string | null;
}
```

#### Configuration

```ruby
Typelizer.configure do |config|
  config.output_dir = Rails.root.join("app/javascript/types/serializers")
  config.types_import_path = "@/types"
  config.null_strategy = :nullable  # :nullable | :optional | :nullable_and_optional
  config.inheritance_strategy = :none  # :none | :inheritance
  config.associations_strategy = :database  # :database | :active_record
  config.verbatim_module_syntax = false
  config.comments = true  # adds JSDoc comments
end
```

#### Advanced capabilities

**Manual typing for computed attributes:**

```ruby
typelize author_name: :string, published_at: :string

typelize attribute_name: ["string", "Date",
  optional: true,
  nullable: true,
  multi: true,
  enum: %w[foo bar],
  comment: "Description",
  deprecated: "Use `another_attribute` instead"
]
```

**Multiple writers** — generating both camelCase and snake_case variants in parallel.

**Per-serializer output_dir** (v0.11.0) — different serializers into different folders.

#### Usage in Inertia components

```tsx
import type { Post } from "@/types/serializers/Post"

interface Props {
  post: Post;  // full typing from the Rails model
}

export default function Show({ post }: Props) {
  // TypeScript will catch the error if you access post.titl (a typo)
  return <h1>{post.title}</h1>
}
```

#### Auto-refresh in dev

With the `listen` gem, types are regenerated automatically when serializers change. Change `PostResource` — the TypeScript interface updates without a restart.

#### Comparison with the current approach

| | Now (our project) | With Typelizer |
|--|---------------------|-------------|
| Frontend types | Manual interfaces | Auto-generated from serializers |
| Synchronization | None — types drift apart | Automatic with watch |
| Serialization | `active_model_serializers` | Alba (faster, simpler DSL) |
| Contract | Implicit (JSON) | Explicit (TypeScript interface) |
| Refactoring | Dangerous (broke a field — found out at runtime) | Safe (the compiler catches it) |

#### Replacing active_model_serializers with Alba

We currently use `active_model_serializers` (v0.10.13). Alba is more modern, faster, and natively supported by Typelizer.

```ruby
# Before (AMS)
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title, :body
  belongs_to :author
end

# After (Alba + Typelizer)
class PostResource < ApplicationResource
  attributes :id, :title, :body
  has_one :author, serializer: AuthorResource
end
# → a TypeScript interface is generated automatically
```

---

### Modal windows without state management

Inertia Modal — the controller does not know that it is rendered in a modal:

```tsx
import { ModalLink } from '@inertiajs/modal'

<ModalLink href="/posts/new">Create post</ModalLink>
```

```tsx
import { Modal } from '@inertiajs/modal'

export default function New({ post }: Props) {
  return (
    <Modal>
      <h1>New post</h1>
      <PostForm post={post} />
    </Modal>
  )
}
```

One controller works both for a regular page and for a modal. No modal state, no modal library needed.

---

### Navigation: JsRoutes instead of ts_routes

Evil Martians recommend [JsRoutes](https://github.com/railsware/js-routes) for generating Rails route helpers in JS:

```tsx
import { postPath } from "@/routes"

<Link href={postPath(post.id)}>Show post</Link>
```

Instead of hardcoding URLs or our current `ts_routes`.

---

## Links

### Inertia.js
- [Inertia.js docs](https://inertiajs.com/)
- [Inertia Rails](https://inertia-rails.dev/)
- [Inertia Rails — Partial Reloads](https://inertia-rails.dev/guide/partial-reloads)
- [Inertia Rails — Deferred Props](https://inertia-rails.dev/guide/deferred-props)
- [InertiaCable — WebSocket integration](https://github.com/cole-robertson/inertia-cable)
- [Evil Martians: Simplicity, vanished?!](https://evilmartians.com/chronicles/simplicity-vanished-solving-the-mystery-with-inertia-js-and-rails)
- [Evil Martians: Inertia.js in Rails — basic setup](https://evilmartians.com/chronicles/inertiajs-in-rails-a-new-era-of-effortless-integration)

### Typing
- [Typelizer — TypeScript from Rails serializers](https://github.com/skryukov/typelizer)
- [Alba — serializer](https://github.com/okuramasafumi/alba)
- [JsRoutes — Rails routes in JS](https://github.com/railsware/js-routes)

### UI libraries
- [Mantine](https://mantine.dev/)
- [Mantine v9 changelog](https://alpha.mantine.dev/changelog/9-0-0/)
- [shadcn/ui](https://ui.shadcn.com/)
- [MUI](https://mui.com/)
- [Tailwind CSS v4](https://tailwindcss.com/blog/tailwindcss-v4)

### Comparisons and reviews
- [Best React Component Libraries 2026 — PkgPulse](https://www.pkgpulse.com/blog/best-react-component-libraries-2026-shadcn-mantine-chakra)
- [ShadCN vs Mantine 2026 — BSWEN](https://docs.bswen.com/blog/2026-03-22-shadcn-vs-mantine-comparison)
- [Mantine vs Chakra vs MUI — AdminLTE](https://adminlte.io/blog/mantine-vs-chakra-ui-vs-mui/)
- [Post by Kirill Mokevnin (Hexlet)](https://www.linkedin.com/posts/mokevnin_%D0%BF%D0%BE%D1%81%D0%BB%D0%B5-%D0%B3%D0%BE%D0%B4%D0%B0-%D1%80%D0%B5%D1%84%D0%B0%D0%BA%D1%82%D0%BE%D1%80%D0%B8%D0%BD%D0%B3%D0%B0-%D0%BC%D1%8B-%D0%BF%D0%B5%D1%80%D0%B5%D0%B5%D1%85%D0%B0%D0%BB%D0%B8-%D0%BD%D0%B0-activity-7444769890437185536-Hyc1/)
