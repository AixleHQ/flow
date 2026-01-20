# Integration Architecture

**Generated**: 2026-01-20
**Project**: Palad
**Type**: Multi-Part Monorepo

---

## Overview

Palad uses **Temporal** to orchestrate workflows between Ruby and Python components. This allows it to:

- Separate responsibilities: Ruby for DB/storage, Python for AI
- Provide durability and retry for long-running operations
- Scale workers independently

---

## Integration Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              BROWSER                                     │
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │   HomePage   │    │ SessionPage  │    │  FileTree + FileViewer   │   │
│  └──────┬───────┘    └──────┬───────┘    └────────────┬─────────────┘   │
│         │                   │                         │                  │
│         │ HTTP              │ HTTP + iframe           │ WebSocket        │
└─────────┼───────────────────┼─────────────────────────┼──────────────────┘
          │                   │                         │
          ▼                   ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         WEB PART (Rails :4000)                           │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │    REST API      │  │ ContainerManager │  │   TemporalService      │ │
│  │ terminal_sessions│  │   Docker API     │  │   Workflow client      │ │
│  └──────────────────┘  └──────────────────┘  └────────────────────────┘ │
│                                                         │                │
│  ┌──────────────────────────────────────────────────────▼──────────────┐ │
│  │              Ruby Temporal Worker (palad_ruby)                       │ │
│  │  • DB operations (read/write)                                        │ │
│  │  • File loading from S3                                              │ │
│  │  • Saving analysis results                                           │ │
│  │  • Integration activities (Jira, Confluence)                         │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
          │                                          │
          │ Temporal (gRPC)                          │ Docker API
          ▼                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         TEMPORAL SERVER (:7233)                          │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                      Workflow Execution                              ││
│  │                                                                      ││
│  │  ┌─────────────┐    Activity Calls    ┌─────────────┐               ││
│  │  │ palad_ruby  │◄────────────────────►│palad_python │               ││
│  │  │ Task Queue  │                      │ Task Queue  │               ││
│  │  └─────────────┘                      └─────────────┘               ││
│  └─────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
          │
          │ Temporal (gRPC)
          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                 AI ENGINE PART (Python) [LEGACY]                         │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │              Python Temporal Worker (palad_python)                    ││
│  │  • AI analysis (codebase, documents, images)                         ││
│  │  • LLM calls (OpenRouter, Anthropic, OpenAI)                         ││
│  │  • Vector indexing (Qdrant)                                          ││
│  │  ⚠️ Legacy code from previous product - will be refactored           ││
│  └──────────────────────────────────────────────────────────────────────┘│
│                              │                                           │
│  ┌───────────────┐  ┌───────▼───────┐  ┌───────────────────────────────┐│
│  │  AI Agents    │  │  LLM Factory  │  │    Vector Engine (Qdrant)     ││
│  │  (LangGraph)  │  │  (OpenRouter) │  │    Embeddings + Search        ││
│  └───────────────┘  └───────────────┘  └───────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      CLAUDE CODE CONTAINER                               │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │  ttyd (:7681)    │  │ File Watcher     │  │   Claude Code CLI      │ │
│  │  Web Terminal    │  │ (:4040) WS+HTTP  │  │   + bash shell         │ │
│  └──────────────────┘  └──────────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Integration Points

| From | To | Protocol | Purpose |
|------|-----|----------|---------|
| Browser | Rails | HTTP/REST | API calls |
| Browser | Claude Container | HTTP (iframe) | Terminal access |
| Browser | Claude Container | WebSocket | File tree sync |
| Rails | Temporal | gRPC | Workflow execution |
| Rails | Docker | Unix socket | Container management |
| Rails | PostgreSQL | TCP | Data persistence |
| Rails | Redis | TCP | State caching |
| Python Worker | Temporal | gRPC | Activity execution |
| Python Worker | Qdrant | HTTP | Vector operations |
| Python Worker | LLM APIs | HTTPS | AI inference |
| Ruby Worker | Python Worker | Temporal | Cross-queue activities |

---

## Temporal Task Queues

| Queue | Language | Responsibilities |
|-------|----------|------------------|
| `palad_ruby` | Ruby | DB operations, file I/O, integrations |
| `palad_python` | Python | AI analysis, LLM calls, vector indexing |

---

## Cross-Language Workflow Patterns

### Pattern 1: Python-Owned with Ruby Activities

```yaml
workflow: asset_codebase_processing
owner: palad_python

flow:
  1. codebase_extract_and_prepare     → palad_ruby   # DB + file extraction
  2. codebase_load_file_content       → palad_ruby   # Read from S3
  3. codebase_analyze_file            → palad_python # AI analysis
  4. codebase_save_file_analysis      → palad_ruby   # Save to DB
  5. codebase_index_file_in_vector_db → palad_python # Qdrant indexing
  6. codebase_generate_report_section → palad_python # LLM generation
  7. codebase_save_report_section     → palad_ruby   # Save to DB
  8. shared_finalize_asset            → palad_ruby   # Mark complete
```

### Pattern 2: Ruby-Owned Simple Workflow

```yaml
workflow: sync_model_list
owner: palad_ruby

flow:
  1. model_list_get  → palad_python  # Get models from LLM APIs
  2. model_list_save → palad_ruby    # Save to DB
```

### Pattern 3: Specification Generation

```yaml
workflow: specification_processing
owner: palad_python

flow:
  # Domains
  1. specification_prepare_domain_context → palad_ruby
  2. generate_domains                     → palad_python
  3. specification_save_domains           → palad_ruby

  # Features
  4. specification_prepare_feature_context → palad_ruby
  5. generate_features                     → palad_python
  6. specification_save_features           → palad_ruby

  # User Stories
  7. specification_prepare_user_story_context → palad_ruby
  8. generate_user_stories                    → palad_python
  9. specification_save_user_stories          → palad_ruby

  # ... continues for use_cases, diagrams
```

---

## Shared Resources

| Resource | Used By | Purpose |
|----------|---------|---------|
| **PostgreSQL** | Web, AI Engine (via Ruby) | Primary data store |
| **Redis** | Web | Container state, caching |
| **Qdrant** | AI Engine | Vector embeddings |
| **S3** | Web, AI Engine | File storage |
| **Temporal** | Web, AI Engine | Workflow orchestration |

---

## Data Flow Examples

### 1. Interactive Terminal Session

```
Browser                Rails                   Docker
   │                     │                       │
   │ POST /terminal_sessions                     │
   │────────────────────►│                       │
   │                     │ create_session()      │
   │                     │──────────────────────►│
   │                     │◄──────────────────────│
   │ { ttyd_port, watcher_port }                 │
   │◄────────────────────│                       │
   │                     │                       │
   │ iframe src=localhost:ttyd_port              │
   │─────────────────────────────────────────────►
   │                     │                       │
   │ WebSocket ws://localhost:watcher_port       │
   │─────────────────────────────────────────────►
```

### 2. Codebase Analysis

```
Rails                Temporal               Python Worker
  │                     │                       │
  │ start_workflow()    │                       │
  │────────────────────►│                       │
  │                     │ extract_and_prepare   │
  │◄────────────────────│ (palad_ruby)          │
  │ [files list]        │                       │
  │────────────────────►│                       │
  │                     │ analyze_file          │
  │                     │──────────────────────►│
  │                     │◄──────────────────────│
  │                     │ save_analysis         │
  │◄────────────────────│ (palad_ruby)          │
  │                     │                       │
  │                     │ index_in_vector_db    │
  │                     │──────────────────────►│
  │                     │◄──────────────────────│
```

---

## Authentication & Security

### Internal Network

- Temporal: No auth (internal network only)
- Docker API: Unix socket (local only)
- PostgreSQL: Trust auth (Docker network)
- Redis: No auth (Docker network)
- Qdrant: No auth (Docker network)

### External APIs

- LLM APIs: API keys via environment variables
- Google OAuth: OmniAuth configuration
- S3: AWS credentials via environment/IAM

---

## Error Handling

### Temporal Retries

```ruby
# Ruby activity with retry config
class Activities::Base
  def execute(input)
    # Wrapped with retry logic
    run(input)
  rescue ActiveRecord::RecordNotFound => e
    raise TemporalExceptions.wrap(e, retryable: false)
  end
end
```

### Python Activity Errors

```python
# Python activity with structured errors
@activity.defn
async def analyze_file(input: AnalyzeInput) -> AnalyzeOutput:
    try:
        return await do_analysis(input)
    except LLMError as e:
        raise ApplicationError(str(e), non_retryable=True)
```

---

## Monitoring

| Component | Tool | Access |
|-----------|------|--------|
| Temporal | Temporal UI | http://localhost:8080 |
| LLM Calls | Langfuse | https://lf.palad.com |
| Rails Logs | Lograge | stdout/Rollbar |
| Python Logs | Loguru | stdout |
