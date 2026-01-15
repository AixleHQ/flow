# Interactive Agent Architecture: Palad

**Date:** 2026-01-16
**Author:** Artem Petrov (via Brainstorming with Carson)
**Status:** Draft / Work in Progress

---

## 🎯 Problem Statement

How to run an interactive AI agent in the cloud that:
1. Streams responses in real time
2. Asks questions and waits for answers (BMAD-style)
3. Performs actions (files, commands) and shows the result
4. Operates within a multi-step workflow with accumulating context

---

## 🏗️ Architectural decision

### Key principles

1. **Each step = a separate session** with an isolated workspace
2. **Context mounting** — assets from previous steps are available as readonly
3. **Temporal for orchestration** — durability, cross-language, long-running workflows
4. **LangGraph for agent logic** — inside each step
5. **Sequential execution** — one agent at a time, human checkpoint between steps

### Conceptual model

```
WORKFLOW: Replatforming
│
├── STEP 1: Cartographer
│   └── Session A
│       ├── Mounted: /repo (source code)
│       ├── Output: /assets/step-1/surface_area.md
│       └── PAUSE → Human checkpoint
│
├── STEP 2: Behavior Extractor  
│   └── Session B
│       ├── Mounted: /repo
│       ├── Mounted: /assets/step-1/* (readonly)
│       ├── Output: /assets/step-2/scenarios/
│       └── PAUSE → Human checkpoint
│
├── STEP 3: Data & Invariants
│   └── Session C
│       ├── Mounted: /repo
│       ├── Mounted: /assets/step-1/* (readonly)
│       ├── Mounted: /assets/step-2/* (readonly)
│       ├── Output: /assets/step-3/domain_model.md
│       └── PAUSE → Human checkpoint
│
└── ... (7 agents total for replatforming)
```

---

## 📊 Data Model

### WorkflowRun

```
┌─────────────────────────────────────────────────────────────┐
│                        WORKFLOW RUN                          │
│  id: uuid                                                    │
│  workflow_type: "replatforming"                             │
│  status: in_progress | paused | completed                   │
│  current_step: 2                                            │
│  temporal_workflow_id: "wf-xxx"                             │
│  input_repo_url: "gitlab.com/..."                           │
│  created_at, updated_at                                     │
└─────────────────────────────────────────────────────────────┘
```

### Session

```
┌─────────────────────────────────────────────────────────────┐
│                         SESSION                              │
│  id: uuid                                                    │
│  workflow_run_id: fk                                        │
│  step_number: 2                                             │
│  agent_type: "behavior_extractor"                           │
│  status: active | waiting_input | completed                 │
│  mounted_assets: [step-1-id, step-2-id]                     │
│  workspace_path: "/sessions/{id}/"                          │
│  temporal_activity_id: "act-xxx"                            │
└─────────────────────────────────────────────────────────────┘
```

### Asset

```
┌─────────────────────────────────────────────────────────────┐
│                          ASSET                               │
│  id: uuid                                                    │
│  session_id: fk                                             │
│  asset_type: "surface_area" | "scenario" | "contract"       │
│  file_path: "surface_area.md"                               │
│  s3_key: "workflows/{run_id}/step-1/surface_area.md"        │
│  metadata: jsonb                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 Execution Flow

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                         RAILS WEB                            │
│  • REST API for managing workflows                        │
│  • WebSocket for streaming + UI updates                     │
│  • ActionCable channels per session                          │
└─────────────────────────────────────────────────────────────┘
     │                              ▲
     │ 1. POST /workflow_runs      │ 6. WebSocket: stream tokens
     │    {type: replatforming,    │    + UI updates
     │     repo_url: ...}          │
     ▼                              │
┌─────────────────────────────────────────────────────────────┐
│                    TEMPORAL (Orchestrator)                   │
│                                                              │
│  WorkflowRun::ReplatformingWorkflow                         │
│    │                                                         │
│    ├── Step 1: execute_agent_session(cartographer)          │
│    │     └── Activity → Python AI Engine                    │
│    │           └── Returns: session_id, assets[]            │
│    │     └── WAIT for signal: "human_approved"              │
│    │                                                         │
│    ├── Step 2: execute_agent_session(behavior_extractor,    │
│    │              mounted: [step_1_assets])                  │
│    │     └── Activity → Python AI Engine                    │
│    │     └── WAIT for signal: "human_approved"              │
│    │                                                         │
│    └── ... continue until complete                          │
└─────────────────────────────────────────────────────────────┘
     │
     │ 2. Start Activity
     ▼
┌─────────────────────────────────────────────────────────────┐
│                   PYTHON AI ENGINE                           │
│  • LangGraph agents with tools                              │
│  • Streaming via WebSocket                                  │
│  • Human-in-the-loop via Temporal signals                   │
└─────────────────────────────────────────────────────────────┘
```

### Human Input Pattern (Temporal Signal)

Problem: how do you stop the agent, wait for the user's response, and continue?

**Solution: Temporal Signal Pattern**

```python
# In a Temporal Workflow (Python or Ruby via SDK)
@workflow.defn
class ReplatformingWorkflow:
    def __init__(self):
        self.human_response = None
        
    @workflow.run
    async def run(self, input: WorkflowInput):
        for step in self.steps:
            # Run agent until it needs input or completes
            result = await workflow.execute_activity(
                run_agent_step,
                args=[step, input],
                start_to_close_timeout=timedelta(hours=24)
            )
            
            if result.needs_human_approval:
                # Workflow pauses here, can survive restarts
                await workflow.wait_condition(
                    lambda: self.human_response is not None,
                    timeout=timedelta(days=7)  # Long timeout
                )
                
                # Process response and continue
                self.human_response = None
                
    @workflow.signal
    def provide_human_response(self, response: str):
        self.human_response = response
```

**How it works:**
1. Agent streams → reaches input point → Activity completes with `needs_human_approval=True`
2. Workflow calls `wait_condition` — Temporal persists the state
3. UI shows a prompt to the user
4. User responds → Rails sends a signal to Temporal
5. Workflow wakes up, continues with the next Activity

**Timeout + Recovery:**
- A Temporal workflow can live for days/weeks in a paused state
- When the user returns, the workflow resumes from the saved state
- All assets are already on disk/S3, the context is not lost

---

## 📁 Workspace Structure

```
/workspaces/
└── {workflow_run_id}/
    ├── repo/                    # Git clone (shared across steps)
    │   └── ... source code
    │
    ├── step-1/                  # Cartographer output
    │   ├── surface_area.md
    │   └── system_index.md
    │
    ├── step-2/                  # Behavior Extractor output
    │   ├── scenarios/
    │   │   ├── auth_flow.md
    │   │   └── payment_flow.md
    │   └── error_catalog.md
    │
    └── current_session/         # Active session workspace
        ├── repo/ → symlink to ../repo
        ├── context/ → symlinks to previous steps (readonly)
        │   ├── step-1/ → ../../step-1
        │   └── step-2/ → ../../step-2
        └── output/              # Current step writes here
```

---

## 🛠️ Agent Tools

```python
AGENT_TOOLS = [
    # File operations
    ReadFileTool(),           # Read files from repo/ and context/
    WriteFileTool(),          # Write only to output/
    SearchCodeTool(),         # ripgrep over repo/
    ListDirectoryTool(),      # ls
    
    # Context tools
    ReadContextTool(),        # Specifically for reading assets from previous steps
    
    # BMAD-style interaction
    AskHumanTool(),           # Ask a question, get an answer
    ProposeOptionsTool(),     # Propose options, get a choice
    
    # Output tools
    CreateAssetTool(),        # Create an asset with metadata
    MarkEvidenceTool(),       # Mark a claim with evidence
]
```

---

## 🖥️ UX: What User Sees

```
┌─────────────────────────────────────────────────────────────┐
│  PALAD - Replatforming Workflow                    [Step 2/7]│
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  🤖 Behavior Extractor Agent                                │
│  ─────────────────────────────────────────────────────────  │
│                                                              │
│  Analyzing endpoint: POST /api/v1/orders                    │
│                                                              │
│  📁 Context loaded:                                         │
│    • surface_area.md (from Step 1)                          │
│    • system_index.md (from Step 1)                          │
│                                                              │
│  Behavior found:                                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ **Scenario: Create Order**                              ││
│  │ Given: authenticated user with cart                     ││
│  │ When: POST /api/v1/orders {items: [...]}               ││
│  │ Then: order created, inventory decremented              ││
│  │                                                          ││
│  │ Evidence: app/controllers/orders_controller.rb:45-67    ││
│  │ Evidence: app/services/order_service.rb:12-34           ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ❓ I see an edge case: what happens if inventory = 0?      │
│     The code is ambiguous. Options:                         │
│     [1] Error 422, order is not created                     │
│     [2] Order is created with backorder status              │
│     [3] Needs to be checked at runtime                      │
│                                                              │
│  Your choice: _                                             │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│ [Enter response] [Skip] [Pause workflow] [View assets]      │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Implementation Roadmap

### Iteration 0: Proof of Concept
- [ ] Single agent (Cartographer)
- [ ] Hardcoded workflow (not from DB)
- [ ] WebSocket streaming works
- [ ] AskHuman tool works
- [ ] Files are saved locally

### Iteration 1: Multi-step
- [ ] Two agents in sequence
- [ ] Mounting assets between steps
- [ ] Temporal orchestration with signals
- [ ] S3 sync on step completion

### Iteration 2: Full Pipeline
- [ ] All 7 agents for replatforming
- [ ] Workflow definition from DB
- [ ] UI for workflow selection
- [ ] Progress tracking

---

## 🤖 Replatforming Agents (7 roles)

| # | Agent | Responsibility | Output |
|---|-------|----------------|--------|
| 1 | **Cartographer** | Surface area: routes, jobs, events, models | system_index.md, surface_area.md |
| 2 | **Behavior Extractor** | Scenarios by endpoint/use-case + errors | scenarios/*.md, error_catalog.md |
| 3 | **Data & Invariants** | DB, constraints, domain model | domain_model.md, db_constraints.md |
| 4 | **Integrations & Contracts** | OpenAPI, events, external services | api_contract.yaml, integrations.md |
| 5 | **Permissions & Auth** | Access matrix | permissions.md |
| 6 | **Test Smith** | Characterization tests | characterization_tests/ |
| 7 | **Editor/Integrator** | Spec assembly, consistency | spec_pack_index.md, gaps_risks.md |

### Key rule for all agents

> **No claims without Evidence** (file path + lines / function).
> No proof → UNKNOWN + TODO.

---

## 📋 Open Questions

1. **Branching** — what if at step 3 the user wants to go back to step 2? (For now: not supported, sequential only)

2. **Parallelism within a step** — can the Behavior Extractor analyze 47 endpoints in parallel? (For now: sequentially)

3. **WebSocket reconnection** — what if the user reloaded the page? (Solution: reconnect to the same workflow, get the current state)

---

## 🔧 Deep Dive: Temporal + LangGraph Integration

### Architectural decisions

| Question | Solution | Rationale |
|--------|---------|-------------|
| **State storage** | PostgreSQL | Already in the stack, reliable, queryable |
| **Streaming** | Redis pubsub | Python → Redis → Rails → WebSocket |
| **Activity timeout** | 12 hours | Enough for long analyses |
| **Error recovery** | Restore from the last checkpoint | Retry from the saved state |

### Final component architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           BROWSER                                │
│  xterm.js / React UI                                            │
│  WebSocket connection to Rails                                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ WebSocket (ActionCable)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                           RAILS                                  │
│  • REST API: /workflow_runs, /sessions                          │
│  • WebSocket: ActionCable subscriber to Redis                   │
│  • Temporal Client: start workflows, send signals               │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│        TEMPORAL         │   │         REDIS           │
│  • Workflows            │   │  • Pub/Sub for stream   │
│  • Activity scheduling  │   │  • Channel: session:*   │
│  • Signal handling      │   │                         │
│  • 12h activity timeout │   │                         │
└────────────┬────────────┘   └────────────▲────────────┘
             │                             │
             │ gRPC                        │ Publish
             ▼                             │
┌─────────────────────────────────────────────────────────────────┐
│                      PYTHON AI ENGINE                            │
│  • Temporal Worker (Activities)                                  │
│  • LangGraph Agents                                              │
│  • PostgreSQL Checkpointer                                       │
│  • Streaming → Redis                                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ Read/Write
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                       POSTGRESQL                                 │
│  • workflow_runs                                                 │
│  • sessions                                                      │
│  • assets                                                        │
│  • agent_checkpoints (LangGraph state)                          │
└─────────────────────────────────────────────────────────────────┘
```

### PostgreSQL: Agent Checkpoints Table

```sql
CREATE TABLE agent_checkpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id),
    checkpoint_id VARCHAR(255) NOT NULL,  -- LangGraph thread_id + checkpoint_id
    
    -- LangGraph state
    channel_values JSONB NOT NULL,        -- Current channel values
    channel_versions JSONB NOT NULL,      -- Versions for conflict resolution
    pending_sends JSONB,                  -- Pending messages
    
    -- Metadata
    step_name VARCHAR(255),               -- "analyze", "ask_human", etc.
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(session_id, checkpoint_id)
);

CREATE INDEX idx_checkpoints_session ON agent_checkpoints(session_id);
```

### LangGraph PostgreSQL Checkpointer

```python
# checkpointer.py

from langgraph.checkpoint.base import BaseCheckpointSaver, Checkpoint
from psycopg_pool import AsyncConnectionPool
import json

class PostgresCheckpointer(BaseCheckpointSaver):
    def __init__(self, pool: AsyncConnectionPool, session_id: str):
        self.pool = pool
        self.session_id = session_id
        
    async def aget(self, config: dict) -> Optional[Checkpoint]:
        """Load the latest checkpoint for the session"""
        thread_id = config["configurable"]["thread_id"]
        
        async with self.pool.connection() as conn:
            row = await conn.fetchrow("""
                SELECT channel_values, channel_versions, pending_sends
                FROM agent_checkpoints
                WHERE session_id = $1 AND checkpoint_id LIKE $2
                ORDER BY created_at DESC
                LIMIT 1
            """, self.session_id, f"{thread_id}%")
            
            if not row:
                return None
                
            return Checkpoint(
                v=1,
                channel_values=row["channel_values"],
                channel_versions=row["channel_versions"],
                pending_sends=row["pending_sends"] or [],
            )
    
    async def aput(self, config: dict, checkpoint: Checkpoint) -> dict:
        """Save the checkpoint"""
        thread_id = config["configurable"]["thread_id"]
        checkpoint_id = f"{thread_id}:{checkpoint.id}"
        
        async with self.pool.connection() as conn:
            await conn.execute("""
                INSERT INTO agent_checkpoints 
                    (session_id, checkpoint_id, channel_values, channel_versions, pending_sends, step_name)
                VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT (session_id, checkpoint_id) 
                DO UPDATE SET 
                    channel_values = EXCLUDED.channel_values,
                    channel_versions = EXCLUDED.channel_versions,
                    pending_sends = EXCLUDED.pending_sends
            """, 
                self.session_id,
                checkpoint_id,
                json.dumps(checkpoint.channel_values),
                json.dumps(checkpoint.channel_versions),
                json.dumps(checkpoint.pending_sends),
                self._extract_step_name(checkpoint),
            )
            
        return config
    
    def _extract_step_name(self, checkpoint: Checkpoint) -> str:
        """Extract the current step name for debugging"""
        return checkpoint.channel_values.get("__current_node__", "unknown")
```

### Error Recovery Flow

```
Activity starts
    │
    ├── Load last checkpoint from Postgres (if exists)
    │       └── Resume agent from that state
    │
    ├── Agent runs, checkpoints every N steps
    │       └── Each checkpoint saved to Postgres
    │
    ├── IF Activity crashes / timeout:
    │       └── Temporal retries Activity
    │       └── Activity loads last checkpoint
    │       └── Agent continues from there
    │
    └── IF needs human input:
            └── Final checkpoint saved
            └── Activity completes with needs_input=True
            └── Next Activity loads this checkpoint
```

### Temporal Activity with Recovery and Streaming

```python
# activities.py

@activity.defn
async def run_agent_chunk(
    session_id: str,
    agent_type: str,
    human_response: Optional[str] = None,
    retry_attempt: int = 0
) -> AgentChunkResult:
    
    workspace = await setup_workspace(session_id)
    
    # Postgres checkpointer for this session
    checkpointer = PostgresCheckpointer(db_pool, session_id)
    
    # Create the agent with the checkpointer
    agent = create_agent(
        agent_type=agent_type,
        workspace=workspace,
        checkpointer=checkpointer,
    )
    
    # Config for LangGraph (thread_id = unique stream identifier)
    config = {
        "configurable": {
            "thread_id": f"{session_id}:{agent_type}",
        }
    }
    
    # Check whether a checkpoint exists (recovery or continuation)
    last_checkpoint = await checkpointer.aget(config)
    
    if last_checkpoint:
        logger.info(f"Resuming from checkpoint, step: {last_checkpoint.metadata.get('step')}")
    
    # If there is a human response — add it to the input
    input_data = {"human_response": human_response} if human_response else {}
    
    # Streaming with heartbeat
    stream_manager = StreamingManager(session_id)
    
    try:
        async for event in agent.astream_events(input_data, config=config):
            # Heartbeat on every event (Temporal knows we're alive)
            activity.heartbeat({"last_event": event["type"]})
            
            if event["type"] == "on_chat_model_stream":
                # Token streaming
                token = event["data"]["chunk"].content
                if token:
                    await stream_manager.emit({"type": "token", "content": token})
                    
            elif event["type"] == "on_tool_start":
                await stream_manager.emit({
                    "type": "tool_start",
                    "tool": event["name"],
                    "input": event["data"].get("input"),
                })
                
            elif event["type"] == "on_tool_end":
                await stream_manager.emit({
                    "type": "tool_end",
                    "tool": event["name"],
                    "output": event["data"].get("output"),
                })
                
            elif event["type"] == "on_chain_end":
                # Check if agent is waiting for human
                state = agent.get_state(config)
                if state.next == ("ask_human",):
                    # Agent paused at human input node
                    return AgentChunkResult(
                        status="needs_human_input",
                        prompt=state.values.get("human_prompt"),
                        options=state.values.get("human_options"),
                    )
        
        # Agent completed successfully
        return AgentChunkResult(
            status="completed",
            assets=await workspace.finalize_assets(),
        )
        
    except Exception as e:
        logger.error(f"Agent failed: {e}")
        # Checkpoint is already saved — the next retry will continue
        raise  # Temporal retry
```

### Temporal Workflow with 12h timeout

```python
# workflows.py

from datetime import timedelta
from temporalio import workflow
from temporalio.common import RetryPolicy

@workflow.defn
class AgentSessionWorkflow:
    def __init__(self):
        self.human_response: Optional[str] = None
        
    @workflow.run
    async def run(self, input: SessionInput) -> SessionResult:
        
        retry_policy = RetryPolicy(
            initial_interval=timedelta(seconds=10),
            backoff_coefficient=2.0,
            maximum_interval=timedelta(minutes=5),
            maximum_attempts=5,  # 5 attempts on crash
        )
        
        result = await workflow.execute_activity(
            run_agent_chunk,
            args=[input.session_id, input.agent_type, None],
            start_to_close_timeout=timedelta(hours=12),  # 12 hours max
            heartbeat_timeout=timedelta(minutes=5),       # If no heartbeat for 5 min — retry
            retry_policy=retry_policy,
        )
        
        while result.status == "needs_human_input":
            # Notify UI
            await workflow.execute_activity(
                notify_ui_needs_input,
                args=[input.session_id, result.prompt, result.options],
                start_to_close_timeout=timedelta(seconds=30),
            )
            
            # Wait for human (up to 7 days)
            try:
                await workflow.wait_condition(
                    lambda: self.human_response is not None,
                    timeout=timedelta(days=7)
                )
            except asyncio.TimeoutError:
                # User abandoned — cleanup and fail
                return SessionResult(status="abandoned")
            
            # Continue with human response
            result = await workflow.execute_activity(
                run_agent_chunk,
                args=[input.session_id, input.agent_type, self.human_response],
                start_to_close_timeout=timedelta(hours=12),
                heartbeat_timeout=timedelta(minutes=5),
                retry_policy=retry_policy,
            )
            
            self.human_response = None
        
        return SessionResult(
            status="completed",
            assets=result.assets,
        )
    
    @workflow.signal
    def provide_human_response(self, response: str):
        self.human_response = response
```

### Streaming via Redis

```python
# streaming.py

import redis.asyncio as redis
import json

class StreamingManager:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.redis = redis.from_url("redis://localhost")
        
    async def emit(self, event: dict):
        """Activity calls this to send to the UI"""
        channel = f"session:{self.session_id}:stream"
        await self.redis.publish(channel, json.dumps(event))
```

### Rails: ActionCable Subscriber

```ruby
# app/channels/session_channel.rb

class SessionChannel < ApplicationCable::Channel
  def subscribed
    @session_id = params[:session_id]
    
    # Subscribe to Redis channel
    stream_from "session:#{@session_id}:stream"
  end

  def unsubscribed
    stop_all_streams
  end
  
  def respond(data)
    # User sent response — forward to Temporal
    TemporalClient.signal_workflow(
      workflow_id: @session.workflow_run.temporal_workflow_id,
      signal: "provide_human_response",
      args: [data["response"]]
    )
  end
end
```

### Full Flow

```
1. User clicks "Start Replatforming"
   └── Rails: POST /api/workflow_runs
       └── Creates WorkflowRun record
       └── Starts Temporal Workflow via SDK
       └── Returns workflow_run_id

2. Frontend connects WebSocket
   └── ws://palad/cable?session_id=xxx
   └── Rails subscribes to Redis channel

3. Temporal Workflow starts
   └── Calls Activity: run_agent_chunk(cartographer)
   
4. Activity runs LangGraph agent
   └── Agent analyzes repo
   └── Streams tokens → Redis → Rails ActionCable → Browser
   └── Agent hits ambiguity, needs human input
   └── Activity returns {status: "needs_human_input", state: {...}}

5. Workflow receives result
   └── Calls Activity: notify_ui_needs_input(prompt, options)
   └── Enters wait_condition for signal

6. User sees prompt in UI, selects option
   └── Frontend: ActionCable.perform("respond", {response: "app/main.py"})
   └── Rails: sends Temporal signal "provide_human_response"

7. Workflow wakes up
   └── Calls Activity: run_agent_chunk with human_response
   └── Agent continues from checkpoint
   └── ... repeat until complete

8. Workflow completes
   └── Assets synced to S3
   └── Session marked complete
   └── UI shows "Step 1 complete, proceed to Step 2?"
```

---

## 🔗 Related Documents

- [Design Thinking Session](./design-thinking-2026-01-15.md) — original product context
- [Architecture Overview](../kb/product/architecture.md) — current architecture

---

_Generated during brainstorming session with Carson (BMAD Brainstorming Coach)_
