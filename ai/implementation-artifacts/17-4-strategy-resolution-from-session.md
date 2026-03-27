# Story 17.4: Strategy Resolution from Session

Status: review

## Story

As a platform engineer,
I want `TerminalSession` to build its own container strategy,
so that activities and services don't manually resolve strategy types from input hashes.

## Acceptance Criteria

1. **AC1: TerminalSession#strategy** — New public method that returns the correct strategy instance based on `session_type`:
   - `auth_setup` → `ContainerStrategies::AgentAuthStrategy`
   - `agent_session` → `ContainerStrategies::AgentSessionStrategy`
   - Other types → raise `ArgumentError`

2. **AC2: Strategy params** — Strategy initialized with `user_id`, `agent_type`, `session_id` (self.id), `route_token`. For `agent_session`, also includes `credential` (resolved from `user.agent_credentials.find_by(agent_type: agent_type)`).

3. **AC3: ContainerService.execute(session:)** — New method signature. Internally calls `session.strategy`, runs all 6 lifecycle phases. Returns result hash.

4. **AC4: ContainerService.cleanup(session:)** — New method. Resolves strategy from session, builds context with container reference, runs `before_cleanup` + `cleanup`. Marks session collected.

5. **AC5: Backward compat** — Existing `execute(strategy:, input:)` signature preserved during migration. Both signatures work.

6. **AC6: Tests** — Unit tests for `TerminalSession#strategy` covering auth_setup, agent_session, and invalid session types. Integration tests for `ContainerService.execute(session:)`.

## Tasks / Subtasks

- [x] Task 1: Add `strategy` and `strategy_params` to TerminalSession (AC: #1, #2)
  - [x] 1.1 Implement `strategy` method with session_type dispatch
  - [x] 1.2 Implement `strategy_params` private method
  - [x] 1.3 Handle credential resolution for agent_session
- [x] Task 2: Add `ContainerService.execute(session:)` (AC: #3, #5)
  - [x] 2.1 Add session-based execute path
  - [x] 2.2 Keep existing strategy-based path
- [x] Task 3: Add `ContainerService.cleanup(session:)` (AC: #4)
  - [x] 3.1 Load container from session.container_id
  - [x] 3.2 Run before_cleanup + cleanup via strategy
  - [x] 3.3 Mark session collected on success
- [x] Task 4: Write tests (AC: #6)
  - [x] 4.1 Test TerminalSession#strategy for each session_type
  - [x] 4.2 Test ContainerService with session input
  - [x] 4.3 Test error cases (missing session_type, invalid type)

## Dev Notes

### Design

This eliminates the following from `ContainerActivityBase` (after 17.5):
- `STRATEGY_MAP` hash (~5 lines)
- `build_strategy_from_input` method (~5 lines)
- `build_strategy_from_session` method (~10 lines)
- `prepare_strategy_input` method with case statement (~20 lines)

Total: ~40 lines of strategy routing code replaced by `session.strategy` (~15 lines on the model).

### Key files to modify

- `web/app/models/terminal_session.rb` — add `strategy`, `strategy_params`
- `web/app/services/container_service.rb` — add session-based execute and cleanup

### Strategy initialization comparison

Current (in activity):
```ruby
strategy_class = STRATEGY_MAP.fetch(strategy_type)
prepared = prepare_strategy_input(strategy_type, strategy_input)
strategy_class.new(**prepared)
```

New (on session):
```ruby
session.strategy  # returns fully initialized strategy
```

### Credential resolution

For `agent_session`, the credential is currently passed as `credential_id` through Temporal input, then resolved in `prepare_strategy_input`. Now it's resolved directly: `user.agent_credentials.find_by(agent_type: agent_type)`.

### References

- [Source: web/app/models/terminal_session.rb](web/app/models/terminal_session.rb) — model to extend
- [Source: web/app/temporal/activities/container_activity_base.rb](web/app/temporal/activities/container_activity_base.rb) — code being replaced
- [Source: web/app/services/container_service.rb](web/app/services/container_service.rb) — service to extend
