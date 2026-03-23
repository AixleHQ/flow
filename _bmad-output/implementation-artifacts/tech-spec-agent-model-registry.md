---
title: 'Agent Model Registry'
slug: 'agent-model-registry'
created: '2026-03-23'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: ['rails-8.1', 'postgresql', 'react-18', 'mui-6', 'rtk-query', 'typescript', 'ruby-3.3']
files_to_modify:
  - 'app/services/agents/base_adapter.rb'
  - 'app/services/agents/claude_code_adapter.rb'
  - 'app/services/agents/codex_adapter.rb'
  - 'app/services/agents/gemini_cli_adapter.rb'
  - 'app/services/agents/cursor_cli_adapter.rb'
  - 'app/services/container_strategies/agent_session_strategy.rb'
  - 'app/services/container_strategies/agent_base_strategy.rb'
  - 'app/controllers/api/v1/current_user_controller.rb'
  - 'app/controllers/api/v1/company/projects/workflows/steps_controller.rb'
  - 'app/models/terminal_session.rb'
  - 'app/models/step.rb'
  - 'app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx'
  - 'app/frontend/features/workflow-steps/ui/AddStepDialog.tsx'
  - 'app/frontend/features/workflow-steps/lib/types.ts'
  - 'app/frontend/entities/terminal-session/model/types.ts'
code_patterns:
  - 'Adapter pattern: BaseAdapter → per-runtime adapters (ClaudeCodeAdapter, etc.)'
  - 'Strategy pattern: AgentBaseStrategy → AgentSessionStrategy → WorkflowStepStrategy'
  - 'session_command(mode:, prompt:) → CLI command builder per adapter'
  - 'RTK Query: baseApi.injectEndpoints for API slices'
  - 'MUI Autocomplete for resource selection (tools, skills, MCP servers — same pattern)'
  - 'FSD: entities/terminal-session, features/workflow-steps, widgets/session-launch'
  - 'react-hook-form + zod for step form validation (AddStepDialog)'
test_patterns:
  - 'minitest + mocha for unit/integration tests'
  - 'test/services/agents/*_adapter_test.rb for adapter tests'
  - 'StubSupport with container_filesystem for container strategy tests'
---

# Tech-Spec: Agent Model Registry

**Created:** 2026-03-23

## Overview

### Problem Statement

Users cannot select a specific LLM model when launching a session or configuring a workflow step. The platform always uses the runtime's default model. Users need the ability to choose from available models (e.g., claude-sonnet-4-6 vs claude-opus-4-6, gpt-5.3-codex vs gpt-5.2-codex) to control cost, speed, and capability tradeoffs.

### Solution

Query provider APIs on-the-fly using stored user credentials (`AgentCredential`) to fetch available models per runtime. Each adapter gets a `fetch_available_models` method that calls the provider's models API. Results are cached with TTL via `Rails.cache`. A new API endpoint exposes models to the frontend, which adds a model selector dropdown to the session launch form and workflow step editor. Selected model is passed to the runtime via `adapter.session_command(model:)`.

### Scope

**In Scope:**
- `adapter.fetch_available_models(credentials)` — 4 implementations (Claude, Gemini, Codex, Cursor)
- API endpoint `GET /api/v1/current_user/models?agent_runtime=X`
- Rails.cache-based caching with TTL (~24h) per user per runtime
- DB migration: `terminal_sessions.requested_model` (string, nullable)
- DB migration: `steps.preferred_model` (string, nullable)
- `adapter.session_command(model:)` — pass model flag to CLI
- Frontend: model selector Autocomplete in SessionLaunchWidget (after Agent Runtime toggle)
- Frontend: model selector in AddStepDialog (workflow step editor)
- Admin page: view cached models per runtime

**Out of Scope:**
- Smart model recommendation based on task type
- Per-model cost tracking / pricing display
- Model capability-based filtering in UI (future enhancement)

## Context for Development

### Codebase Patterns

**Backend — Adapter pattern:**
`Agents::BaseAdapter` defines interface, 4 concrete adapters implement per-runtime logic. Key existing methods: `session_command(mode:, prompt:)`, `config_files(credentials, workflow_config)`, `default_env_vars(session)`. New method: `fetch_available_models(credentials)`.

**Backend — Strategy pattern:**
`AgentBaseStrategy#build_env_vars` assembles env vars. `AgentSessionStrategy#launch_agent_in_tmux` calls `adapter.session_command(...)` and sends result to tmux. Model flag goes into this flow.

**Backend — Credential storage:**
`AgentCredential` stores encrypted credentials per user per agent_type. `credential.config_data` returns decrypted hash with API keys/tokens. Available via `user.agent_credentials.find_by(agent_type:)`.

**Frontend — FSD + RTK Query:**
- Entity types in `entities/terminal-session/model/types.ts` — `ITerminalSession`, `ICreateTerminalSessionRequest`
- API slices in `shared/api/terminalSessionApi.ts` — `baseApi.injectEndpoints`
- Widgets use `Autocomplete` from MUI for all resource selectors (tools, skills, MCP, assets, repos)
- Step forms use `react-hook-form` + `zod` in `AddStepDialog.tsx`
- `SessionLaunchWidget` sends `createSessionAction({ terminalSession: { agentType, toolIds, ... } })`

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `app/services/agents/base_adapter.rb` | Adapter interface — add `fetch_available_models` |
| `app/services/agents/claude_code_adapter.rb` | Claude impl — `GET api.anthropic.com/v1/models` |
| `app/services/agents/codex_adapter.rb` | Codex impl — `GET chatgpt.com/backend-api/codex/models` |
| `app/services/agents/gemini_cli_adapter.rb` | Gemini impl — `GET generativelanguage.googleapis.com/v1beta/models` |
| `app/services/agents/cursor_cli_adapter.rb` | Cursor impl — `POST api2.cursor.sh/GetUsableModels` |
| `app/models/agent_credential.rb` | Credential storage — `config_data` decrypts to API keys |
| `app/services/container_strategies/agent_session_strategy.rb:107` | `launch_agent_in_tmux` — calls `adapter.session_command(...)` |
| `app/services/container_strategies/agent_base_strategy.rb:29-30` | `SESSION_COMMANDS` — base CLI commands |
| `app/models/terminal_session.rb` | Add `requested_model` field |
| `app/models/step.rb` | Add `preferred_model` field |
| `app/controllers/api/v1/current_user_controller.rb` | Add `models` action |
| `app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx` | Add model Autocomplete after agent toggle |
| `app/frontend/features/workflow-steps/ui/AddStepDialog.tsx` | Add model select in step form |
| `app/frontend/entities/terminal-session/model/types.ts` | Add `requestedModel` to types |
| `app/frontend/features/workflow-steps/lib/types.ts` | Add `preferredModel` to Step type |
| `config/routes.rb` | Add models route under current_user |

### Technical Decisions

1. **No DB table for models** — `Rails.cache` with TTL. Models are transient, provider-owned data. Cache key: `"agent_models:#{user.id}:#{agent_runtime}"`, TTL: 24 hours.
2. **Normalized response** — All adapters return same shape: `[{ model_id:, display_name:, description: }]` regardless of provider format.
3. **Model validation** — `requested_model` format: `/\A[a-z0-9][a-z0-9._:-]*\z/` (strict, prevents injection in shell commands).
4. **Cursor no-op** — `CursorCliAdapter#fetch_available_models` returns models from API but `session_command` ignores model param (Cursor manages internally).
5. **Provider API auth per adapter:**
   - Claude: `X-Api-Key` header + `anthropic-version: 2023-06-01`
   - Gemini: OAuth Bearer token (access_token from credentials)
   - Codex: Bearer token (access_token from credentials)
   - Cursor: Bearer token (accessToken from credentials)

## Implementation Plan

### Tasks

- [ ] Task 1: DB migration — add requested_model and preferred_model columns
  - File: `db/migrate/XXXXXX_add_model_selection_fields.rb`
  - Action: Add `requested_model` (string, nullable) to `terminal_sessions`, add `preferred_model` (string, nullable) to `steps`
  - Notes: No index needed — not queried by these columns

- [ ] Task 2: Add `fetch_available_models` to BaseAdapter
  - File: `app/services/agents/base_adapter.rb`
  - Action: Add `def fetch_available_models(credentials) = []` default implementation. Define normalized return shape: `[{ model_id: String, display_name: String, description: String }]`

- [ ] Task 3: Implement ClaudeCodeAdapter#fetch_available_models
  - File: `app/services/agents/claude_code_adapter.rb`
  - Action: `GET https://api.anthropic.com/v1/models` with headers `X-Api-Key: credentials["primaryApiKey"]`, `anthropic-version: 2023-06-01`. Parse response `data` array, map each model to `{ model_id: m["id"], display_name: m["display_name"], description: "#{m["max_input_tokens"]} input tokens" }`. Handle pagination if `has_more`. Filter to models with `id` matching `/claude/`.
  - Notes: OAuth accounts use different auth — check if `credentials["oauthAccount"]` present, if so this API may not work (return empty). API key users get full list.

- [ ] Task 4: Implement GeminiCliAdapter#fetch_available_models
  - File: `app/services/agents/gemini_cli_adapter.rb`
  - Action: `GET https://generativelanguage.googleapis.com/v1beta/models` with header `Authorization: Bearer #{credentials["access_token"]}`. Parse `models` array, map to `{ model_id: m["name"].sub("models/", ""), display_name: m["displayName"], description: m["description"] }`. Filter to models where `supportedGenerationMethods` includes `"generateContent"`. Handle pagination via `pageToken`/`nextPageToken`.

- [ ] Task 5: Implement CodexAdapter#fetch_available_models
  - File: `app/services/agents/codex_adapter.rb`
  - Action: `GET https://chatgpt.com/backend-api/codex/models` with header `Authorization: Bearer #{credentials.dig("tokens", "access_token")}`. Parse `models` array, map to `{ model_id: m["slug"], display_name: m["display_name"], description: m["description"] }`. Filter to models with `visibility == "list"`.

- [ ] Task 6: Implement CursorCliAdapter#fetch_available_models
  - File: `app/services/agents/cursor_cli_adapter.rb`
  - Action: `POST https://api2.cursor.sh/aiserver.v1.AiService/GetUsableModels` with header `Authorization: Bearer #{credentials["accessToken"]}`, `Content-Type: application/proto`, `Connect-Protocol-Version: 1`. Response is protobuf — extract model strings using regex on raw binary: scan for consecutive printable ASCII sequences. Group into model entries (model_id, display_name pattern). Return normalized array.
  - Notes: Protobuf parsing without a `.proto` file — use string extraction heuristic (same approach validated in brainstorming session). Alternatively, send empty JSON body with `Content-Type: application/json` — Cursor Connect API may support JSON encoding.

- [ ] Task 7: Add model validation to TerminalSession and Step models
  - File: `app/models/terminal_session.rb`
  - Action: Add `validates :requested_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true`
  - File: `app/models/step.rb`
  - Action: Add `validates :preferred_model, format: { with: /\A[a-z0-9][a-z0-9._:-]*\z/, message: "invalid model ID format" }, allow_nil: true`

- [ ] Task 8: Add `session_command(model:)` parameter to adapters
  - File: `app/services/agents/base_adapter.rb`
  - Action: Update signature to `def session_command(mode:, prompt: nil, model: nil)`. Default: ignore model.
  - File: `app/services/agents/claude_code_adapter.rb`
  - Action: `def session_command(mode:, prompt: nil, model: nil)` — return `model ? "claude --model #{model}" : "claude"`
  - File: `app/services/agents/codex_adapter.rb`
  - Action: Return `model ? "codex --model #{model} --yolo" : "codex --yolo"`
  - File: `app/services/agents/gemini_cli_adapter.rb`
  - Action: Return `model ? "gemini --model #{model} --yolo" : "gemini --yolo"`
  - File: `app/services/agents/cursor_cli_adapter.rb`
  - Action: Ignore model param — return `"agent --force"` always.

- [ ] Task 9: Pass model through strategy → adapter
  - File: `app/services/container_strategies/agent_session_strategy.rb`
  - Action: In `launch_agent_in_tmux`, load session's `requested_model` and pass to `adapter.session_command(mode:, prompt:, model:)`.
  - File: `app/services/container_strategies/workflow_step_strategy.rb`
  - Action: In `build_env_vars` or `launch_agent_in_tmux`, resolve model: use `step.preferred_model` if set, else `session.requested_model`, else nil (runtime default). Pass to `session_command(model:)`.

- [ ] Task 10: API endpoint — models for current user
  - File: `app/controllers/api/v1/current_user_controller.rb`
  - Action: Add `def models` action. Params: `agent_runtime` (required, must be in `User::AVAILABLE_AGENTS`). Find `AgentCredential` for current_user + agent_runtime. Call `AgentCredentialsService.for(agent_runtime).adapter.fetch_available_models(credential.config_data)`. Wrap with `Rails.cache.fetch("agent_models:#{current_user.id}:#{agent_runtime}", expires_in: 24.hours)`. Return JSON array. Handle errors: no credential → 404, API failure → 502 with message.
  - File: `config/routes.rb`
  - Action: Add `get :models, on: :member` under current_user resource, or `get 'current_user/models', to: 'current_user#models'`.

- [ ] Task 11: Permit `requested_model` in terminal sessions controller
  - File: `app/controllers/api/v1/terminal_sessions_controller.rb` (or wherever create is handled)
  - Action: Add `:requested_model` to permitted params in create action.
  - File: `app/controllers/api/v1/company/projects/workflows/steps_controller.rb`
  - Action: Add `:preferred_model` to permitted params for step create/update.

- [ ] Task 12: Frontend — API slice for models
  - File: `app/frontend/shared/api/agentModelsApi.ts` (new file)
  - Action: Create RTK Query endpoint: `getAgentModels: builder.query<AgentModel[], string>({ query: (agentRuntime) => ({ url: '/api/v1/current_user/models', params: { agent_runtime: agentRuntime } }) })`. Define `AgentModel` type: `{ modelId: string; displayName: string; description: string }`.

- [ ] Task 13: Frontend — model selector in SessionLaunchWidget
  - File: `app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx`
  - Action: Add state `const [selectedModel, setSelectedModel] = useState<string | null>(null)`. Add `useGetAgentModelsQuery(selectedAgent!, { skip: !selectedAgent })`. Reset `selectedModel` to null when `selectedAgent` changes. Add `Autocomplete` after Agent Runtime toggle group (before "Optional Configuration" divider): options from query, `getOptionLabel: (o) => o.displayName`, value mapped from `selectedModel`, placeholder "Default (runtime selects)". Pass `requestedModel: selectedModel` in `createSessionAction` payload.

- [ ] Task 14: Frontend — update terminal session types
  - File: `app/frontend/entities/terminal-session/model/types.ts`
  - Action: Add `requestedModel?: string` to `ICreateTerminalSessionRequest.terminalSession`. Add `requestedModel: string | null` to `ITerminalSession`.

- [ ] Task 15: Frontend — model selector in AddStepDialog
  - File: `app/frontend/features/workflow-steps/ui/AddStepDialog.tsx`
  - Action: Add model `Autocomplete` field. Query models based on step's `requiredAgentRuntime` or fall back to user's default runtime. Add `preferredModel` to form data and submit.
  - File: `app/frontend/features/workflow-steps/lib/types.ts`
  - Action: Add `preferredModel: string | null` to `Step`, `CreateStepRequest`, `UpdateStepRequest`.
  - File: `app/frontend/features/workflow-steps/lib/stepSchema.ts`
  - Action: Add `preferredModel` to zod schema (optional string).

- [ ] Task 16: Admin page — view models
  - File: `app/views/admin/agent_models/` (new)
  - Action: Simple admin page that iterates each agent_runtime, fetches models for a selected user (or current admin's credentials), and displays as a read-only table. Uses existing admin layout pattern.

## Acceptance Criteria

- [ ] AC 1: Given a user with Claude API key credential, when `GET /api/v1/current_user/models?agent_runtime=claude_code`, then response returns JSON array of Claude models with `model_id`, `display_name`, `description` fields
- [ ] AC 2: Given a user with Gemini OAuth credential, when `GET /api/v1/current_user/models?agent_runtime=gemini_cli`, then response returns JSON array of Gemini models filtered to those supporting `generateContent`
- [ ] AC 3: Given a user with Codex credential, when `GET /api/v1/current_user/models?agent_runtime=codex`, then response returns JSON array of Codex models filtered to `visibility: "list"`
- [ ] AC 4: Given a user with Cursor credential, when `GET /api/v1/current_user/models?agent_runtime=cursor_cli`, then response returns JSON array of Cursor models with model_id and display_name
- [ ] AC 5: Given a user without credential for a runtime, when `GET /api/v1/current_user/models?agent_runtime=X`, then response returns 404 with error message
- [ ] AC 6: Given models were fetched within 24 hours, when the same request is made, then cached results are returned without calling provider API
- [ ] AC 7: Given a user selects a model in SessionLaunchWidget and starts a session, when the container starts, then the CLI is launched with `--model <selected_model>` flag (verified in tmux command)
- [ ] AC 8: Given a user starts a session without selecting a model (null), when the container starts, then the CLI is launched without `--model` flag (runtime default)
- [ ] AC 9: Given a workflow step has `preferred_model` set, when the workflow step executes, then the CLI uses that model regardless of session-level setting
- [ ] AC 10: Given `requested_model` contains invalid characters (e.g., shell metacharacters), when creating a session, then validation fails with 422 error
- [ ] AC 11: Given a Cursor runtime session with model selected, when the container starts, then the model flag is NOT passed to the CLI (Cursor manages internally)
- [ ] AC 12: Given user selects agent runtime in SessionLaunchWidget, when the runtime changes, then the model dropdown loads models for the new runtime and resets selection to null (default)
- [ ] AC 13: Given the provider API is unreachable, when fetching models, then the endpoint returns 502 with a user-friendly error message and the dropdown shows an error state

## Additional Context

### Dependencies

- `AgentCredential` must exist for user+runtime to fetch models (existing requirement for sessions)
- No new gems required — `Net::HTTP` already used in adapters (see CursorCliAdapter)
- `Rails.cache` backend must be configured (default memory store works for dev, Redis for production)

### Testing Strategy

- **Unit tests (4):** One per adapter's `fetch_available_models` — mock HTTP responses with WebMock, verify normalized output shape and filtering logic
- **Controller test (1):** `GET /api/v1/current_user/models` — test with credential present, missing, invalid runtime, and caching behavior
- **Integration test (1):** Model flows through from `TerminalSession#requested_model` to `adapter.session_command(model:)` — verify CLI command string
- **Validation tests (2):** `requested_model` and `preferred_model` format validation on model save
- **Frontend tests:** Model Autocomplete renders, loads on runtime change, resets on runtime switch, sends `requestedModel` in create payload

### Notes

- **Cursor protobuf parsing:** The `GetUsableModels` response is protobuf-encoded. Without a `.proto` definition, use string extraction heuristic (validated in brainstorming: consecutive ASCII printable sequences contain model_id and display_name). Alternative: try `Content-Type: application/json` — Cursor's Connect API may support JSON transport.
- **Claude OAuth limitation:** Users authenticated via OAuth (not API key) may not have access to `/v1/models` — the adapter should handle 401/403 gracefully and return empty list.
- **Gemini token refresh:** OAuth access_token may be expired. The adapter should handle 401 and suggest re-authentication. Do not auto-refresh tokens in this scope.
- **Provider API rate limits:** Models endpoints are lightweight and rarely hit. With 24h cache, a user makes at most 4 API calls per day (one per runtime). No rate limit concerns.
- **Future: model capabilities in UI** — Provider responses include rich capability data (thinking, vision, context_window). The normalized shape can be extended later to expose these for smart filtering.
