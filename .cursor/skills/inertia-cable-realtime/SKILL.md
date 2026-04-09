---
name: inertia-cable-realtime
description: Real-time page updates via Inertia Cable with broadcast_refresh_to and Alba resources. Use when adding live updates to Inertia pages, setting up ActionCable broadcasts, creating new show pages with real-time data, or working with broadcast_refresh_to, useInertiaCableStream, or cable_stream props.
---

# Inertia Cable Real-Time Updates

## Architecture

Real-time updates use **Inertia Cable** (`inertia_cable` gem), not custom ActionCable channels. When a model changes, it broadcasts a refresh signal via Inertia Cable. The frontend hook receives this and calls `router.reload()` to fetch fresh props from the controller.

```
Model update → broadcast_refresh_to(self) → ActionCable → useInertiaCableStream → router.reload({ only: [...] }) → Controller re-renders props via Alba resources
```

## Rules

- **DO** use `broadcast_refresh_to(self)` on model `after_commit`
- **DO** use Alba resources for all serialization (never build hashes in controllers)
- **DO** use `useInertiaCableStream` hook on the frontend
- **DO** use `touch` to propagate changes through parent models
- **DO NOT** create custom ActionCable channels for Inertia pages
- **DO NOT** use polling (`setInterval` + `router.reload`)
- **DO NOT** build prop hashes manually in controllers

## Backend: Model

Prefer the `broadcasts_to` DSL from `inertia_cable` — it registers `after_commit` callbacks automatically:

```ruby
class WorkflowRun < ApplicationRecord
  broadcasts_to ->(run) { run }, on: :update
end
```

Equivalent manual approach (use when you need custom logic):

```ruby
class WorkflowRun < ApplicationRecord
  after_commit :broadcast_updates, on: :update

  private

  def broadcast_updates
    broadcast_refresh_to(self)
  end
end
```

### Propagating child changes via touch

When a child model changes and the parent's Inertia page needs to refresh, use `touch`:

```ruby
class StepRun < ApplicationRecord
  belongs_to :workflow_run

  after_commit :touch_workflow_run, on: :update, if: :state_previously_changed?

  def broadcast_update!
    workflow_run.touch  # triggers WorkflowRun's after_commit → broadcast_refresh_to
  end

  private

  def touch_workflow_run
    workflow_run.touch
  end
end
```

For deeper nesting, each level touches its parent:

```ruby
class SubStepRun < ApplicationRecord
  belongs_to :step_run

  after_commit :broadcast_update!, on: [:create, :update], if: :state_previously_changed?

  private

  def broadcast_update!
    step_run.broadcast_update!  # → step_run.workflow_run.touch
  end
end
```

Models that belong to multiple parents (e.g. `TerminalSession` has its own Inertia page AND is nested in `WorkflowRun`) broadcast to both:

```ruby
class TerminalSession < ApplicationRecord
  after_commit :broadcast_updates, on: :update

  private

  def broadcast_updates
    broadcast_refresh_to(self)            # for TerminalSession's own show page
    step_run&.workflow_run&.touch         # for WorkflowRun's show page
  end
end
```

## Backend: Controller

Pass `cable_stream: inertia_cable_stream(record)` in props. Serialize everything through Alba resources:

```ruby
def show
  run = WorkflowRun.where(project: @project)
                   .includes(step_runs: [:step, :terminal_session])
                   .find(params[:id])

  render inertia: "Projects/WorkflowRuns/ShowPage", props: {
    project: project_props,
    run: WorkflowRunResource.new(run).to_h,
    cable_stream: inertia_cable_stream(run)
  }
end
```

## Backend: Alba Resources

All serialization goes through Alba resources inheriting from `ApplicationResource`:

```ruby
class ApplicationResource
  include Alba::Resource
  include Typelizer::DSL
  include Rails.application.routes.url_helpers
end
```

Use `next` (not `return`) inside attribute blocks. Use `params` to pass context to nested resources:

```ruby
class StepRunResource < ApplicationResource
  attributes :id, :state, :started_at

  attribute :terminal_url do |sr|
    ts = sr.terminal_session
    next nil unless ts&.route_token.present? && ts.active?
    # build URL...
  end

  attribute :sub_step_runs do |sr|
    sr.sub_step_runs.map { |ssr| SubStepRunResource.new(ssr).to_h }
  end
end
```

For URL attributes, use path helpers:

```ruby
attribute :download_url do |wra|
  next nil unless wra.file.present?
  download_api_v1_company_project_workflow_run_workflow_run_asset_path(
    project_id: wra.workflow_run.project_id,
    workflow_run_id: wra.workflow_run_id,
    id: wra.id
  )
end
```

## Frontend: Hook

Use `useInertiaCableStream` from `shared/lib/hooks/useInertiaCableStream`. Pass `cable_stream` from props and specify which props to reload:

```tsx
const { run, assets, cableStream } = usePage().props;

const isTerminal = run.state === 'completed' || run.state === 'failed' || run.state === 'cancelled';

useInertiaCableStream(cableStream, {
  only: ['run', 'assets'],
  enabled: !isTerminal,
});
```

- `only` — reload only these props (avoids full page reload)
- **CRITICAL: `only` keys must use the original snake_case names from the Rails controller**, not the camelCase names that arrive in frontend props. Inertia's `PropsResolver` filters partial reload requests using the raw `X-Inertia-Partial-Data` header against the **original prop keys defined in the controller** — before `prop_transformer` converts them to camelCase. If you pass camelCase keys (e.g. `'boardColumns'`), the backend won't match them to `board_columns` and will return nothing. Single-word prop names (e.g. `'run'`, `'assets'`, `'session'`) are unaffected since they're identical in both casings.
- `enabled: !isTerminal` — stop listening when record reaches final state
- Built-in 150ms debounce coalesces rapid broadcasts

## Checklist for adding real-time to a new page

1. Model: add `after_commit :broadcast_updates, on: :update` → `broadcast_refresh_to(self)`
2. Child models: add `touch` calls to propagate to parent
3. Controller: pass `cable_stream: inertia_cable_stream(record)` in props
4. Controller: serialize all data through Alba resources
5. Frontend: call `useInertiaCableStream(cableStream, { only: [...], enabled: !isTerminal })`
6. Frontend: `only` array must use **snake_case** prop names from the controller (e.g. `'board_columns'`, NOT `'boardColumns'`)
7. Frontend: no polling, no custom ActionCable subscriptions
