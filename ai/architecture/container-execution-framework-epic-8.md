# Container Execution Framework (Epic 8)

Unified framework for running Docker containers with Strategy Pattern:

**Location:** `app/services/container_strategies/`

**Key Components:**
- `ContainerService` - Unified orchestrator with lifecycle phases (before_create → create → before_start → start → before_exec → exec)
- `BaseStrategy` - Abstract base class with timeout protection
- `ToolExecutionStrategy` - Custom tool execution
- `AgentAuthStrategy` - Agent authentication containers
- `AgentSessionStrategy` - Pre-authenticated agent sessions (inherits AgentAuth, adds MCP + credential loading)

**Usage:**
```ruby
# Execute a tool
strategy = ContainerStrategies::ToolExecutionStrategy.new(
  tool: tool,
  parameters: { query: "hello" },
  timeout: 300
)
result = ContainerService.execute(strategy: strategy)

# Start agent session via workflow
ContainerWorkflowService.start_agent_session(
  session: terminal_session,
  credential: agent_credential
)
```

**Temporal Integration:** `UnifiedContainerWorkflow` → `PullDockerImageActivity` → `ExecuteContainerActivity` → wait for signal → `CleanupContainerActivity`

**Documentation:** See `ai/epic-8-unified-container-architecture.md`

---
