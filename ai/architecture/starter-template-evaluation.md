# Starter Template Evaluation

## Primary Technology Domain

**Full-stack web application (brownfield)** — the project is already initialized and uses an established technology stack.

## Starter Options Considered

Since this is a brownfield project with an already established architecture, evaluating a starter template is not required. The project uses a custom setup without a standard starter template.

## Current Architecture Foundation

**The project uses:**
- Rails 8.0.2 (initialized via `rails new`)
- React 19 + Vite (configured manually)
- Feature-Sliced Design structure for the frontend
- Multi-part monorepo organization (`web/`, `ai-engine/`, `docker/`)

**Architectural decisions already established:**

**Language & Runtime:**
- Ruby 3.x for the backend
- Node.js for frontend build tooling
- Python 3.13 for AI workers
- TypeScript 5.9.3 for type safety

**Styling Solution:**
- Material UI 6.4.7 as the UI library foundation
- Custom dark theme with a grayscale palette
- SCSS for Rails assets

**Build Tooling:**
- Vite 7.3.1 for frontend HMR and build
- Rails asset pipeline for backend assets

**Testing Framework:**
- Minitest for the Rails backend (controllers only)
- Mandatory use of factories for tests
- Factories
- **Note:** Tests run in Docker. We write tests only for controllers, not for models.

**Code Organization:**
- Feature-Sliced Design for the frontend (`app/frontend/`)
- Rails MVC for the backend (`app/controllers/`, `app/models/`, `app/services/`)
- Multi-part monorepo (`web/`, `ai-engine/`, `docker/`)

**Development Experience:**
- `bin/dev` to run Rails + Vite
- Hot reloading via Vite
- Docker Compose for infrastructure
- Temporal UI for workflow debugging

**Note:** Since this is a brownfield project with an already established architecture, there is no need for a starter template. The current structure serves as the foundation for further architectural decisions.
