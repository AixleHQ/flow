# Story 10.6: Session Launch UI

Status: done

## Story

As a user,
I want to configure and launch a standalone agent session with selected resources (agent persona, tools, skills, MCP servers) from the project page or company page,
so that I can start a fully configured agent session in the right context without a separate launcher page.

## Acceptance Criteria

1. **AC1:** `SessionLaunchWidget` — reusable widget that accepts optional `projectId` prop
2. **AC2:** Agent runtime selector — only agent types where user has `configuredAgents` are enabled; unauthorized shown as disabled with "Not configured" hint
3. **AC3:** Optional agent persona selector — lists agents via project-scoped (`useGetProjectAgentsQuery(projectId)`) or company-scoped (`useGetCompanyAgentsQuery`) API depending on context
4. **AC4:** Optional tools multi-select — lists tools via project or company API; user can pick multiple or skip
5. **AC5:** Optional skills multi-select — lists skills via project or company API; user can pick multiple or skip
6. **AC6:** Optional MCP servers multi-select — lists MCP servers via project or company API; user can pick multiple or skip
7. **AC7:** Mode toggle: Interactive (default) / Non-interactive; when Non-interactive — show text area for initial prompt (required)
8. **AC8:** "Start Session" builds `session_config` and calls `createTerminalSession` with full payload
9. **AC9:** After session created, navigate to `/terminal-test/:routeToken` (reuse existing TerminalTestPage + TerminalSessionWidget)
10. **AC10:** Frontend types updated: `ITerminalSession` includes `sessionConfig`, `ICreateTerminalSessionRequest` includes `sessionConfig`
11. **AC11:** Widget embedded on ProjectPage as new "Sessions" tab
12. **AC12:** Widget embedded on a new company page `/company/sessions` accessible from header nav

## Tasks / Subtasks

- [x] Task 1: Update frontend types (AC: #10)
  - [x] 1.1: Add `ISessionConfig` interface: `agentId?`, `toolIds?`, `skillIds?`, `mcpServerIds?`, `mode?`, `initialPrompt?`
  - [x] 1.2: Add `sessionConfig: ISessionConfig | null` to `ITerminalSession`
  - [x] 1.3: Add `sessionConfig?: ISessionConfig` to `ICreateTerminalSessionRequest.terminalSession`

- [x] Task 2: Create `SessionLaunchWidget` (AC: #1, #2, #3, #4, #5, #6, #7, #8, #9)
  - [x] 2.1: Create `widgets/session-launch/ui/SessionLaunchWidget.tsx` — props: `projectId?: number`
  - [x] 2.2: Create `widgets/session-launch/index.ts` barrel export
  - [x] 2.3: Agent runtime ToggleButtonGroup (reuse pattern from TerminalTestPage), disable unauthorized types using `currentUser.configuredAgents`
  - [x] 2.4: Agent persona Autocomplete (single, optional) — use project or company API depending on `projectId` prop
  - [x] 2.5: Tools Autocomplete (multi-select chips, optional)
  - [x] 2.6: Skills Autocomplete (multi-select chips, optional)
  - [x] 2.7: MCP Servers Autocomplete (multi-select chips, optional)
  - [x] 2.8: Mode ToggleButtonGroup (Interactive / Non-interactive) + conditional TextField for `initialPrompt`
  - [x] 2.9: "Start Session" button — build `session_config`, call `createTerminalSession`, navigate to `/terminal-test/:routeToken` on success

- [x] Task 3: Embed on ProjectPage (AC: #11)
  - [x] 3.1: Add `'sessions'` to `ProjectTab` type in `pages/project/lib/types.ts`
  - [x] 3.2: Add `<Tab value="sessions" label="Sessions" />` in ProjectPage tabs
  - [x] 3.3: Render `<SessionLaunchWidget projectId={numericProjectId} />` when `activeTab === 'sessions'`

- [x] Task 4: Embed on company page (AC: #12)
  - [x] 4.1: Create `pages/company-sessions/ui/CompanySessionsPage.tsx` — renders `<SessionLaunchWidget />` (no projectId)
  - [x] 4.2: Create `pages/company-sessions/index.ts` barrel export
  - [x] 4.3: Add route `/company/sessions` in `routeTree.tsx` and `Routes`
  - [x] 4.4: Add "Sessions" to `navItems` in `AppHeader.tsx`

## Dev Notes

### Backend is READY — no backend changes needed

The controller already accepts `session_config` with all necessary keys:

```ruby
# web/app/controllers/api/v1/terminal_sessions_controller.rb
# session_params uses to_unsafe_h.slice(*TerminalSession::ALLOWED_SESSION_CONFIG_KEYS)
# ALLOWED_SESSION_CONFIG_KEYS = %w[config_files env_vars mcp_server_ids tool_ids agent_id skill_ids mode initial_prompt]
```

`SessionContextService.assemble_session_context` handles injection of all resources into the container. No backend changes required.

### Widget Architecture: `projectId` Prop Drives API Scope

The widget conditionally uses project-scoped or company-scoped API hooks based on `projectId`:

```typescript
// SessionLaunchWidget.tsx
interface SessionLaunchWidgetProps {
  projectId?: number;
}

// Inside:
const { data: agents } = projectId
  ? useGetProjectAgentsQuery(projectId)
  : useGetCompanyAgentsQuery();

const { data: tools } = projectId
  ? useGetProjectToolsQuery(projectId)
  : useGetCompanyToolsQuery();

// Same pattern for skills, MCP servers
```

**IMPORTANT:** Conditional hooks violate React rules. Use a wrapper pattern or pass `skip` param:

```typescript
const projectAgents = useGetProjectAgentsQuery(projectId!, { skip: !projectId });
const companyAgents = useGetCompanyAgentsQuery(undefined, { skip: !!projectId });
const agents = projectId ? projectAgents.data : companyAgents.data;
```

### Frontend Type Gap

Current `ICreateTerminalSessionRequest` is missing `sessionConfig`:

```typescript
// ADD to web/app/frontend/entities/terminal-session/model/types.ts:

export interface ISessionConfig {
  agentId?: number;
  toolIds?: number[];
  skillIds?: number[];
  mcpServerIds?: number[];
  mode?: 'interactive' | 'non_interactive';
  initialPrompt?: string;
}

// Update ITerminalSession:
export interface ITerminalSession {
  // ... existing fields ...
  sessionConfig: ISessionConfig | null;  // ← ADD
}

// Update ICreateTerminalSessionRequest:
export interface ICreateTerminalSessionRequest {
  terminalSession: {
    sessionType: TerminalSessionType;
    agentType: AgentType;
    projectId?: number;
    metadata?: Record<string, unknown>;
    sessionConfig?: ISessionConfig;  // ← ADD
  };
}
```

### Existing API Hooks to Reuse

| Resource | Project-scoped | Company-scoped | File |
|----------|---------------|----------------|------|
| Agents | `useGetProjectAgentsQuery(projectId)` | `useGetCompanyAgentsQuery()` | `features/agents-management/api/agentsApi.ts` |
| Tools | `useGetProjectToolsQuery(projectId)` | `useGetCompanyToolsQuery()` | `features/tools-management/api/toolsApi.ts` |
| Skills | `useGetProjectSkillsQuery(projectId)` | `useGetCompanySkillsQuery()` | `features/skills-management/api/skillsApi.ts` |
| MCP Servers | `useGetProjectMcpServersQuery(projectId)` | `useGetMcpServersQuery()` | `entities/mcp-server/api/mcpServersApi.ts` |
| Current User | — | `useGetCurrentUserQuery()` → `configuredAgents: AgentType[]` | `entities/user/` |

### Agent Runtime vs Agent Persona

- **Agent Runtime** (`agentType`): Which CLI runs — `claude_code`, `codex`, `gemini_cli`, `cursor_cli`. Required. Must be in `configuredAgents`.
- **Agent Persona** (`agentId` in `session_config`): `Agent` model record with custom system prompt. Optional. Injected via `SessionContextService`.

Separate concepts. Runtime = what container runs. Persona = how it behaves.

### ProjectPage Integration

Project page already has tabs pattern. Add `'sessions'` to `ProjectTab` type and render the widget:

```typescript
// pages/project/lib/types.ts
export type ProjectTab =
  | 'overview'
  | 'workflows'
  // ... existing ...
  | 'sessions'   // ← ADD
  | 'settings';

// pages/project/ui/ProjectPage.tsx — in Tabs:
<Tab value="sessions" label="Sessions" sx={styles.tab} />

// In content area:
{activeTab === 'sessions' && <SessionLaunchWidget projectId={Number(projectId)} />}
```

### Company Page Integration

Add new company page and header nav item:

```typescript
// widgets/AppHeader/ui/AppHeader.tsx — add to navItems:
{ path: Routes.frontend.companySessionsPath, label: 'Sessions' },  // NOT adminOnly
```

### Widget Layout

```
┌────────────────────────────────────────────────┐
│  Agent Runtime:                                 │
│  ┌──────────┬──────────┬──────────┬──────────┐ │
│  │ Claude   │ Cursor   │ Codex    │ Gemini   │ │
│  │ Code ●   │ CLI      │ (off)    │ CLI      │ │
│  └──────────┴──────────┴──────────┴──────────┘ │
│                                                  │
│  ── Optional Configuration ────────────────     │
│                                                  │
│  Agent Persona: [  Search agents...    ▼  ]     │
│  Tools:         [  Search tools...     ▼  ]     │
│  Skills:        [  Search skills...    ▼  ]     │
│  MCP Servers:   [  Search MCP...       ▼  ]     │
│                                                  │
│  Mode:  [ Interactive ● ] [ Non-interactive ]    │
│                                                  │
│  (if non-interactive:)                           │
│  ┌──────────────────────────────────────────┐   │
│  │ Enter your prompt...                      │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│           [ Start Session ]                      │
│                                                  │
└────────────────────────────────────────────────┘
```

### Feature-Sliced Design Placement

```
web/app/frontend/
├── widgets/
│   └── session-launch/
│       ├── ui/
│       │   └── SessionLaunchWidget.tsx    ← Reusable widget
│       └── index.ts
├── pages/
│   ├── project/
│   │   ├── ui/ProjectPage.tsx             ← ADD "sessions" tab
│   │   └── lib/types.ts                   ← ADD 'sessions' to ProjectTab
│   └── company-sessions/
│       ├── ui/CompanySessionsPage.tsx      ← Wrapper page for company context
│       └── index.ts
├── entities/
│   └── terminal-session/
│       └── model/types.ts                 ← Update types
├── shared/routes/routes.ts                ← Add companySessionsPath
├── app/routeTree.tsx                      ← Add companySessionsRoute
```

### Case Conversion Reminder

Frontend sends `camelCase` → axios interceptor converts to `snake_case` before Rails. `sessionConfig.agentId` → `session_config.agent_id`. No manual conversion needed.

### After Session Created

On successful `createTerminalSession`:
1. Response includes `data.routeToken`
2. `navigate({ to: Routes.frontend.terminalTestSessionPath(routeToken) })`
3. TerminalTestPage loads session by routeToken and shows `TerminalSessionWidget`

### Key Files

**New files:**
- `web/app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx`
- `web/app/frontend/widgets/session-launch/index.ts`
- `web/app/frontend/pages/company-sessions/ui/CompanySessionsPage.tsx`
- `web/app/frontend/pages/company-sessions/index.ts`

**Modified files:**
- `web/app/frontend/entities/terminal-session/model/types.ts` — `ISessionConfig`, update `ITerminalSession`, `ICreateTerminalSessionRequest`
- `web/app/frontend/pages/project/ui/ProjectPage.tsx` — add "Sessions" tab
- `web/app/frontend/pages/project/lib/types.ts` — add `'sessions'` to `ProjectTab`
- `web/app/frontend/app/routeTree.tsx` — add `companySessionsRoute`
- `web/app/frontend/shared/routes/routes.ts` — add `companySessionsPath`
- `web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx` — add "Sessions" nav item

### Previous Story Intelligence

Story 9-8 established:
- `session_config` supports `mode` and `initial_prompt` fields
- `assemble_session_context` orchestrates all injection in order
- Backend is fully ready to accept all session_config keys

TerminalTestPage patterns:
- Agent selection via ToggleButtonGroup with color coding per agent
- Session creation via `useCreateTerminalSessionMutation`
- Navigate to `/terminal-test/:routeToken` on success

### References

- [Source: web/app/frontend/pages/terminal-test/ui/TerminalTestPage.tsx — agent selector + session creation pattern]
- [Source: web/app/frontend/pages/project/ui/ProjectPage.tsx — tab pattern, `AgentsPanel`, `ToolsPanel` embedding]
- [Source: web/app/frontend/pages/project/lib/types.ts — `ProjectTab` type]
- [Source: web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx — `navItems` for company navigation]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — types to extend]
- [Source: web/app/frontend/shared/api/terminalSessionApi.ts — `createTerminalSession` mutation]
- [Source: web/app/frontend/app/routeTree.tsx — routing pattern]
- [Source: web/app/controllers/api/v1/terminal_sessions_controller.rb — session_params already supports session_config]
- [Source: web/app/models/terminal_session.rb — ALLOWED_SESSION_CONFIG_KEYS]
- [Source: web/app/frontend/features/agents-management/api/agentsApi.ts — project/company agents hooks]
- [Source: web/app/frontend/features/tools-management/api/toolsApi.ts — project/company tools hooks]
- [Source: web/app/frontend/features/skills-management/api/skillsApi.ts — project/company skills hooks]
- [Source: web/app/frontend/entities/mcp-server/api/mcpServersApi.ts — project/company MCP hooks]
- [Source: _bmad-output/implementation-artifacts/9-8-full-session-context-assembly-and-interactive-agents.md — previous story]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-max-thinking

### Debug Log References

- TypeScript: 0 errors after fix (`npx tsc --noEmit` clean)
- Linting: 0 errors on all modified files
- No frontend tests exist in project yet (vitest installed but no test files)

### Completion Notes List

- Added `ISessionConfig`, `SessionMode` types to `entities/terminal-session/model/types.ts`. Extended `ITerminalSession` with `sessionConfig` field and `ICreateTerminalSessionRequest` with optional `sessionConfig`.
- Created `SessionLaunchWidget` at `widgets/session-launch/` — reusable widget accepting optional `projectId` prop. Uses conditional `skip` pattern for RTK Query hooks to switch between project-scoped and company-scoped APIs without violating React hooks rules.
- Widget includes: agent runtime ToggleButtonGroup (disabled for unconfigured agents with tooltip), Autocomplete selectors for agent persona (single), tools (multi), skills (multi), MCP servers (multi), mode toggle (interactive/non-interactive), conditional initial prompt textarea with validation.
- "Start Session" builds `session_config` payload from selections, calls `createTerminalSession`, navigates to `/terminal-test/:routeToken` on success.
- Added barrel exports for API hooks (`useGetCompanyAgentsQuery`, `useGetProjectAgentsQuery`, etc.) to `features/agents-management`, `features/tools-management`, `features/skills-management` barrel files — previously only internal components were exported.
- Embedded widget on ProjectPage as new "Sessions" tab (added to `ProjectTab` type and tab list).
- Created `CompanySessionsPage` at `pages/company-sessions/` — wrapper rendering `SessionLaunchWidget` without `projectId` (company-level resources).
- Added `/company/sessions` route to `routeTree.tsx` and `Routes.frontend.companySessionsPath`.
- Added "Sessions" nav item to `AppHeader` (not admin-only, visible to all users).
- Fixed TS error: `useGetProjectMcpServersQuery` expects `string` arg (unlike agents/tools/skills which expect `number`).

### File List

- `web/app/frontend/entities/terminal-session/model/types.ts` — added `SessionMode`, `ISessionConfig`, extended `ITerminalSession` and `ICreateTerminalSessionRequest`
- `web/app/frontend/widgets/session-launch/ui/SessionLaunchWidget.tsx` — NEW: reusable session launch widget
- `web/app/frontend/widgets/session-launch/index.ts` — NEW: barrel export
- `web/app/frontend/pages/company-sessions/ui/CompanySessionsPage.tsx` — NEW: company sessions page wrapper
- `web/app/frontend/pages/company-sessions/index.ts` — NEW: barrel export
- `web/app/frontend/pages/project/lib/types.ts` — added `'sessions'` to `ProjectTab`
- `web/app/frontend/pages/project/ui/ProjectPage.tsx` — added Sessions tab + SessionLaunchWidget rendering
- `web/app/frontend/app/routeTree.tsx` — added `companySessionsRoute`
- `web/app/frontend/shared/routes.ts` — added `companySessionsPath`
- `web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx` — added "Sessions" to `navItems`
- `web/app/frontend/features/agents-management/index.ts` — added API hook re-exports
- `web/app/frontend/features/tools-management/index.ts` — added API hook re-exports
- `web/app/frontend/features/skills-management/index.ts` — added API hook re-exports
