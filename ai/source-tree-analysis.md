# Source Tree Analysis

**Generated**: 2026-01-20
**Project**: Palad
**Type**: Multi-Part Monorepo

---

## Complete Directory Structure

```
palad-app/
│
├── 📁 _bmad/                          # BMAD Method configuration
│   ├── _config/                       # Agent manifests and configs
│   │   ├── agent-manifest.csv
│   │   ├── agents/                    # Agent YAML definitions
│   │   ├── manifest.yaml
│   │   └── workflow-manifest.csv
│   ├── _memory/                       # Agent memory storage
│   │   └── config.yaml
│   ├── bmb/                           # BMAD Build module
│   │   ├── agents/
│   │   ├── config.yaml
│   │   └── workflows/
│   ├── bmm/                           # BMAD Method module
│   │   ├── agents/                    # Analyst, Architect, etc.
│   │   ├── config.yaml
│   │   ├── data/
│   │   └── workflows/                 # document-project, prd, etc.
│   ├── cis/                           # Creative Intelligence module
│   │   ├── agents/
│   │   └── workflows/
│   └── core/                          # Core resources
│       ├── agents/
│       ├── resources/
│       ├── tasks/                     # workflow.xml, etc.
│       └── workflows/
│
├── 📁 _bmad-output/                   # Generated artifacts
│   ├── implementation-artifacts/
│   └── planning-artifacts/
│       └── bmm-workflow-status.yaml   # Workflow progress tracking
│
├── 📁 ai/                             # AI documentation & tools
│   ├── BMAD-METHOD/                   # Full BMAD repository
│   │   ├── docs/
│   │   ├── src/
│   │   ├── samples/
│   │   └── tools/
│   ├── design-thinking-2026-01-15.md
│   └── tech-design-xterm-docker-claude-code.md
│
├── 📁 ai-engine/                      # 🐍 PYTHON AI ENGINE
│   ├── app/
│   │   ├── agents/                    # AI Agents
│   │   │   ├── __init__.py
│   │   │   └── common/
│   │   │       ├── base/              # BaseAgent[T]
│   │   │       │   ├── agent.py       # 🎯 Base agent class
│   │   │       │   └── configuration.py
│   │   │       ├── base_langgraph_agent/
│   │   │       ├── base_openrouter_agent/
│   │   │       ├── batch_text_agent/
│   │   │       ├── mixture_of_experts_agent/
│   │   │       ├── one_shot_text_agent/
│   │   │       ├── rag/               # RAG agent
│   │   │       │   ├── task_rag_agent.py
│   │   │       │   └── tools.py
│   │   │       └── self_refinement_vision_agent/
│   │   ├── config/
│   │   │   ├── settings.py            # Dynaconf loader
│   │   │   └── settings.yml           # 🎯 Configuration
│   │   ├── constants/
│   │   ├── core/
│   │   │   ├── database.py
│   │   │   └── logging.py
│   │   ├── llm/
│   │   │   └── llm_factory.py         # 🎯 LLM provider factory
│   │   ├── models/
│   │   │   ├── common.py
│   │   │   ├── db.py
│   │   │   ├── llm.py
│   │   │   └── telemetry.py
│   │   ├── services/
│   │   ├── temporal/
│   │   │   ├── activities/            # 🎯 Temporal activities
│   │   │   │   ├── __init__.py
│   │   │   │   ├── codebase.py
│   │   │   │   ├── document.py
│   │   │   │   ├── image.py
│   │   │   │   ├── models.py
│   │   │   │   └── specification.py
│   │   │   ├── workflows/             # 🎯 Temporal workflows
│   │   │   │   ├── asset_codebase.py
│   │   │   │   ├── asset_document.py
│   │   │   │   ├── asset_image.py
│   │   │   │   ├── asset_image_collection.py
│   │   │   │   ├── base.py
│   │   │   │   └── specification_processing.py
│   │   │   └── worker.py              # 🚀 ENTRY POINT
│   │   ├── utils/
│   │   └── vector_engine/             # Qdrant integration
│   │       ├── core/
│   │       │   ├── client.py
│   │       │   └── config.py
│   │       ├── embeddings/
│   │       ├── indexing/
│   │       │   └── strategies/
│   │       └── search/
│   ├── tests/
│   ├── Dockerfile
│   ├── Makefile
│   └── pyproject.toml                 # 🎯 Dependencies
│
├── 📁 config/                         # Shared configuration
│   └── workflows.yml                  # 🎯 Workflow definitions
│
├── 📁 docker/                         # 🐳 INFRASTRUCTURE
│   ├── claude-code/                   # Claude Code container
│   │   ├── config/
│   │   │   └── managed-settings.json
│   │   ├── prompts/
│   │   │   ├── CLAUDE.md
│   │   │   └── system-prompt.md
│   │   ├── watcher/                   # File watcher (Node.js)
│   │   │   ├── index.js
│   │   │   └── package.json
│   │   ├── Dockerfile                 # 🎯 Container definition
│   │   └── entrypoint.sh              # 🚀 Startup script
│   └── remote/                        # Remote deployment
│       ├── Dockerfile
│       └── Makefile
│
├── 📁 kb/                             # 📚 KNOWLEDGE BASE
│   ├── CLAUDE.md                      # 🎯 Claude Code rules
│   ├── README.md
│   ├── operations/
│   │   └── team-coordination/
│   │       ├── README.md
│   │       ├── tracking/
│   │       │   └── weekly-plan.md     # 🎯 Current tasks
│   │       ├── transcripts/
│   │       └── telegram-logs/
│   ├── product/
│   │   ├── README.md
│   │   ├── architecture.md            # 🎯 Architecture doc
│   │   └── vision.md                  # 🎯 Product vision
│   └── tools/
│
├── 📁 web/                            # 💎 RAILS + REACT
│   ├── app/
│   │   ├── assets/
│   │   │   └── stylesheets/
│   │   ├── channels/
│   │   │   └── application_cable/
│   │   ├── controllers/
│   │   │   ├── api/
│   │   │   │   └── v1/
│   │   │   │       ├── application_controller.rb
│   │   │   │       └── terminal_sessions_controller.rb  # 🎯 API
│   │   │   └── web/
│   │   │       ├── application_controller.rb
│   │   │       └── home_controller.rb
│   │   ├── frontend/                  # ⚛️ REACT SPA (FSD)
│   │   │   ├── app/
│   │   │   │   ├── App.tsx            # 🎯 App shell
│   │   │   │   ├── layouts/
│   │   │   │   ├── providers/
│   │   │   │   └── routeTree.tsx
│   │   │   ├── entities/
│   │   │   ├── entrypoints/
│   │   │   │   └── application.tsx    # 🚀 Frontend entry
│   │   │   ├── features/
│   │   │   │   └── file-tree/
│   │   │   │       ├── index.ts
│   │   │   │       └── ui/
│   │   │   │           ├── FileTree.tsx    # 🎯 File tree
│   │   │   │           └── FileViewer.tsx  # 🎯 File viewer
│   │   │   ├── pages/
│   │   │   │   ├── home/
│   │   │   │   │   └── ui/
│   │   │   │   │       └── HomePage.tsx
│   │   │   │   └── session/
│   │   │   │       └── ui/
│   │   │   │           └── SessionPage.tsx # 🎯 Terminal session
│   │   │   ├── shared/
│   │   │   │   ├── api/               # RTK Query
│   │   │   │   │   ├── baseApi.ts
│   │   │   │   │   ├── routes.ts
│   │   │   │   │   └── store.ts
│   │   │   │   ├── lib/               # Utilities
│   │   │   │   │   └── hooks/
│   │   │   │   ├── theme/             # MUI theme
│   │   │   │   └── ui/
│   │   │   │       └── Terminal/
│   │   │   └── widgets/
│   │   ├── models/
│   │   │   └── application_record.rb
│   │   ├── services/
│   │   │   ├── container_manager.rb   # 🎯 Docker orchestration
│   │   │   ├── temporal_service.rb    # 🎯 Temporal client
│   │   │   └── workflow_service.rb
│   │   ├── temporal/
│   │   │   ├── activities/
│   │   │   │   └── base.rb            # 🎯 Base activity
│   │   │   └── workflows/
│   │   │       └── base.rb
│   │   └── views/
│   │       └── layouts/
│   ├── bin/
│   │   ├── dev                        # 🚀 Development server
│   │   └── temporal_worker            # 🚀 Ruby worker
│   ├── config/
│   │   ├── application.rb             # 🎯 Rails config
│   │   ├── database.yml
│   │   ├── routes.rb                  # 🎯 Routes
│   │   └── settings/
│   ├── db/
│   │   ├── migrate/
│   │   ├── schema.rb                  # 🎯 DB schema
│   │   └── seeds.rb
│   ├── test/
│   ├── Dockerfile
│   ├── Gemfile                        # 🎯 Ruby dependencies
│   ├── Makefile
│   ├── package.json                   # 🎯 JS dependencies
│   ├── tsconfig.json
│   └── vite.config.ts
│
├── docker-compose.yml                 # 🎯 Development environment
├── docker-compose.ci.yml
└── Makefile                           # 🎯 Root commands
```

---

## Critical Folders by Part

### Web Part

| Folder | Purpose |
|--------|---------|
| `web/app/controllers/api/v1/` | REST API endpoints |
| `web/app/frontend/` | React SPA (FSD) |
| `web/app/services/` | Business logic |
| `web/app/temporal/` | Temporal integration |
| `web/config/` | Rails configuration |
| `web/db/` | Database schema and migrations |

### AI Engine Part

| Folder | Purpose |
|--------|---------|
| `ai-engine/app/agents/` | AI agents |
| `ai-engine/app/temporal/activities/` | Temporal activities |
| `ai-engine/app/temporal/workflows/` | Temporal workflows |
| `ai-engine/app/vector_engine/` | Qdrant integration |
| `ai-engine/app/llm/` | LLM factory |

### Infrastructure

| Folder | Purpose |
|--------|---------|
| `docker/claude-code/` | Claude Code container |
| `docker/remote/` | Remote deployment tools |
| `config/` | Shared workflow definitions |

### Knowledge Base

| Folder | Purpose |
|--------|---------|
| `kb/product/` | Product vision, architecture |
| `kb/operations/` | Team coordination |
| `_bmad/` | BMAD Method configuration |

---

## Entry Points

| Part | File | Command |
|------|------|---------|
| Web (Dev) | `web/bin/dev` | `docker-compose up web` |
| Web (Worker) | `web/bin/temporal_worker` | `docker-compose up worker-ruby` |
| AI Engine | `ai-engine/app/temporal/worker.py` | `docker-compose up worker-python` |
| Claude Code | `docker/claude-code/entrypoint.sh` | Via ContainerManager |
| Frontend | `web/app/frontend/entrypoints/application.tsx` | Via Vite |

---

## Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service orchestration |
| `config/workflows.yml` | Workflow definitions |
| `web/config/routes.rb` | API routes |
| `web/app/services/container_manager.rb` | Docker management |
| `ai-engine/app/temporal/worker.py` | Python worker entry |
| `kb/CLAUDE.md` | Claude Code rules |
