# Palad App

This is a Ruby on Rails application with a modern frontend stack.

## Prerequisites

- Docker and Docker Compose

## Local Development Setup

1. Clone the repository:
```bash
git clone https://github.com/palad-ai/palad-app.git
cd palad-app
```

2. Set up the project using Docker:
```bash
make setup
```
This command will:
- Build Docker containers
- Install Ruby dependencies (via Bundler)
- Install JavaScript dependencies (via Yarn)
- Create and set up the database

3. Start the development server:
```bash
docker-compose up
```

4. Access the application at `http://localhost:4000`

## Google OAuth Configuration

To enable Google OAuth login, you need to configure Google Cloud Console:

1. **Create Google Cloud Project:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one

2. **Enable Google+ API:**
   - Navigate to "APIs & Services" → "Library"
   - Search for "Google+ API" and enable it

3. **Create OAuth 2.0 Credentials:**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth 2.0 Client ID"
   - Application type: "Web application"
   - Add Authorized redirect URI: `http://localhost:4000/api/v1/auth/google/callback`
   - For production, add: `https://yourdomain.com/api/v1/auth/google/callback`

4. **Set Environment Variables:**
   Create `.env` file in the `web/` directory:
   ```bash
   GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=your-client-secret
   ```

5. **Restart the application:**
   ```bash
   docker-compose restart web
   ```

**Note:** Without Google OAuth configuration, the Google login button will redirect to `/api/v1/auth/failure`. Password-based login will still work.

## Development Commands

### Database Management
- Prepare database: `make db-prepare`
- Reset database: `make db-reset`

### Code Quality and Testing
- Run all linters and tests: `make check`
- Run only linters: `make lint`
- Run only tests: `make test`
- Run Rubocop (Ruby linter): `make rubocop`
- Run Rubocop with auto-correction: `make rubocop-fix`
- Run ESLint (JavaScript linter): `make eslint`
- Run ESLint with auto-correction: `make eslint-fix`
- Run Brakeman security analysis: `make brakeman`
- Run Rails tests: `make rails-test`

### Frontend Development
- Run FSD (Feature-Sliced Design) analysis: `make fsd`
- Fix FSD issues: `make fsd-fix`

### Other Commands
- Open shell in web container: `make shell`
- Show available commands: `make help`

## Project Structure

The project follows a modern architecture with:
- Ruby on Rails backend
- Feature-Sliced Design (FSD) for frontend organization
- Docker-based development environment
- Comprehensive testing and linting setup

### Container Execution Framework (Epic 8)

Unified framework for running Docker containers with Strategy Pattern:

**Location:** `app/services/container_strategies/`

**Key Components:**
- `ContainerService` - Unified orchestrator with lifecycle phases
- `BaseStrategy` - Abstract base class with timeout protection
- `ToolExecutionStrategy` - Custom tool execution
- `AgentAuthStrategy` - Agent authentication containers
- `AgentSessionStrategy` - Pre-authenticated agent sessions

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

**Documentation:** See `ai/epic-8-unified-container-architecture.md`

### State Machines (AASM)

The project uses AASM gem for managing entity lifecycles and state transitions:

**Location:** `app/state_machines/`

**Active State Machines:**

1. **CompanyStateMachine** (`app/state_machines/company_state_machine.rb`)
   - States: `active` (initial), `suspended`, `archived`
   - Events: `suspend`, `activate`, `archive`
   - Auto-generated scopes: `Company.active`, `Company.suspended`, `Company.archived`

2. **UserStateMachine** (`app/state_machines/user_state_machine.rb`)
   - States: `active` (initial), `pending`, `suspended`, `archived`
   - Events: `activate`, `suspend`, `archive`, `mark_pending`
   - Auto-generated scopes: `User.active`, `User.pending`, etc.

**Usage Example:**
```ruby
# Change state via events
company.suspend!  # active → suspended
company.activate! # suspended → active

# Query by state
Company.active.where(email_domain: "acme.com")
User.pending.where(company: company)
```

**Note:** Roles (`employee`, `admin`, `super_admin`) and positions use `enumerize`, not state machines.

### Automatic Case Conversion (Frontend ↔ Backend)

The project automatically converts between camelCase (TypeScript) and snake_case (Ruby) in API requests/responses.

**Implementation:** `app/frontend/shared/api/baseApi.ts`

**How it works:**

```typescript
// Frontend sends (camelCase)
const request = {
  currentUser: {
    passwordConfirmation: "secret123",
    preferredAgentLanguage: "en"
  }
};

// Automatically converted to snake_case for Rails
// { current_user: { password_confirmation: "secret123", preferred_agent_language: "en" } }

// Rails responds (snake_case)
// { current_user: { onboarding_completed_at: "2026-01-23", agent_credentials: [...], configured_agents: [...] } }

// Automatically converted to camelCase for TypeScript
const response = {
  currentUser: {
    onboardingCompletedAt: "2026-01-23",
    // agentCredentials - full credential info
    agentCredentials: [{ agentType: "claude_code", configKeys: ["api_key"], ... }],
    // configuredAgents - derived list of agent types (read-only)
    configuredAgents: ["claude_code", "cursor_cli"]
  }
};
```

**TypeScript Best Practices:**
- All interfaces use camelCase (e.g., `IUpdateCurrentUserRequest`, `IUser`)
- No need for manual transform functions
- Automatic conversion happens at HTTP client level
- Consistent with `web_reference` project architecture

## Contributing

1. Create a new branch for your feature
2. Make your changes
3. Run `make check` to ensure all tests and linters pass
4. Submit a pull request

## AWS Vault Configuration

To configure AWS Vault, run: `aws-vault add {your_aws_vault_profile}`

## Remote Execution

To execute into QA container, run:
```
make exec-qa PROFILE={your_aws_vault_profile}
```

## Login to AWS account with AWS-Vault

```
make login_aws PROFILE={your_aws_vault_profile}
```

## Run browser tools server

```
make browser-tools-server
```

It will run browser tools server that will be listening on http://0.0.0.0:3025