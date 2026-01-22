# Brainstorm: Palad Platform

**Date:** 2026-01-20
**Topic:** Architecture of a cloud AI-agent platform with a workflow system
**Techniques:** First Principles → Morphological Analysis → Six Thinking Hats → Constraint Mapping → Cross-Pollination

---

## 🎯 Product vision

Palad — a platform for running cloud AI agents (Claude Code, Cursor CLI, Codex, Gemini CLI) with:
- **Workflow Engine** — step-by-step task execution (BMAD-style)
- **Multi-tenancy** — companies, users, data isolation
- **Billing & Analytics** — accurate accounting of tokens and cost
- **Extensible Tools** — any code in Docker + secrets

---

## ✅ Architectural decisions

### Locked-in decisions

| Area | Decision | Rationale |
|---------|---------|-------------|
| **Agent isolation** | Docker containers | Already works, mount assets, agents work with the FS |
| **Orchestration** | Temporal | Complex lifecycle: prepare → session → cleanup → billing |
| **Billing Data** | MITM Proxy (mitmproxy) + Sidecar | Universal for all CLI agents |
| **Storage** | Full DB (PostgreSQL) | Single source of truth, UI editing |
| **Tools** | Agent calls MCP → Temporal Activity (sync) | Natural UX + reliability |
| **Prompts** | Build-time templates | Predictable, debuggable |
| **Artifacts** | S3 + DB metadata | Large files in S3, metadata in DB |
| **Secrets** | Hierarchy: Platform → Company → Workflow | Flexibility + security |

---

## 🏗️ Architecture

### Session Lifecycle (Temporal Workflow)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. PREPARE                                                  │
│    ├─ Download from GitHub (legacy repos)                   │
│    ├─ Download from S3 (previous step artifacts)            │
│    ├─ Mount volumes in Docker                               │
│    └─ Health check → Signal frontend "ready"                │
├─────────────────────────────────────────────────────────────┤
│ 2. SESSION (interactive)                                    │
│    ├─ ttyd + watcher + agent                                │
│    └─ + mitmproxy (billing interceptor)                     │
│    └─ + Tool Sidecar (MCP Server)                           │
├─────────────────────────────────────────────────────────────┤
│ 3. CLEANUP                                                  │
│    ├─ Copy outputs from container                           │
│    ├─ Create Artifact entities in DB                        │
│    ├─ Upload to S3                                          │
│    ├─ Parse logs → extract billing data                     │
│    └─ Create billing records (tokens, cost, user)           │
└─────────────────────────────────────────────────────────────┘
```

### Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Docker Container                                            │
│                                                             │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐ │
│  │CLI Agent  │  │ mitmproxy │  │Tool       │  │ Watcher  │ │
│  │(Claude/   │─▶│ (billing) │  │Sidecar    │  │ (files)  │ │
│  │Codex/etc) │  │           │  │(MCP+HTTP) │  │          │ │
│  └───────────┘  └───────────┘  └───────────┘  └──────────┘ │
│       │              │               │              │       │
│       └──────────────┴───────────────┴──────────────┘       │
│                    /workspace (mounted)                     │
└─────────────────────────────────────────────────────────────┘
```

### Platform Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              PALAD PLATFORM                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐               │
│  │   Web UI    │     │  Rails API  │     │  Temporal   │               │
│  │   (React)   │────▶│             │────▶│  (Ruby +    │               │
│  │             │     │             │     │   Python)   │               │
│  └─────────────┘     └─────────────┘     └──────┬──────┘               │
│                                                  │                      │
│  ┌──────────────────────────────────────────────┼──────────────────┐   │
│  │                    PostgreSQL                 │                  │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───┴────┐ ┌─────────┐ │   │
│  │  │Companies │ │Workflows │ │  Steps   │ │Runs    │ │Usage    │ │   │
│  │  │Users     │ │Templates │ │  Tools   │ │Artifacts│ │Events   │ │   │
│  │  │Secrets   │ │Prompts   │ │          │ │        │ │Billing  │ │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────┘ └─────────┘ │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────┐                                                        │
│  │     S3      │  Artifacts, large files                               │
│  └─────────────┘                                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 💾 Data Model

### Core Entities

```sql
-- Multi-tenancy
companies (id, name, plan, settings)
users (id, company_id, email, role)

-- Secrets hierarchy
secrets (id, scope_type, scope_id, name, encrypted_value)
-- scope_type: 'platform' | 'company' | 'workflow'

-- Workflow definitions
workflows (id, company_id, name, description, status, version)
-- status: 'draft' | 'published' | 'archived'

workflow_steps (
  id, workflow_id, order, name, description,
  agent_type,           -- 'claude_code' | 'codex' | 'gemini_cli' | 'cursor'
  prompt_template,      -- TEXT with {{variables}}
  tools,                -- JSONB array of tool references
  input_schema,         -- JSONB
  output_schema,        -- JSONB
  timeout_seconds,
  requires_approval     -- boolean for human-in-the-loop
)

-- Tool definitions
tools (
  id, company_id, name, description,
  type,                 -- 'docker' | 'http' | 'ruby_service'
  image_or_endpoint,
  secrets_required,     -- JSONB array
  input_schema,
  output_schema
)

-- Execution tracking
workflow_runs (
  id, workflow_id, user_id,
  status,               -- 'pending' | 'running' | 'paused' | 'completed' | 'failed'
  started_at, completed_at,
  total_cost, total_tokens_in, total_tokens_out
)

step_runs (
  id, workflow_run_id, step_id,
  status, started_at, completed_at,
  input_artifacts,      -- JSONB array of artifact IDs
  output_artifacts,     -- JSONB array of artifact IDs
  cost, tokens_in, tokens_out,
  session_id            -- FK to container session
)

-- Artifacts
artifacts (
  id, step_run_id, name, type,
  s3_key, size_bytes, content_type,
  metadata              -- JSONB
)

-- Billing
usage_events (
  id, company_id, user_id, workflow_run_id, step_run_id,
  tokens_input, tokens_output,
  model, provider,
  cost_usd,
  created_at
)

-- Prompt versioning
prompt_versions (
  id, step_id, version,
  content, created_by, created_at, change_reason
)
```

---

## 🔧 MITM Proxy for Billing

### Dockerfile addition

```dockerfile
# In the agent container
ENV HTTP_PROXY=http://localhost:8080
ENV HTTPS_PROXY=http://localhost:8080

# mitmproxy with a custom script
RUN pip install mitmproxy
COPY billing_interceptor.py /app/
```

### billing_interceptor.py

```python
from mitmproxy import http
import json
import time

PROVIDERS = {
    "api.anthropic.com": "anthropic",
    "api.openai.com": "openai",
    "openrouter.ai": "openrouter"
}

def response(flow: http.HTTPFlow):
    for domain, provider in PROVIDERS.items():
        if domain in flow.request.host:
            try:
                data = json.loads(flow.response.content)
                usage = data.get("usage", {})

                event = {
                    "timestamp": time.time(),
                    "provider": provider,
                    "model": data.get("model"),
                    "input_tokens": usage.get("input_tokens") or usage.get("prompt_tokens"),
                    "output_tokens": usage.get("output_tokens") or usage.get("completion_tokens"),
                }

                with open("/var/log/llm/usage.jsonl", "a") as f:
                    f.write(json.dumps(event) + "\n")
            except:
                pass
```

---

## 🔧 Tool Sidecar (MCP Server)

### Concept

The Agent calls a tool via the MCP protocol → Tool Sidecar → Temporal Activity (sync) → Result

### tool_sidecar.py (example)

```python
from mcp import Server
from temporalio.client import Client

server = Server("tool-sidecar")
temporal_client = None

@server.tool("transcribe_audio")
async def transcribe_audio(audio_url: str, language: str = "auto") -> dict:
    """Transcribe audio file to text"""
    # Synchronous Temporal Activity call
    result = await temporal_client.execute_workflow(
        "ToolExecutionWorkflow",
        args=["transcribe_audio", {"audio_url": audio_url, "language": language}],
        task_queue="tools",
    )
    return result

@server.tool("read_slack_channel")
async def read_slack_channel(channel: str, days: int = 7) -> dict:
    """Read messages from Slack channel"""
    result = await temporal_client.execute_workflow(
        "ToolExecutionWorkflow",
        args=["read_slack_channel", {"channel": channel, "days": days}],
        task_queue="tools",
    )
    return result
```

---

## 🎯 Open Questions (for PoC)

| # | Question | Options | How to verify |
|---|--------|----------|---------------|
| 1 | Tool Sidecar architecture | A) Temporal Worker + Local Activity<br>B) HTTP Server + sync workflow call | Build both, measure latency |
| 2 | MITM with different agents | Claude Code, Codex, Gemini CLI | Run each one through mitmproxy |
| 3 | Latency overhead from proxy | Acceptable / not | Benchmark with and without proxy |
| 4 | Certificate trust | Add CA / env var / agent config | Test each agent |

---

## 💡 Ideas from Cross-Pollination

### High Priority

| Idea | Source | Description |
|------|----------|----------|
| **Human-in-the-loop** | LangGraph | Pause step, wait for approval, continue |
| **Secrets hierarchy** | GitHub Actions | Platform → Company → Workflow secrets |
| **Usage metering** | Stripe | Async usage events, aggregation, invoices |

### Medium Priority

| Idea | Source | Description |
|------|----------|----------|
| **Webhook triggers** | n8n/Zapier | Trigger a workflow on an event (GitHub push, Slack) |
| **Reusable templates** | GitHub Actions | Workflow templates for reuse |
| **Resource limits** | Vercel | CPU/Memory/Duration per tier |
| **Temporal Visibility** | Temporal | Query workflow state for the dashboard |

### Future

| Idea | Source | Description |
|------|----------|----------|
| **Parallel steps** | GitHub Actions Matrix | Run several steps in parallel |
| **Checkpointing** | LangGraph | Save/restore mid-workflow |
| **Streaming output** | Vercel | Real-time progress in the UI |

---

## 🚀 Implementation Phases

### Phase 1: PoC (1-2 weeks)
- [ ] Verify MITM with Claude Code
- [ ] Verify MITM with Codex
- [ ] Verify MITM with Gemini CLI
- [ ] Basic DB schema for workflows
- [ ] One simple tool via Temporal

### Phase 2: MVP (2-4 weeks)
- [ ] Full workflow execution (prepare → session → cleanup)
- [ ] Billing aggregation + basic dashboard
- [ ] Basic UI for workflows (CRUD)
- [ ] 3-5 built-in tools

### Phase 3: Polish (ongoing)
- [ ] Human-in-the-loop (pause/approve)
- [ ] Webhook triggers
- [ ] Tool marketplace
- [ ] Analytics dashboard
- [ ] Multi-tenancy (companies)

---

## 📊 Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| MITM does not work with agent X | Medium | High | Fallback: wrapper/logs parsing |
| Tool latency > 5s | Low | Medium | Local Activities, caching |
| DB without prompt versioning | High | Medium | prompt_versions table + audit log |
| Debugging complexity | High | Medium | Structured logging, Temporal UI |

---

## 📎 References

- [Temporal Documentation](https://docs.temporal.io/)
- [mitmproxy Documentation](https://docs.mitmproxy.org/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [BMAD Method](../_bmad/)
