# Brainstorm: BMad Configuration in Database with Docker Mount

**Date:** 2026-01-21
**Status:** Draft
**Author:** AI Assistant + Artem Petrov

---

## Problem Statement

The current BMad Method architecture assumes storing configuration in the file system (`_bmad/` directory). When using Docker containers for AI agents (Claude Code, Cursor CLI, Codex), problems arise:

1. **Loss of configuration** — when the container is recreated, the config is lost
2. **No persistence of agent memory** — sidecar memory is not preserved between sessions
3. **Multi-tenancy complexity** — each user needs their own config
4. **No versioning** — there is no change history for the configuration
5. **Module duplication** — module sources are copied for each session

---

## Proposed Solution

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PostgreSQL                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ bmad_configurations                                           │   │
│  │ ├── user_id / team_id                                        │   │
│  │ ├── core_config (JSONB)                                      │   │
│  │ ├── module_configs (JSONB)                                   │   │
│  │ ├── agent_customizations (JSONB)                             │   │
│  │ ├── agent_memory (JSONB)                                     │   │
│  │ └── installed_modules (Array)                                │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Config Materializer Service                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 1. Fetch config from DB                                       │   │
│  │ 2. Generate _bmad/ structure in temp dir                     │   │
│  │ 3. Mount into container as volume                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Docker Container                                │
│  /workspace/                                                         │
│  ├── repo/           ← git clone                                    │
│  ├── _bmad/          ← MOUNTED from materialized config             │
│  │   ├── _config/                                                   │
│  │   ├── core/                                                      │
│  │   ├── bmm/                                                       │
│  │   └── ...                                                        │
│  └── output/                                                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Model

### Database Schema

```sql
CREATE TABLE bmad_configurations (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  team_id BIGINT REFERENCES teams(id),

  -- Installation metadata
  bmad_version VARCHAR(50) NOT NULL DEFAULT '6.0.0',
  installed_modules TEXT[] NOT NULL DEFAULT ARRAY['core', 'bmm'],
  configured_ides TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

  -- Module configurations (replaces config.yaml files)
  core_config JSONB NOT NULL DEFAULT '{}',
  module_configs JSONB NOT NULL DEFAULT '{}',

  -- Agent customizations (replaces .customize.yaml files)
  agent_customizations JSONB NOT NULL DEFAULT '{}',

  -- Memory persistence (sidecar data)
  agent_memory JSONB NOT NULL DEFAULT '{}',

  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

  UNIQUE(user_id, team_id)
);

CREATE INDEX idx_bmad_configs_user ON bmad_configurations(user_id);
CREATE INDEX idx_bmad_configs_team ON bmad_configurations(team_id);
```

### JSONB Structures

#### core_config

```json
{
  "user_name": "Artem",
  "communication_language": "Russian",
  "document_output_language": "English",
  "output_folder": "_bmad-output"
}
```

#### module_configs

```json
{
  "bmm": {
    "project_name": "Palad Platform",
    "user_skill_level": "expert",
    "planning_artifacts": "_bmad-output/planning-artifacts",
    "implementation_artifacts": "_bmad-output/implementation-artifacts",
    "project_knowledge": "docs",
    "tea_use_mcp_enhancements": false,
    "tea_use_playwright_utils": false
  },
  "cis": {
    "default_brainstorm_technique": "random"
  }
}
```

#### agent_customizations

```json
{
  "bmm-dev": {
    "persona": {
      "communication_style": "Ultra-concise, Russian comments in code"
    },
    "principles": [
      "Always write tests first",
      "Use TypeScript strict mode"
    ]
  },
  "bmm-architect": {
    "persona": {
      "principles": [
        "Prefer PostgreSQL over other databases",
        "Use Redis for caching"
      ]
    }
  }
}
```

#### agent_memory

```json
{
  "bmm-architect": {
    "decisions": "# Architecture Decisions\n\n## 2026-01-15\n- Decided to use...",
    "context": "# Project Context\n\nThis project is..."
  },
  "storyteller": {
    "characters": "# Character Database\n\n## Main Characters\n..."
  }
}
```

---

## Components

### 1. BmadConfiguration Model

```ruby
# app/models/bmad_configuration.rb
class BmadConfiguration < ApplicationRecord
  belongs_to :user
  belongs_to :team, optional: true

  DEFAULT_MODULES = %w[core bmm].freeze

  validates :bmad_version, presence: true
  validates :installed_modules, presence: true

  # Accessors
  def user_name
    core_config["user_name"] || user.name
  end

  def config_for(module_name)
    return core_config if module_name == "core"
    core_config.merge(module_configs[module_name] || {})
  end

  def customization_for(agent_id)
    agent_customizations[agent_id] || {}
  end

  def update_agent_memory(agent_id, memory_data)
    self.agent_memory = agent_memory.merge(agent_id => memory_data)
    save!
  end
end
```

### 2. BmadConfigMaterializer Service

A key service that:

1. **Reads configuration from the DB**
2. **Copies module files** from `vendor/bmad-method/src/`
3. **Generates config.yaml** for each module from JSONB
4. **Generates .customize.yaml** for agents
5. **Restores _memory/** from agent_memory
6. **Generates manifests** (workflow-manifest.csv, agent-manifest.csv)

```ruby
# app/services/bmad_config_materializer.rb
class BmadConfigMaterializer
  BMAD_SOURCE_PATH = Rails.root.join("vendor", "bmad-method", "src")

  def self.materialize(config, session_id)
    target_path = Rails.root.join("tmp", "bmad_configs", session_id, "_bmad")

    # Check cache
    return target_path if cached?(config, target_path)

    # Clean and recreate
    FileUtils.rm_rf(target_path)
    FileUtils.mkdir_p(target_path)

    # 1. Copy module files (read-only source)
    copy_module_files(config, target_path)

    # 2. Generate config.yaml from DB
    generate_module_configs(config, target_path)

    # 3. Generate agent customizations
    generate_agent_customizations(config, target_path)

    # 4. Generate manifests
    generate_manifests(config, target_path)

    # 5. Restore agent memory
    restore_agent_memory(config, target_path)

    target_path
  end

  def self.sync_memory_to_db(config, session_id)
    # Read _memory/*-sidecar/*.md files
    # Update config.agent_memory in DB
  end
end
```

### 3. ContainerManager Integration

```ruby
# app/services/container_manager.rb
def create_session(session_id:, agent_type:, user:, ...)
  # ... existing setup ...

  # Materialize BMad config from database
  bmad_config_path = nil
  if user&.bmad_configuration.present?
    bmad_config_path = BmadConfigMaterializer.materialize(
      user.bmad_configuration,
      session_id
    )
  end

  # Add to volume binds
  binds = ["#{workspace_path}:/workspace:rw"]
  binds << "#{bmad_config_path}:/workspace/_bmad:rw" if bmad_config_path

  # Create container with binds
  # ...
end

def stop_session(session_id:, agent_type:)
  # Sync memory back to DB before stopping
  if user&.bmad_configuration
    BmadConfigMaterializer.sync_memory_to_db(
      user.bmad_configuration,
      session_id
    )
  end

  # ... existing cleanup ...
end
```

---

## Data Flow

### Session Start

```
1. User clicks "Start Session"
   │
2. TerminalSessionsController#create
   │
3. ContainerManager.create_session(user: current_user)
   │
4. BmadConfigMaterializer.materialize(user.bmad_configuration, session_id)
   │
   ├── Copy vendor/bmad-method/src/{core,modules/bmm}/
   │   └── → tmp/bmad_configs/{session_id}/_bmad/{core,bmm}/
   │
   ├── Generate config.yaml from core_config + module_configs
   │   └── → tmp/bmad_configs/{session_id}/_bmad/{module}/config.yaml
   │
   ├── Generate .customize.yaml from agent_customizations
   │   └── → tmp/bmad_configs/{session_id}/_bmad/_config/agents/
   │
   ├── Restore memory from agent_memory
   │   └── → tmp/bmad_configs/{session_id}/_bmad/_memory/
   │
   └── Generate manifests
       └── → tmp/bmad_configs/{session_id}/_bmad/_config/*.csv
   │
5. Docker container created with volume:
   └── tmp/bmad_configs/{session_id}/_bmad → /workspace/_bmad
```

### Session End

```
1. User closes session / timeout
   │
2. ContainerManager.stop_session(session_id)
   │
3. BmadConfigMaterializer.sync_memory_to_db(config, session_id)
   │
   ├── Read tmp/bmad_configs/{session_id}/_bmad/_memory/*-sidecar/*.md
   │
   └── Update bmad_configurations.agent_memory in PostgreSQL
   │
4. Stop and remove container
   │
5. Cleanup tmp/bmad_configs/{session_id}/ (optional, can cache)
```

---

## API Endpoints

### Configuration Management

```
GET    /api/v1/bmad_configuration
       → Returns current user's BMad configuration

PATCH  /api/v1/bmad_configuration
       → Updates core_config, module_configs

POST   /api/v1/bmad_configuration/install_module
       → Adds module to installed_modules, initializes module_configs

DELETE /api/v1/bmad_configuration/uninstall_module
       → Removes module from installed_modules

PATCH  /api/v1/bmad_configuration/agent_customization/:agent_id
       → Updates customization for specific agent

GET    /api/v1/bmad_configuration/agent_memory/:agent_id
       → Returns memory for specific agent

DELETE /api/v1/bmad_configuration/agent_memory/:agent_id
       → Clears memory for specific agent
```

### UI Integration

```
GET    /api/v1/bmad/modules
       → Lists available modules with descriptions

GET    /api/v1/bmad/agents
       → Lists available agents for installed modules

GET    /api/v1/bmad/workflows
       → Lists available workflows for installed modules
```

---

## Caching Strategy

### Materialized Config Cache

```ruby
def cached?(config, target_path)
  cache_marker = target_path.join(".cache_marker")
  return false unless cache_marker.exist?

  cached_data = JSON.parse(File.read(cache_marker))

  # Valid if:
  # 1. Config hasn't been updated since materialization
  # 2. BMad version matches
  cached_data["config_updated_at"] == config.updated_at.iso8601 &&
    cached_data["version"] == config.bmad_version
end
```

### Cache Invalidation

- **Automatic:** When `bmad_configuration` is updated (via `after_save` callback)
- **Manual:** API endpoint to force re-materialization
- **TTL-based:** Optional cleanup of stale materialized configs

---

## Module Source Management

### Vendor Directory Structure

```
vendor/
└── bmad-method/
    └── src/
        ├── core/
        │   ├── agents/
        │   │   └── bmad-master.agent.yaml
        │   ├── workflows/
        │   │   ├── brainstorming/
        │   │   └── party-mode/
        │   └── module.yaml
        └── modules/
            ├── bmm/
            │   ├── agents/
            │   ├── workflows/
            │   └── module.yaml
            ├── bmb/
            └── cis/
```

### Update Strategy

1. **Git submodule** or **npm package** for `bmad-method`
2. Periodic updates via CI/CD
3. Version pinning in `bmad_configurations.bmad_version`
4. Migration scripts for breaking changes

---

## Security Considerations

1. **User Isolation:** Each user has their own config, no cross-contamination
2. **Team Sharing:** Optional team-level configs with proper RBAC
3. **Memory Privacy:** Agent memory stored per-user, encrypted at rest
4. **API Key Storage:** Stored separately in Settings, not in bmad_configuration
5. **Container Isolation:** Each session gets unique materialized path

---

## Migration Path

### From File-based to DB-based

1. **Export existing config:**
   ```ruby
   existing = YAML.load_file("_bmad/core/config.yaml")
   user.create_bmad_configuration!(
     core_config: existing,
     installed_modules: detect_installed_modules("_bmad/")
   )
   ```

2. **Import agent customizations:**
   ```ruby
   Dir.glob("_bmad/_config/agents/*.customize.yaml").each do |file|
     agent_id = File.basename(file, ".customize.yaml")
     customization = YAML.load_file(file)
     config.agent_customizations[agent_id] = customization
   end
   ```

3. **Import agent memory:**
   ```ruby
   Dir.glob("_bmad/_memory/*-sidecar").each do |sidecar|
     agent_id = File.basename(sidecar, "-sidecar")
     memory = {}
     Dir.glob(File.join(sidecar, "*.md")).each do |file|
       key = File.basename(file, ".md")
       memory[key] = File.read(file)
     end
     config.agent_memory[agent_id] = memory
   end
   ```

---

## Benefits

| Aspect | Benefit |
|--------|---------|
| **Persistence** | Config survives container restarts |
| **Multi-tenancy** | Each user/team has isolated config |
| **Versioning** | Can track config changes over time |
| **Memory Sync** | Agent memory persists between sessions |
| **Centralized Management** | UI/API for config management |
| **Caching** | Materialized config cached, regenerated only on changes |
| **Immutable Modules** | Source modules read-only, only config generated |
| **Scalability** | Works with multiple concurrent sessions |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **DB latency** | Cache materialized configs aggressively |
| **Large memory data** | Compress or store in S3/blob storage |
| **Version conflicts** | Pin BMad version per config, migration scripts |
| **Disk space** | TTL cleanup of old materialized configs |
| **Concurrent updates** | Optimistic locking on bmad_configuration |

---

## Next Steps

1. [ ] Create database migration
2. [ ] Implement BmadConfiguration model
3. [ ] Implement BmadConfigMaterializer service
4. [ ] Update ContainerManager integration
5. [ ] Create API endpoints
6. [ ] Build UI for config management
7. [ ] Add vendor/bmad-method submodule
8. [ ] Write migration script for existing users
9. [ ] Add tests

---

## Open Questions

1. **Team configs:** How to handle team-level vs user-level config inheritance?
2. **Memory limits:** Should we limit agent_memory size? Archive old memory?
3. **Real-time sync:** Should memory sync happen periodically during session?
4. **Offline mode:** How to handle when DB is unavailable?
5. **Config sharing:** Allow users to share/export their configurations?

---

## References

- [BMad Method Technical Analysis](./brainstorm-bmad-method-analysis.md)
- [Container Manager Implementation](../web/app/services/container_manager.rb)
- [BMad Method Source](./BMAD-METHOD/)
