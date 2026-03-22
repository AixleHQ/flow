# Frontend Component Inventory

Generated: 2026-03-19

## Key Pages (unique screens)

| # | Route | Page | What it shows |
|---|-------|------|---------------|
| 1 | `/login` | LoginPage | Email/password, Google OAuth |
| 2 | `/onboarding` | OnboardingPage | Multi-step: profile, agents, login |
| 3 | `/company/projects` | ProjectsPage | Project grid with ProjectCard |
| 4 | `/company/projects/:id/:tab` | ProjectPage | Tabbed: overview, board, assets, repos, workflows, runs, sessions, config, agents, tools, mcp-servers, skills, members, settings, analytics |
| 5 | `/company/sessions` | CompanySessionsPage | SessionHistoryWidget |
| 6 | `/company/sessions/new` | CompanySessionNewPage | SessionLaunchWidget + TerminalSessionWidget |
| 7 | `/company/sessions/:id` | CompanySessionViewPage | SessionSummaryCard + TerminalSessionWidget |
| 8 | `/company/sessions/:id/artifacts` | SessionArtifactsPage | Artifacts table |
| 9 | `/company/members` | CompanyMembersPage | Members table + invite |
| 10 | `/company/workflows` | WorkflowsPage → WorkflowsPanel | Workflow list |
| 11 | `/company/workflows/:id/builder` | WorkflowBuilderPage | Step editor, BaseResourcesSection |
| 12 | `/company/projects/:id/workflow-runs/:runId` | WorkflowRunPage | WorkflowStepper + tabs |
| 13 | `/company/tools` | ToolsPage → ToolsPanel | Tools table |
| 14 | `/company/skills` | SkillsPage → SkillsPanel | Skills table |
| 15 | `/company/agents` | AgentsPage → AgentsPanel | Agents table |
| 16 | `/company/mcp-servers` | McpServersPage → McpServersPanel | MCP servers table |
| 17 | `/company/config-items` | ConfigItemsPage → ConfigItemsPanel | Config items table |
| 18 | `/company/assets` | AssetsPage → AssetsPanel | Assets table + preview |
| 19 | `/company/repositories` | RepositoriesPage → RepositoriesPanel | Repositories list |
| 20 | `/company/integrations` | IntegrationsPage → IntegrationsPanel | Integrations (GitHub) |
| 21 | `/profile` | ProfilePage | Profile form + agent credentials |

## Key Widgets

| Widget | File | Description |
|--------|------|-------------|
| AppHeader | `widgets/AppHeader/ui/AppHeader.tsx` | Top bar: logo, nav dropdowns, user menu |
| AppSidebar | `widgets/AppSidebar/ui/AppSidebar.tsx` | Collapsible sidebar with project tabs |
| SessionLaunchWidget | `widgets/session-launch/ui/SessionLaunchWidget.tsx` | Session config: agent, persona, tools, skills, MCPs, assets, repos, mode, prompt, BMAD |
| TerminalSessionWidget | `widgets/terminal-session/ui/TerminalSessionWidget.tsx` | Split view: editor + Terminal + StatusBar |
| SessionHistoryWidget | `widgets/session-history/ui/SessionHistoryWidget.tsx` | Session history list with search |
| WorkflowRunsWidget | `widgets/workflow-runs/ui/WorkflowRunsWidget.tsx` | Recent workflow runs list |

## Key Shared UI

| Component | File | Description |
|-----------|------|-------------|
| StatusBar | `shared/ui/StatusBar/StatusBar.tsx` | Agent, status, cost, duration |
| Terminal | `shared/ui/Terminal/Terminal.tsx` | xterm.js terminal |
| WorkflowStepper | `shared/ui/WorkflowStepper/WorkflowStepper.tsx` | Vertical stepper |
| Logo | `shared/ui/Logo/Logo.tsx` | App logo |
| Loader | `shared/ui/Loader/Loader.tsx` | Loading spinner |
| EmojiPicker | `shared/ui/EmojiPicker/EmojiPicker.tsx` | Emoji picker |

## Key Entity Cards

| Component | File | Description |
|-----------|------|-------------|
| ProjectCard | `entities/project/ui/ProjectCard.tsx` | Project card in grid |
| SessionSummaryCard | `entities/terminal-session/ui/SessionSummaryCard.tsx` | Session summary |
| TaskCard | `entities/board-task/ui/TaskCard.tsx` | Task card for kanban |
| AssetCard | `entities/asset/ui/AssetCard.tsx` | Asset card |

## Board (Kanban) Feature

BoardPanel, BoardColumn, TaskSidebar, TaskDetailsTab, CommentsTab, AssetsTab, ActivityTab, CreateTaskDialog, PresetSelector, BoardFilterBar

## Management Panels (all follow same pattern: table + CRUD dialogs)

- ToolsPanel + ToolsTable + ToolFormDialog
- SkillsPanel + SkillsTable + SkillFormDialog
- AgentsPanel + AgentsTable + AgentFormDialog
- McpServersPanel + McpServersTable + McpServerFormDialog
- ConfigItemsPanel + ConfigItemsTable + ConfigItemFormDialog
- AssetsPanel + AssetsTable + AssetPreviewDialog + UploadAssetDialog
- RepositoriesPanel + AddRepositoryDialog + EditRepositoryDialog
- IntegrationsPanel

## Workflows

- WorkflowsPanel + CreateWorkflowDialog + EditWorkflowDialog
- WorkflowBuilderPage + WorkflowStepsList + StepCard + AddStepDialog + BaseResourcesSection
- WorkflowRunPage + WorkflowAssetsReview + RunWorkflowDialog + RunWorkflowModal

## Total: ~130 .tsx component files
