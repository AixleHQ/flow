---
stepsCompleted: [1, 2, 3]
inputDocuments: []
session_topic: 'LLM Model Management System - storage, sync, API, model selection for agent runtimes'
session_goals: 'Design Model table, sync mechanism, API endpoint, UX for model selection, model passing to container'
selected_approach: 'random-selection'
techniques_used: ['alien-anthropologist', 'morphological-analysis', 'chaos-engineering']
ideas_generated: [27]
context_file: ''
---

# Brainstorming Session Results

**Facilitator:** Artem_Petrov
**Date:** 2026-03-23

## Session Overview

**Topic:** LLM Model Management System - storage, sync, API, model selection for agent runtimes
**Goals:** Design Model table, sync mechanism, API endpoint, UX for model selection, model passing to container

## Technique Execution Results

### Phase 1: Alien Anthropologist

Key findings from examining the system as an outsider:

1. **Runtimes are NOT equal in model selection** — Claude Code supports `--model` flag, Codex has `--model`, Gemini likely supports it, but Cursor CLI abstracts models away entirely
2. **Model data already flows through the system** — `usage_statistics.models` and `terminal_sessions.models` already store used models post-session
3. **"Default" is not a model** — it's "delegate to runtime", a fundamentally different concept from selecting a specific model
4. **session_command already accepts params** — `adapter.session_command(mode:, prompt:)` is the natural place to add `model:` parameter

### Phase 2: Morphological Analysis

Parameters explored: source of truth (5 options), sync mechanism (6 options), model scope (5 options), how to pass model (5 options), UI selection level (5 options), default behavior (5 options).

**Winning combination:** MITM log parsing + DB cache + per-adapter model flag + session+step level selection + null=runtime-default.

### Phase 3: Chaos Engineering

Critical failure scenarios identified:
1. Model deprecated mid-workflow → need active/inactive flag + graceful fallback
2. API key tier mismatch → model visible in DB but fails for user → handle at runtime error level
3. Model name injection in shell command → strict validation: `/\A[a-z0-9][a-z0-9._-]*\z/`
4. Cursor doesn't support model selection → per-adapter `supports_model_selection?` capability

## Key Research Finding: MITM Logs Already Contain Model Lists

Analysis of real MITM HTTP logs from production sessions revealed:

### Codex: `GET chatgpt.com/backend-api/codex/models`
Full JSON response with structured data per model:
- `slug`, `display_name`, `description`, `context_window`, `visibility` (list/hide)
- `supported_reasoning_levels`, `priority`, `input_modalities`
- 10 models total, 5 with visibility="list"

### Cursor CLI: `POST api2.cursor.sh/aiserver.v1.AiService/GetUsableModels`
Protobuf response containing ~30 models from ALL providers:
- model_id + display_name + aliases (e.g. `claude-4.6-opus-high-thinking` → "Opus 4.6 (Thinking)")
- Includes Claude, GPT, Gemini models
- Also: `GetDefaultModelForCli` returns current default

### Claude Code: `api.anthropic.com`
- `GET /api/claude_code/settings` → 404 (OAuth-dependent)
- Models extracted from `POST /v1/messages` request body: `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`
- No explicit list-models endpoint — models likely hardcoded in CLI

### Gemini CLI
- No local MITM logs (uses OTLP). Likely calls Google's `GET /v1beta/models`.

## Agreed Approach

**MITM log parsing with TTL-based freshness:**

1. Add `collect_models` step to adapter cleanup phase (alongside existing `collect_usage`)
2. Parse http.log for model-list API responses (Codex JSON, Cursor protobuf, Claude from request bodies)
3. Store in `agent_models` table with `last_synced_at` timestamp
4. Freshness TTL (~1 week) — if models are stale, next session cleanup refreshes them
5. Flag on session/adapter controls whether to run model collection: skip if `AgentModel.where(agent_runtime: X).fresh?`

### Data Model: `agent_models`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| agent_runtime | string | claude_code, cursor_cli, codex, gemini_cli |
| model_id | string | canonical: "claude-sonnet-4-6", "gpt-5.3-codex" |
| display_name | string | "Claude Sonnet 4.6", "GPT-5.3 Codex" |
| description | text | optional, from API response |
| capabilities | jsonb | {context_window, reasoning_levels, vision, ...} |
| visibility | string | "list" / "hide" — from provider |
| active | boolean | default true, set false when not seen in fresh sync |
| last_seen_at | datetime | updated on each sync |
| metadata | jsonb | raw provider data |
| created_at | datetime | |
| updated_at | datetime | |

Unique index on `[agent_runtime, model_id]`.

### Model Passing: `adapter.session_command(model:)`

Each adapter decides how (or whether) to pass the model:
- **claude_code**: `claude --model claude-sonnet-4-6`
- **codex**: `codex --model gpt-5.3-codex --yolo`
- **gemini_cli**: `gemini --model gemini-2.5-pro --yolo`
- **cursor_cli**: no-op (Cursor manages model internally)

### Storage of Selected Model

- `terminal_sessions.requested_model` — string, nullable, null = runtime default
- `steps.preferred_model` — string, nullable, null = runtime default
- `workflow_runs.step_overrides` already exists as jsonb — can carry per-step model overrides

### API

`GET /api/v1/current_user/models?agent_runtime=claude_code`
Returns active models for the given runtime sorted by display_name.
