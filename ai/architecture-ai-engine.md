# Architecture - AI Engine Part

**Generated**: 2026-01-20
**Part**: ai-engine
**Type**: Backend (AI/ML)
**Status**: 🔄 Legacy (migrated from previous product)

---

## Overview

> ⚠️ **Note**: AI Engine is currently a copy from the previous product (Palad AI). This code will be refactored or replaced as the new Palad architecture evolves. The documentation below describes the existing structure for reference.

The AI Engine is a Python component for AI analysis, document processing, and specification generation. It runs as a Temporal worker, executing activities for analyzing code, documents, and images.

---

## Technology Stack

| Category | Technology | Version | Notes |
|----------|------------|---------|-------|
| **Language** | Python | 3.13 | Latest |
| **Orchestration** | Temporal SDK | 1.7.0+ | Workers |
| **AI Framework** | LangGraph | 1.0.x | Agent orchestration |
| **LLM** | LangChain | 1.0.x | LLM integration |
| **Structured Output** | Instructor | 1.7.0 | LLM → Pydantic |
| **Vector DB** | Qdrant | - | Semantic search |
| **ORM** | SQLAlchemy | 2.0.44 | Database access |
| **Validation** | Pydantic | 2.12.3 | Data validation |
| **Config** | Dynaconf | 3.2.11 | Environment config |
| **Telemetry** | Langfuse | 3.2.1 | LLM observability |
| **Package Manager** | uv | - | Fast Python packages |

---

## Architecture Pattern

**Service-Oriented** with Temporal activities and workflows.

```
┌─────────────────────────────────────────────────────────┐
│                  Temporal Server                         │
│                  (Task Queue: palad_python)              │
└─────────────────────────┬───────────────────────────────┘
                          │ gRPC
┌─────────────────────────▼───────────────────────────────┐
│                  Python Worker                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │               Activities                         │    │
│  │  • codebase_analyze_file                        │    │
│  │  • document_analyze_file                        │    │
│  │  • image_analyze_file                           │    │
│  │  • generate_domains/features/stories            │    │
│  │  • *_index_in_vector_db                         │    │
│  └─────────────────────────────────────────────────┘    │
│                          │                               │
│  ┌───────────────────────▼─────────────────────────┐    │
│  │                 Services                         │    │
│  │  AI Agents → LLM Factory → Vector Engine        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │  Qdrant  │        │ LLM APIs │        │PostgreSQL│
    │ (Vector) │        │(OpenAI,..)│       │ (via Ruby)│
    └──────────┘        └──────────┘        └──────────┘
```

---

## Directory Structure

```
ai-engine/
├── app/
│   ├── agents/                    # AI Agents
│   │   ├── __init__.py
│   │   └── common/
│   │       ├── base/              # BaseAgent[T]
│   │       ├── base_langgraph_agent/
│   │       ├── base_openrouter_agent/
│   │       ├── batch_text_agent/
│   │       ├── mixture_of_experts_agent/
│   │       ├── one_shot_text_agent/
│   │       ├── rag/               # TaskRAGAgent
│   │       └── self_refinement_vision_agent/
│   ├── config/
│   │   ├── settings.py            # Dynaconf loader
│   │   └── settings.yml           # Configuration
│   ├── constants/                 # Workflow constants
│   ├── core/
│   │   ├── database.py            # SQLAlchemy
│   │   └── logging.py             # Loguru
│   ├── llm/
│   │   └── llm_factory.py         # LLM provider factory
│   ├── models/                    # Pydantic models
│   │   ├── common.py
│   │   ├── db.py
│   │   ├── llm.py
│   │   └── telemetry.py
│   ├── services/                  # Business services
│   ├── temporal/
│   │   ├── activities/            # Temporal activities
│   │   │   ├── codebase.py
│   │   │   ├── document.py
│   │   │   ├── image.py
│   │   │   ├── models.py
│   │   │   └── specification.py
│   │   ├── workflows/             # Temporal workflows
│   │   │   ├── asset_codebase.py
│   │   │   ├── asset_document.py
│   │   │   ├── asset_image.py
│   │   │   └── specification_processing.py
│   │   └── worker.py              # Entry point
│   ├── utils/                     # Utilities
│   └── vector_engine/             # Qdrant integration
│       ├── core/                  # Client, config
│       ├── embeddings/            # Embedding service
│       ├── indexing/              # Indexing strategies
│       └── search/                # Search service
├── tests/                         # Pytest tests
├── Dockerfile
├── pyproject.toml                 # Dependencies (uv)
└── Makefile
```

---

## AI Agents

### Agent Hierarchy

```
BaseAgent[T]
├── BaseLangGraphAgent      # LangGraph workflows
├── BaseOpenRouterAgent     # Multi-model routing
├── BatchTextAgent          # Batch text processing
├── MixtureOfExpertsAgent   # Ensemble approach
├── OneShotTextAgent        # Single-shot generation
├── SelfRefinementVisionAgent  # Iterative image analysis
└── TaskRAGAgent            # Retrieval-augmented generation
```

### BaseAgent Features

- Generic type `T` for structured output
- Telemetry context (Langfuse)
- Prompt loading
- LangChain config builder
- Image handling (base64)

---

## Temporal Activities

| Activity | Description |
|----------|-------------|
| `codebase_analyze_file` | Analyze source code file |
| `codebase_index_file_in_vector_db` | Index code in Qdrant |
| `codebase_generate_report_section` | Generate code report |
| `document_analyze_file` | Analyze PDF/Word document |
| `document_index_in_vector_db` | Index document |
| `image_analyze_file` | Analyze image (vision) |
| `image_index_in_vector_db` | Index image |
| `generate_domains` | Generate domain analysis |
| `generate_features` | Generate features |
| `generate_user_stories` | Generate user stories |
| `generate_use_cases` | Generate use cases |
| `generate_erd_diagram` | Generate ERD |
| `generate_dataflow_diagram` | Generate dataflow |
| `model_list_get` | List available LLM models |

---

## Temporal Workflows

| Workflow | Owner | Description |
|----------|-------|-------------|
| `AssetCodebaseWorkflow` | palad_python | Process codebase assets |
| `AssetDocumentWorkflow` | palad_python | Process documents |
| `AssetImageWorkflow` | palad_python | Process single images |
| `AssetImageCollectionWorkflow` | palad_python | Process image collections |
| `SpecificationProcessingWorkflow` | palad_python | Generate specifications |

---

## Vector Engine (Qdrant)

### Architecture

```
VectorEngine
├── core/
│   ├── client.py          # Qdrant client
│   ├── config.py          # Collection config
│   └── models.py          # Data models
├── embeddings/
│   └── service.py         # Embedding generation
├── indexing/
│   ├── service.py         # Indexing service
│   └── strategies/        # Chunking strategies
└── search/
    ├── service.py         # Search service
    └── configs/           # Search configurations
```

### Capabilities

- Document chunking (multiple strategies)
- Embedding generation (OpenAI)
- Semantic search
- Hybrid search (dense + sparse)

---

## LLM Integration

### Supported Providers

| Provider | Models | Use Case |
|----------|--------|----------|
| **OpenRouter** | Multiple | Primary routing |
| **Anthropic** | Claude | High-quality analysis |
| **OpenAI** | GPT-4, Embeddings | General, embeddings |

### LLM Factory

```python
from llm.llm_factory import LLMFactory

llm = LLMFactory.create(
    provider="openrouter",
    model="anthropic/claude-3-opus",
    temperature=0.7
)
```

---

## Configuration

### Environment Variables

```bash
# LLM APIs
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=sk-or-...

# Database
DB_HOST=db
DB_PORT=5432
DB_NAME=palad_development

# Qdrant
QDRANT_URL=http://qdrant:6333

# Temporal
TEMPORAL_HOST=temporal
TEMPORAL_PORT=7233
TEMPORAL_TASK_QUEUE_PYTHON=palad_python

# Telemetry
LANGFUSE_ENABLED=true
LANGFUSE_PUBLIC_KEY=...
LANGFUSE_SECRET_KEY=...
```

### settings.yml

```yaml
temporal:
  task_queues:
    python: palad_python
    ruby: palad_ruby
  max_workers: 30

concurrency:
  mixture_of_experts: 3
  file_analysis: 2
  embedding_generation: 7
```

---

## Development

```bash
# Enter container
docker-compose run --rm worker-python bash

# Install dependencies
make deps

# Generate workflow constants
make workflows

# Linting
make lint
make format

# Testing
make test

# All checks
make check
```

---

## Entry Point

```bash
# Start worker
python app/temporal/worker.py
```

Worker registers:
- 14 activities
- 5 workflows
- Listens on `palad_python` task queue

---

## Important Notes

1. **Legacy Code** — this is a copy from previous product, expect refactoring
2. **No direct DB writes** — all DB operations go through Ruby activities
3. **Structured output** — use Pydantic + Instructor
4. **Telemetry** — all LLM calls are logged to Langfuse
5. **Error handling** — fail-fast, specific exceptions

---

## Future Plans

The AI Engine will likely be:
- Simplified to focus on Palad-specific workflows
- Integrated more tightly with BMAD Method agents
- Potentially replaced with different agent architecture (Claude Code, OpenCode)
