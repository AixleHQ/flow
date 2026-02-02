# Implementation Notes

**Purpose:** Detailed implementation decisions made during development.
**See also:** [Architecture Document](./architecture.md) for core architectural decisions.

---

## User Onboarding Flow (Story 2.1, 2.2)

**Decision:** Mandatory 4-Step Onboarding with Strict Validation

**Context:**
Users must complete onboarding before accessing the platform. Onboarding **cannot be skipped** and includes:
1. **Step 1 - Your Profile:** Selecting position and preferred agent language
2. **Step 2 - Select Agents:** Selecting at least one AI agent (Claude Code, Cursor CLI, Codex, Gemini CLI)
3. **Step 3 - Authenticate:** Authenticating at least one selected agent
4. **Step 4 - Complete:** Reviewing and confirming setup

**Solution:**
Automatic `onboarding_completed_at` tracking via `before_validation` callback in User model:

```ruby
# app/models/user.rb
AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
POSITIONS = %w[qa pm_po_ba dev designer].freeze
AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

# Callbacks
before_validation :set_onboarding_completed_at, if: :onboarding_ready?

private

def onboarding_ready?
  return false if super_admin? || onboarding_completed?
  position.present? && preferred_agent_language.present? && has_configured_agents?
end
```

**API:** `PATCH /api/v1/current_user` accepts `position`, `preferred_agent_language`, `configured_agents[]`

---

## Agent Authentication Infrastructure (Story 2.3)

**Decision:** Terminal Sessions with State Machines + Temporal Workflows + Docker Containers

### TerminalSession Model (AASM State Machine)

```ruby
class TerminalSession < ApplicationRecord
  include AASM

  aasm column: :state do
    state :not_started, initial: true
    state :started, :running, :stopped, :collected, :failed, :cancelled

    event :start do
      transitions from: :not_started, to: :started, after: :start_temporal_workflow
    end
    # ... more events
  end
end
```

**States:** not_started → started → running → stopped → collected

### Temporal Workflow (AgentAuthWorkflow)

1. `StartAuthTerminalActivity` - Start container with empty home
2. Wait for `authentication_finished` signal
3. `CollectArtifactsActivity` - Extract and save credentials
4. `StopContainerActivity` - Cleanup

### AgentCredential Model

```ruby
class AgentCredential < ApplicationRecord
  belongs_to :user
  encrypts :encrypted_config_data
  validates :agent_type, uniqueness: { scope: :user_id }
end
```

---

## Agent Credentials Service (Strategy Pattern)

**Architecture:**
```
AgentCredentialsService              # Facade
├── Agents::BaseAdapter              # Abstract interface
├── Agents::ClaudeCodeAdapter        # Claude Code implementation
├── Agents::CursorCliAdapter         # Cursor CLI (stub)
├── Agents::CodexAdapter             # Codex (stub)
└── Agents::GeminiCliAdapter         # Gemini CLI (stub)
```

**Base Adapter Interface:**
```ruby
module Agents
  class BaseAdapter
    def config_path           # Path to config file
    def home_dir              # Home directory
    def auth_required_keys    # Keys for auth completion
    def extract_credentials   # Extract for DB
    def generate_config       # Generate full config
  end
end
```

**Adding new agent:**
1. Create `app/services/agents/{agent}_adapter.rb`
2. Implement all methods from `BaseAdapter`
3. Create Docker image in `docker/{agent}/`
4. Add to `AVAILABLE_AGENTS` in User model

---

## API Controller Patterns (2026-01-29)

### Minimalist Controller Style

```ruby
module Api::V1::Company
  class UsersController < ApplicationController
    def index
      users = current_company.users.ransack(params[:q]).result
      respond_with paginate(users)
    end

    def create
      user = current_company.users.create(user_params)
      respond_with user
    end
  end
end
```

### Dynamic Authorization

Authorization via `dynamic_authorize!` in namespace base controller:
- Controller: `Api::V1::Company::UsersController`
- Policy: `Api::V1::Company::UsersPolicy`

```ruby
module Api::V1::Company
  class ApplicationController < Api::V1::ApplicationController
    before_action :dynamic_authorize!

    def current_company
      @current_company ||= current_user.company
    end
  end
end
```

---

## Docker Images

| Image | Purpose |
|-------|---------|
| `palad/claude-code:latest` | Claude Code agent |
| `palad/cursor-cli:latest` | Cursor CLI agent |
| `palad/codex:latest` | OpenAI Codex agent |
| `palad/gemini-cli:latest` | Gemini CLI agent |

**Usage:**
- **auth_setup:** Container with empty home (tmpfs)
- **agent_session:** Container with mounted credentials

---

_Last updated: 2026-01-30_
