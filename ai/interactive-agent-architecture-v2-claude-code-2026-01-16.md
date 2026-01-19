# Interactive Agent Architecture v2: Claude Code + Docker

**Date:** 2026-01-16
**Author:** Artem Petrov (via Brainstorming session)
**Status:** Draft / Alternative Architecture
**Supersedes:** interactive-agent-architecture-2026-01-16.md (partially)

---

## 🎯 Key Insight

Instead of writing our own agent with tools, we use **Claude Code CLI** — a ready-made solution from Anthropic with:
- File operations (read, write, edit)
- Code search (ripgrep)
- Shell execution
- Human-in-the-loop confirmations
- Streaming in the terminal
- CLAUDE.md support for context

---

## 🏗️ Architecture: Container per Step + Claude Code

### Key principles

1. **Each step = a separate Docker container**
2. **Claude Code CLI** — the main tool inside the container
3. **CLAUDE.md** — BMAD prompts for each step
4. **xterm.js** — a real terminal in the browser, connected to the container
5. **Temporal** — only container orchestration, not agent management
6. **Artifacts** — collected from `/workspace/output/` when exiting the container

### Conceptual model

```
WORKFLOW: Replatforming
│
├── STEP 1: Cartographer
│   └── Container A
│       ├── Mounts: /repo (git clone)
│       ├── CLAUDE.md: cartographer prompt
│       ├── User runs: $ claude
│       ├── Works interactively with Claude Code
│       └── Exit → collect /workspace/output/ → S3
│
├── STEP 2: Behavior Extractor
│   └── Container B (new)
│       ├── Mounts: /repo
│       ├── Mounts: /artifacts/step-1 (readonly)
│       ├── CLAUDE.md: behavior_extractor prompt
│       └── Exit → collect artifacts → S3
│
└── ... (7 steps total)
```

---

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        BROWSER                               │
│  xterm.js ← full-fledged terminal                            │
└──────────────────────────┬──────────────────────────────────┘
                           │ WebSocket (bidirectional PTY)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         RAILS                                │
│  • Docker API: create/start/stop containers                 │
│  • WebSocket ↔ Docker attach (PTY)                          │
│  • Artifact collector: container exit → S3                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
┌─────────────────────────┐   ┌─────────────────────────────────┐
│        TEMPORAL         │   │      DOCKER CONTAINERS          │
│                         │   │                                 │
│  Orchestrates steps:    │   │  ┌─────────────────────────┐   │
│  1. Start container     │   │  │ Container (per step)    │   │
│  2. Wait for exit       │   │  │ • Claude Code CLI       │   │
│  3. Collect artifacts   │   │  │ • CLAUDE.md (BMAD)      │   │
│  4. Start next step     │   │  │ • /workspace/output/    │   │
│                         │   │  └─────────────────────────┘   │
└─────────────────────────┘   └─────────────────────────────────┘
```

---

## 🔧 Claude Code CLI

### Installation

```bash
npm install -g @anthropic-ai/claude-code
# Requires Node.js 18+
```

### Key Features (out of the box)

| Feature | Description |
|---------|-------------|
| **File tools** | Read, Write, Edit files |
| **Search** | ripgrep integration |
| **Shell** | Execution of bash commands |
| **CLAUDE.md** | Automatically reads from the project root |
| **Streaming** | Works in the terminal |
| **Confirmations** | Asks before making changes |

### CLI Flags

| Flag | Description |
|------|-------------|
| `--add-dir` | Add additional directories |
| `--system-prompt-file` | Custom system prompt |
| `--print` / `-p` | Headless mode for automation |
| `--continue` | Continue the last session |
| `--dangerously-skip-permissions` | Skip confirmations |

### Configuration: settings.json

```json
{
  "model": "claude-sonnet-4-20250514",
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(git:*)",
      "Edit(workspace/**)",
      "Write(workspace/output/**)"
    ],
    "deny": [
      "Read(.env*)",
      "Bash(rm -rf:*)"
    ],
    "defaultMode": "acceptEdits"
  }
}
```

---

## 📁 CLAUDE.md: BMAD Prompts

Claude Code automatically reads `CLAUDE.md` from the workspace root and uses it as context for all interactions.

### Step 1: Cartographer

```markdown
# CLAUDE.md - Cartographer Step

## Your Role

You are **Cartographer** — the first agent in a replatforming workflow.
Your task is to create a "Surface Area Map" of the codebase.

## Workspace Structure

- `/workspace/repo/` — The codebase to analyze (readonly)
- `/workspace/output/` — Write all artifacts here
- `/workspace/context/` — Artifacts from previous steps (if any)

## Your Task

Analyze the repository and document:

1. **Entry Points**: routes, endpoints, CLI commands
2. **Background Jobs**: cron, workers, queues
3. **Events**: pub/sub, webhooks, callbacks
4. **External Integrations**: APIs, databases, services
5. **Data Models**: entities, relationships

## Output Requirements

Create these files in `/workspace/output/`:

### system_index.md
High-level system overview:
- Tech stack
- Main components
- Key dependencies

### surface_area.md
Detailed map with:
- All endpoints with methods and paths
- All background jobs with schedules
- All external integrations
- All data models with relationships

## Evidence Rule (CRITICAL)

**Every claim MUST have evidence.**

Format: `[Evidence: path/to/file.rb:45-67]`

If no evidence found: `[UNKNOWN - needs verification]`

## Getting Started

1. Explore the codebase structure
2. Find configuration files (routes, database config)
3. Identify the framework/stack
4. Start documenting systematically

When finished, type `exit` in the terminal.
```

### Step 2: Behavior Extractor

```markdown
# CLAUDE.md - Behavior Extractor Step

## Your Role

You are **Behavior Extractor** — step 2 in replatforming.
Extract behavioral specifications from the code.

## Context from Previous Steps

Read the Surface Area Map:
- `/workspace/context/step-1/system_index.md`
- `/workspace/context/step-1/surface_area.md`

## Workspace Structure

- `/workspace/repo/` — The codebase (readonly)
- `/workspace/context/` — Previous step artifacts (readonly)
- `/workspace/output/` — Write your artifacts here

## Your Task

For each endpoint/entry point in Surface Area Map:

1. **Scenarios**: Given/When/Then format
2. **Edge Cases**: Validations, error handling
3. **Side Effects**: DB changes, external calls, files

## Output Requirements

### /workspace/output/scenarios/
One file per major flow:
- `auth_flow.md`
- `order_flow.md`
- etc.

### /workspace/output/error_catalog.md
All error cases with:
- Error code/type
- Trigger conditions
- Evidence in code

## Evidence Rule (CRITICAL)

**Every scenario MUST reference code.**

Format: `[Evidence: path/to/file.rb:45-67]`

## Getting Started

1. Read surface_area.md from context
2. Pick first endpoint
3. Trace the code flow
4. Document scenarios

When finished, type `exit` in the terminal.
```

### Additional Steps (templates)

| Step | Agent | CLAUDE.md Focus |
|------|-------|-----------------|
| 3 | Data & Invariants | DB schema, constraints, domain model |
| 4 | Integrations & Contracts | OpenAPI, events, external services |
| 5 | Permissions & Auth | Access matrix, roles, policies |
| 6 | Test Smith | Characterization tests |
| 7 | Editor/Integrator | Consolidate spec pack, check consistency |

---

## 🐳 Docker Container Setup

### Dockerfile

```dockerfile
# Dockerfile.claude-session
FROM node:20-slim

# System tools for code analysis
RUN apt-get update && apt-get install -y \
    git \
    ripgrep \
    fd-find \
    jq \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create workspace structure
RUN mkdir -p /workspace/repo /workspace/context /workspace/output

# Copy entrypoint
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# Copy BMAD prompts
COPY prompts/ /prompts/

WORKDIR /workspace
ENTRYPOINT ["/app/entrypoint.sh"]
```

### Entrypoint Script

```bash
#!/bin/bash
# entrypoint.sh

set -e

# Clone repo if URL provided
if [ -n "$REPO_URL" ]; then
    echo "📦 Cloning repository..."
    git clone --depth 1 "$REPO_URL" /workspace/repo
fi

# Create output directory
mkdir -p /workspace/output

# Setup Claude Code config
mkdir -p /workspace/.claude
cat > /workspace/.claude/settings.json << EOF
{
  "model": "${MODEL:-claude-sonnet-4-20250514}",
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(git:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Edit(/workspace/output/**)",
      "Write(/workspace/output/**)"
    ],
    "deny": [
      "Bash(rm:*)",
      "Bash(mv:*)",
      "Edit(/workspace/repo/**)",
      "Write(/workspace/repo/**)"
    ],
    "defaultMode": "acceptEdits"
  }
}
EOF

# Copy step-specific CLAUDE.md
if [ -f "/prompts/${STEP_NAME}.md" ]; then
    cp "/prompts/${STEP_NAME}.md" /workspace/CLAUDE.md
    echo "✅ Loaded BMAD prompt for: ${STEP_NAME}"
else
    echo "⚠️  No prompt found for step: ${STEP_NAME}"
fi

# Welcome message
cat << 'WELCOME'

═══════════════════════════════════════════════════════════════
  PALAD Session
═══════════════════════════════════════════════════════════════

WELCOME

echo "  Step:      ${STEP_NAME}"
echo "  Repo:      /workspace/repo"
echo "  Context:   /workspace/context"
echo "  Output:    /workspace/output"

cat << 'INSTRUCTIONS'

  Commands:
    claude     - Start AI assistant (reads CLAUDE.md)
    exit       - Finish this step (artifacts will be collected)

═══════════════════════════════════════════════════════════════

INSTRUCTIONS

# Start interactive shell
exec bash
```

---

## ⚙️ Temporal Workflow

### Simplified Orchestration

```python
# workflows.py

from datetime import timedelta
from temporalio import workflow

@workflow.defn
class ReplatformingWorkflow:

    @workflow.run
    async def run(self, input: WorkflowInput) -> WorkflowResult:
        steps = [
            StepConfig(name="cartographer", depends_on=[]),
            StepConfig(name="behavior_extractor", depends_on=["cartographer"]),
            StepConfig(name="data_invariants", depends_on=["cartographer", "behavior_extractor"]),
            StepConfig(name="integrations_contracts", depends_on=["cartographer"]),
            StepConfig(name="permissions_auth", depends_on=["cartographer"]),
            StepConfig(name="test_smith", depends_on=["behavior_extractor", "data_invariants"]),
            StepConfig(name="editor_integrator", depends_on=["*"]),  # All previous
        ]

        artifacts = {}

        for step in steps:
            # Collect artifacts from dependencies
            mounted_artifacts = [
                artifacts[dep] for dep in step.depends_on
                if dep != "*"
            ]
            if "*" in step.depends_on:
                mounted_artifacts = list(artifacts.values())

            # Run step container
            result = await workflow.execute_activity(
                run_step_container,
                args=[
                    input.session_id,
                    step.name,
                    input.repo_url,
                    mounted_artifacts,
                ],
                start_to_close_timeout=timedelta(hours=12),
                heartbeat_timeout=timedelta(minutes=5),
            )

            # Store artifacts
            artifacts[step.name] = result.artifacts

            # Sync to S3
            await workflow.execute_activity(
                sync_artifacts_to_s3,
                args=[input.session_id, step.name, result.artifacts],
                start_to_close_timeout=timedelta(minutes=10),
            )

        return WorkflowResult(
            status="completed",
            artifacts=artifacts,
        )
```

### Activity: Run Container

```python
# activities.py

import docker
from temporalio import activity

docker_client = docker.from_env()

@activity.defn
async def run_step_container(
    session_id: str,
    step_name: str,
    repo_url: str,
    mounted_artifacts: list[ArtifactSet],
) -> StepResult:

    container_name = f"palad-{session_id}-{step_name}"

    # Build volume mounts
    volumes = {
        get_output_path(session_id, step_name): {
            "bind": "/workspace/output",
            "mode": "rw"
        }
    }

    # Mount previous step artifacts as readonly
    for i, artifact_set in enumerate(mounted_artifacts, 1):
        volumes[artifact_set.local_path] = {
            "bind": f"/workspace/context/step-{i}",
            "mode": "ro"
        }

    # Create and start container
    container = docker_client.containers.run(
        image="palad-claude-session:latest",
        name=container_name,
        environment={
            "STEP_NAME": step_name,
            "REPO_URL": repo_url,
            "ANTHROPIC_API_KEY": get_api_key(),
            "MODEL": "claude-sonnet-4-20250514",
        },
        volumes=volumes,
        tty=True,
        stdin_open=True,
        detach=True,
        mem_limit="2g",
        cpu_period=100000,
        cpu_quota=100000,  # 1 CPU
    )

    # Notify Rails to attach WebSocket
    await notify_container_ready(session_id, step_name, container.id)

    # Wait for container to exit (user types 'exit')
    while True:
        activity.heartbeat({"container": container_name, "status": "running"})

        container.reload()
        if container.status == "exited":
            break

        await asyncio.sleep(5)

    # Collect artifacts from output directory
    output_path = get_output_path(session_id, step_name)
    artifacts = collect_artifacts(output_path)

    # Cleanup container
    container.remove()

    return StepResult(
        step_name=step_name,
        artifacts=artifacts,
        exit_code=container.attrs["State"]["ExitCode"],
    )
```

---

## 🌐 Rails: WebSocket ↔ Docker PTY

### Terminal Channel

```ruby
# app/channels/terminal_channel.rb

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @session_id = params[:session_id]
    @step_name = params[:step_name]

    # Get container ID from Redis (set by Temporal activity)
    container_id = Redis.current.get("palad:#{@session_id}:#{@step_name}:container")

    reject unless container_id

    # Attach to container PTY
    @container = Docker::Container.get(container_id)

    # Start reading from container in background
    @reader_thread = Thread.new do
      @container.attach(
        stream: true,
        stdout: true,
        stderr: true,
        tty: true
      ) do |stream, chunk|
        transmit({ type: "output", data: chunk })
      end
    end

    # Attach stdin
    @stdin_socket = @container.attach(
      stream: true,
      stdin: true,
      tty: true
    )
  end

  def receive(data)
    # Forward user input to container stdin
    @stdin_socket.write(data["input"]) if @stdin_socket
  end

  def unsubscribed
    @reader_thread&.kill
    @stdin_socket&.close
  end
end
```

---

## 📊 Flow Summary

```
1. User: "Start Replatforming" + repo URL
   └── Rails: Create WorkflowRun, start Temporal workflow

2. Temporal: Step 1 (Cartographer)
   └── Activity creates container with:
       • Repo cloned to /workspace/repo
       • CLAUDE.md = cartographer prompt
       • ANTHROPIC_API_KEY in env
   └── Rails notified: container ready
   └── User connects via xterm WebSocket

3. User in container:
   $ claude

   Claude Code starts, reads CLAUDE.md
   User works interactively:
   - Asks questions
   - Claude analyzes code
   - Claude creates artifacts in /workspace/output/

   $ exit

4. Container exits
   └── Temporal activity collects /workspace/output/
   └── Artifacts synced to S3
   └── Temporal starts Step 2

5. Temporal: Step 2 (Behavior Extractor)
   └── New container with:
       • Same repo
       • Step 1 artifacts mounted at /workspace/context/step-1/
       • CLAUDE.md = behavior_extractor prompt
   └── User connects, runs claude, works...

6. Repeat for all 7 steps

7. Workflow completes
   └── Full Spec Pack in S3
   └── Ready for replatforming
```

---

## ⚖️ License & Commercial Use

### Claude Code CLI License

- **Not open source** — proprietary Anthropic software
- License: "© Anthropic PBC. All rights reserved. Use subject to Anthropic's Commercial Terms of Service."

### Commercial Use

| Plan | Terms | Commercial Use | Indemnification |
|------|-------|----------------|-----------------|
| Free, Pro, Max | Consumer Terms | Limited | No |
| **API / Team / Enterprise** | **Commercial Terms** | **Yes** | **Yes** |

**Recommendation:** For commercial use, Palad needs an Anthropic API/Team/Enterprise plan.

### Key Restrictions

1. **No competing AI** — cannot be used to create a competing AI model
2. **Training data** — Consumer plans may use data for training (opt-out available)
3. **API key** — each user must use their own key, or the company must have a Team/Enterprise plan

---

## ✅ Benefits vs Previous Architecture

| Aspect | v1 (Custom Agent) | v2 (Claude Code) |
|--------|-------------------|------------------|
| **Agent code** | Custom LangGraph | Zero — use Claude Code |
| **File tools** | Implement ourselves | Built-in |
| **Search** | Implement ourselves | Built-in ripgrep |
| **Checkpointing** | PostgreSQL | Not needed — container is state |
| **Streaming** | Redis pubsub | Direct PTY |
| **Human interaction** | Custom signals | Native Claude Code |
| **Maintenance** | Our responsibility | Anthropic maintains |

---

## 🚀 Implementation Roadmap

### Phase 1: Proof of Concept
- [ ] Docker image with Claude Code CLI
- [ ] Single step (Cartographer) works
- [ ] xterm.js connects to container
- [ ] CLAUDE.md prompt loaded correctly
- [ ] Artifacts collected on exit

### Phase 2: Multi-step Workflow
- [ ] Temporal orchestration of steps
- [ ] Artifact mounting between steps
- [ ] All 7 BMAD prompts created
- [ ] S3 sync working

### Phase 3: Production Ready
- [ ] Team/Enterprise Anthropic plan
- [ ] API key management
- [ ] Container resource limits
- [ ] Monitoring and logging
- [ ] UI for workflow management

---

## 🤔 Open Questions

1. **API Key management** — how to securely pass the key into the container?
   - User's own key?
   - Company Team/Enterprise key?
   - Vault/secrets manager?

2. **Model selection** — does the user choose the model, or is it fixed?

3. **Session persistence** — what if the user closed the browser? Does the container keep running?

4. **Cost tracking** — how to track API spend per user/project?

---

## 🔗 Related Documents

- [Interactive Agent Architecture v1](./interactive-agent-architecture-2026-01-16.md) — previous version with a custom agent
- [Design Thinking Session](./design-thinking-2026-01-15.md) — original product context

---

## 📚 References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Claude Code CLI Reference](https://docs.anthropic.com/en/docs/claude-code/cli-reference)
- [Claude Code Settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- [Anthropic Commercial Terms](https://www.anthropic.com/legal/commercial-terms)

---

_Generated during brainstorming session, 2026-01-16_
