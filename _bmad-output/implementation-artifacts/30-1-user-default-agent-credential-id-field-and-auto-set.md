# Story 30.1: User `default_agent_credential_id` Field & Auto-Set

Status: done

## Story

As a user,
I want my most recently added agent credential to automatically become my default,
so that I don't have to manually configure a default after onboarding.

## Acceptance Criteria

1. **Migration adds field** — Given the database, when migration runs, then `users` table has `default_agent_credential_id` column (nullable reference to `agent_credentials`)

2. **Auto-set on first credential** — Given a User with no agent credentials, when the user creates their first `AgentCredential`, then `user.default_agent_credential_id` is set to the new credential's ID

3. **Auto-set on subsequent credential** — Given a User with an existing default credential, when the user creates another `AgentCredential`, then `user.default_agent_credential_id` is updated to the new credential's ID

4. **Reassign on deletion** — Given a User whose default credential is deleted, when the credential is destroyed, then `user.default_agent_credential_id` falls back to the most recent remaining credential (or nil if none left)

5. **Association accessor** — Given `User#default_agent_credential`, when called, then returns the associated `AgentCredential` record (or nil)

6. **Convenience runtime method** — `User#default_agent_runtime` returns `default_agent_credential&.agent_type` (or nil)

7. **Serialization** — `CurrentUserSerializer` includes `default_agent_credential_id` and `default_agent_runtime` in the response

8. **Profile update** — `CurrentUserController#update` permits `default_agent_credential_id`, validates it belongs to the user

## Tasks / Subtasks

- [x] Task 1: Create migration (AC: #1)
  - [x] `add_reference :users, :default_agent_credential, foreign_key: { to_table: :agent_credentials }, null: true`
  - [x] Run migration, verify schema.rb
- [x] Task 2: Add User model association and methods (AC: #5, #6)
  - [x] `belongs_to :default_agent_credential, class_name: "AgentCredential", optional: true`
  - [x] `def default_agent_runtime` → `default_agent_credential&.agent_type`
  - [x] Add validation: `validate :default_agent_credential_belongs_to_user` (if credential_id present, must be in user.agent_credentials)
- [x] Task 3: Add AgentCredential callbacks (AC: #2, #3, #4)
  - [x] `after_create :set_as_user_default` — sets `user.update!(default_agent_credential: self)`
  - [x] `before_destroy :reassign_user_default` — changed to before_destroy to avoid FK violation
- [x] Task 4: Update SessionConfigResolver (AC: relates to integration)
  - [x] Added `user&.default_agent_runtime` in priority chain between `workflow_run.agent_runtime` and latest credential fallback
  - [x] Added `"user_default"` source to `resolve_agent_runtime_source`
- [x] Task 5: Update serializer and controller (AC: #7, #8)
  - [x] Added `default_agent_credential_id` and `default_agent_runtime` to `CurrentUserSerializer`
  - [x] Added `default_agent_credential_id` to `update_current_user_params` in `CurrentUserController`
- [x] Task 6: Write tests (AC: #1-#8)
  - [x] Test auto-set on credential creation (first + subsequent)
  - [x] Test reassignment on credential deletion (fallback + nil)
  - [x] Test `default_agent_runtime` convenience method
  - [x] Test validation — cannot set credential that doesn't belong to user
  - [x] Test SessionConfigResolver uses `user.default_agent_runtime` in priority chain

## Dev Notes

### Architecture Patterns

- **Callbacks on AgentCredential** — `after_create` and `after_destroy` are standard Rails patterns. Keep them simple: single `update!` on user
- **Validation on User** — custom validation ensures data integrity. User cannot point to someone else's credential
- **SessionConfigResolver integration** — the resolver already has a priority chain in `resolve_agent_runtime`. The change inserts `user.default_agent_runtime` between `workflow_run.agent_runtime` and `user.agent_credentials.order(...)` fallback. The `resolve_agent_runtime_source` method needs a new `"user_default"` source
- **Enumerize** — project uses `enumerize` gem, NOT ActiveRecord enums. `agent_type` on AgentCredential is validated via `inclusion` validator, not enum

### Existing Code Context

- **User model** (`app/models/user.rb`) — has `has_many :agent_credentials, dependent: :destroy`. No default credential association yet
- **AgentCredential model** (`app/models/agent_credential.rb`) — `belongs_to :user`, validates `agent_type` inclusion in `%w[claude_code cursor_cli codex gemini_cli]`, uniqueness scoped to user
- **CurrentUserSerializer** (`app/serializers/current_user_serializer.rb`) — includes `agent_credentials` and `configured_agents`. No `default_agent_credential_id` yet
- **CurrentUserController** (`app/controllers/api/v1/current_user_controller.rb`) — `update` permits `:password, :password_confirmation, :name, :position, :preferred_agent_language, :onboarding_state_event, selected_agents: []`
- **SessionConfigResolver** (`app/services/session_config_resolver.rb`) — `resolve_agent_runtime` falls back to `user&.agent_credentials&.order(created_at: :desc)&.first&.agent_type || "claude_code"`. `resolve_agent_runtime_source` has `"latest_credential"` but no `"user_default"`

### File Locations

- New: `db/migrate/TIMESTAMP_add_default_agent_credential_to_users.rb`
- Modified: `app/models/user.rb` — association + validation + convenience method
- Modified: `app/models/agent_credential.rb` — callbacks
- Modified: `app/serializers/current_user_serializer.rb` — new attributes
- Modified: `app/controllers/api/v1/current_user_controller.rb` — permit param
- Modified: `app/services/session_config_resolver.rb` — use `default_agent_runtime` in priority chain
- New/Modified: `test/models/agent_credential_test.rb` — callback tests
- New/Modified: `test/models/user_test.rb` — validation + method tests
- Modified: `test/services/session_config_resolver_test.rb` — updated priority chain tests

### Testing Standards

- **Framework:** Minitest with FactoryBot, Mocha for mocks
- **Run:** `docker exec app-web-1 bundle exec rails test test/models/user_test.rb test/models/agent_credential_test.rb test/services/session_config_resolver_test.rb`
- Factory: `create(:agent_credential, user: @user, agent_type: "claude_code")`

### References

- [Source: ai/session-config-cascade.md#6.1] — User default agent credential design
- [Source: ai/epics/epic-30-default-agent-credential.md#Story 30.1] — AC and technical notes
- [Source: app/models/user.rb] — Current User model
- [Source: app/models/agent_credential.rb] — Current AgentCredential model
- [Source: app/services/session_config_resolver.rb] — Priority chain for agent_runtime
- [Source: app/serializers/current_user_serializer.rb] — Current serializer
- [Source: app/controllers/api/v1/current_user_controller.rb] — Current controller

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Used `before_destroy` instead of `after_destroy` for `reassign_user_default` to avoid FK violation
- Fixed fallback in `resolve_agent_runtime` from "cursor_cli" to "claude_code" (was inconsistent)
- 52 tests, 87 assertions, 0 failures

### File List

- db/migrate/20260301152632_add_default_agent_credential_to_users.rb (new)
- app/models/user.rb (modified)
- app/models/agent_credential.rb (modified)
- app/services/session_config_resolver.rb (modified)
- app/serializers/current_user_serializer.rb (modified)
- app/controllers/api/v1/current_user_controller.rb (modified)
- test/models/agent_credential_test.rb (new)
- test/models/user_default_credential_test.rb (new)
