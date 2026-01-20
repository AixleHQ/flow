# Architecture - Web Part

**Generated**: 2026-01-20
**Part**: web
**Type**: Web + Backend

---

## Overview

Web Part is the core backend and frontend of the Palad application, built on **Ruby on Rails 8** with a **React 19** SPA frontend. It is responsible for the REST API, Docker container orchestration, and Temporal integration.

---

## Technology Stack

| Category | Technology | Version | Notes |
|----------|------------|---------|-------|
| **Framework** | Ruby on Rails | 8.0.2 | Full-stack MVC |
| **Language** | Ruby | 3.x | Modern features |
| **Database** | PostgreSQL | 15.3 | Primary store |
| **Cache** | Redis | 7.2 | Sessions, container state |
| **Frontend** | React | 19.0.0 | SPA |
| **TypeScript** | TypeScript | 5.9.3 | Type safety |
| **Build** | Vite | 7.3.1 | Fast HMR |
| **UI Library** | Material UI | 6.4.7 | Components |
| **Routing** | TanStack Router | 1.114.27 | Type-safe |
| **State** | Redux Toolkit + Zustand | - | Global + local |
| **Forms** | React Hook Form + Zod | - | Validation |
| **Orchestration** | Temporal (Ruby SDK) | - | Workflows |
| **File Upload** | Shrine + AWS S3 | - | Assets |
| **Auth** | OmniAuth + Google | - | SSO |

---

## Architecture Pattern

**Monolith (Rails API + SPA)** with Feature-Sliced Design for the frontend.

```
┌─────────────────────────────────────────────────────────┐
│                     React SPA (FSD)                      │
│  pages → features → entities → shared                    │
└─────────────────────────┬───────────────────────────────┘
                          │ HTTP (REST API)
┌─────────────────────────▼───────────────────────────────┐
│                   Rails API (:4000)                      │
│  Controllers → Services → Models → Database              │
└─────────────────────────┬───────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    ┌──────────┐   ┌──────────┐   ┌──────────────┐
    │PostgreSQL│   │  Redis   │   │   Temporal   │
    └──────────┘   └──────────┘   └──────────────┘
```

---

## Directory Structure

```
web/
├── app/
│   ├── assets/               # Rails assets (SCSS)
│   ├── channels/             # ActionCable
│   ├── controllers/
│   │   ├── api/v1/           # REST API
│   │   │   ├── application_controller.rb
│   │   │   └── terminal_sessions_controller.rb
│   │   └── web/              # Web controllers
│   ├── frontend/             # React SPA (FSD)
│   │   ├── app/              # App shell, providers
│   │   ├── entities/         # Domain entities
│   │   ├── features/         # Feature modules
│   │   │   └── file-tree/    # FileTree, FileViewer
│   │   ├── pages/            # Route pages
│   │   │   ├── home/
│   │   │   └── session/      # Terminal session
│   │   ├── shared/           # Shared code
│   │   │   ├── api/          # RTK Query
│   │   │   ├── lib/          # Utilities
│   │   │   ├── theme/        # MUI theme
│   │   │   └── ui/           # UI components
│   │   └── widgets/
│   ├── models/               # ActiveRecord
│   ├── services/             # Business logic
│   │   ├── container_manager.rb   # Docker orchestration
│   │   ├── temporal_service.rb    # Temporal client
│   │   └── workflow_service.rb
│   ├── temporal/             # Temporal integration
│   │   ├── activities/       # Ruby activities
│   │   └── workflows/        # Ruby workflows
│   └── views/                # HAML views
├── bin/
│   ├── dev                   # Development server
│   └── temporal_worker       # Ruby worker
├── config/                   # Rails configuration
├── db/                       # Database
│   ├── migrate/
│   └── schema.rb
└── test/                     # Minitest
```

---

## API Endpoints

| Method | Endpoint | Controller | Description |
|--------|----------|------------|-------------|
| `GET` | `/up` | HealthController | Health check |
| `POST` | `/api/v1/terminal_sessions` | TerminalSessionsController | Create Docker session |
| `GET` | `/api/v1/terminal_sessions/:id` | TerminalSessionsController | Get session status |
| `DELETE` | `/api/v1/terminal_sessions/:id` | TerminalSessionsController | Stop session |
| `GET` | `/*path` | HomeController | SPA fallback |
| `WS` | `/cable` | ActionCable | WebSocket |

---

## Key Services

### ContainerManager

Manages Docker containers for interactive Claude Code sessions.

```ruby
ContainerManager.create_session(
  session_id: "uuid",
  step_name: "dev",
  repo_url: "https://github.com/...",
  repo_branch: "main"
)

ContainerManager.get_session_urls(session_id:, step_name:)
# => { ttyd: { port: 32768, ws_url: "ws://..." }, watcher: { ... } }

ContainerManager.stop_session(session_id:, step_name:)
```

### TemporalService

Temporal client for workflow execution.

```ruby
TemporalService.start_workflow(workflow, input)
TemporalService.execute_workflow(workflow, input)
TemporalService.sync_schedules
```

---

## Frontend Architecture (FSD)

Feature-Sliced Design layers:

| Layer | Purpose | Example |
|-------|---------|---------|
| **app** | App shell, providers, routing | `App.tsx`, `ThemeProvider` |
| **pages** | Route-based pages | `SessionPage`, `HomePage` |
| **widgets** | Composite UI blocks | - |
| **features** | User interactions | `FileTree`, `FileViewer` |
| **entities** | Domain models | - |
| **shared** | Reusable code | `api/`, `lib/`, `theme/`, `ui/` |

---

## Key Frontend Components

### SessionPage

Interactive terminal session with:
- **FileTree** — react-accessible-treeview + react-file-icon
- **FileViewer** — CodeMirror (code), react-pdf (PDF), images
- **Terminal** — ttyd iframe
- **Resizable panels** — react-resizable-panels

### State Management

| Type | Technology | Usage |
|------|------------|-------|
| Server State | RTK Query | API calls |
| Local State | Zustand | Component state |
| Form State | React Hook Form | Forms |
| URL State | TanStack Router | Routing |

---

## Temporal Integration

### Task Queue

- **Name**: `palad_ruby`
- **Activities**: DB operations, file loading, saving results

### Activities (Ruby)

Located in `app/temporal/activities/`:
- `Activities::Base` — base class with error handling

---

## Development

```bash
# Enter container
docker-compose run --rm web bash

# Install dependencies
make deps

# Database
make db-prepare
make db-reset

# Linting
make rubocop-fix
make eslint-fix
make typescript
make fsd

# Testing
make rails-test
make fe-test

# All checks
make check
```

---

## Entry Points

| Entry Point | Command | Description |
|-------------|---------|-------------|
| Development | `bin/dev` | Rails + Vite |
| Worker | `bin/temporal_worker` | Ruby Temporal worker |
| Production | `puma -C config/puma.rb` | Puma server |
