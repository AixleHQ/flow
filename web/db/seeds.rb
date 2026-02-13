# frozen_string_literal: true

# Create super admin user (platform-level admin)
puts "Creating super admin user..."
super_admin_email = Settings.admin.email
super_admin_password = Settings.admin.password

super_admin = User.find_or_create_by!(email: super_admin_email) do |user|
  user.name = "Super Admin"
  user.password = super_admin_password
  user.password_confirmation = super_admin_password
  user.role = :super_admin
  user.company = nil # Super admin is platform-level, not company-scoped
  user.state = :active
end

puts "Creating test company..."
test_company = Company.find_or_create_by!(slug: "dualboot") do |company|
  company.name = "Dualboot Partners"
  company.email_domain = "dualbootpartners.com"
  company.state = :active
  company.auto_accept_users = true
  company.settings = {
    billing: { enabled: false },
    features: { workflows: true, sessions: true }
  }
end

puts "Test company created: #{test_company.name} (#{test_company.email_domain})"

# Stop here in production environment
if Rails.env.production?
  puts "Skipping test data creation in production environment"
  return
end

puts "Creating test users..."
test_password = Settings.admin.password

# Company users with onboarding completed
artem = User.find_or_create_by!(email: "artem@dualbootpartners.com") do |user|
  user.name = "Artem"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
  user.position = :dev
  user.preferred_agent_language = "en"
  user.onboarding_completed_at = Time.current
end
puts "User created: #{artem.email}"

andrey = User.find_or_create_by!(email: "andrey@dualbootpartners.com") do |user|
  user.name = "Andrey"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
  user.position = :dev
  user.preferred_agent_language = "ru"
  user.onboarding_completed_at = Time.current
end
puts "User created: #{andrey.email}"

alex = User.find_or_create_by!(email: "alex@dualbootpartners.com") do |user|
  user.name = "Alexander"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
  user.position = :qa
  user.preferred_agent_language = "en"
  user.onboarding_completed_at = Time.current
end
puts "User created: #{alex.email}"

# Create agent credentials for test users
puts "Creating test agent credentials..."
AgentCredential.find_or_create_by!(user: artem, agent_type: "claude_code") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: artem, agent_type: "cursor_cli") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: andrey, agent_type: "codex") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: alex, agent_type: "claude_code") do |cred|
  cred.config_data = { "test" => "data" }
end
puts "Agent credentials created"

puts "Creating test projects..."

# Project 1: Palad MVP - owned by Artem
palad_project = Project.find_or_create_by!(company: test_company, slug: "palad-mvp") do |project|
  project.name = "Palad MVP"
  project.description = "MVP development of Palad platform"
  project.state = :active
  project.owner = artem
  project.settings = {
    linear_team_id: nil,
    github_repo: "dualboot/palad"
  }
end

# Add collaborators
palad_project.add_collaborator(andrey)
palad_project.add_collaborator(alex)

puts "Project created: #{palad_project.name} (owner: #{palad_project.owner.name}, collaborators: #{palad_project.collaborators.count})"

# Project 2: Agent Research - owned by Andrey
research_project = Project.find_or_create_by!(company: test_company, slug: "agent-research") do |project|
  project.name = "Agent Research"
  project.description = "Research and testing of different AI coding agents"
  project.state = :active
  project.owner = andrey
  project.settings = {}
end

research_project.add_collaborator(alex)

puts "Project created: #{research_project.name} (owner: #{research_project.owner.name}, collaborators: #{research_project.collaborators.count})"

puts "Creating BMAD agents..."

# BMAD BMM Module agents (core development workflow)
bmad_agents = [
  {
    name: "analyst",
    title: "Business Analyst",
    icon: "📊",
    persona: "Strategic Business Analyst + Requirements Expert. Senior analyst with deep expertise in market research, competitive analysis, and requirements elicitation. Specializes in translating vague needs into actionable specs.",
    communication_style: "Speaks with the excitement of a treasure hunter - thrilled by every clue, energized when patterns emerge. Structures insights with precision while making analysis feel like discovery.",
    principles: "Channel expert business analysis frameworks: draw upon Porter's Five Forces, SWOT analysis, root cause analysis, and competitive intelligence methodologies. Every business challenge has root causes waiting to be discovered. Ground findings in verifiable evidence. Articulate requirements with absolute precision. Ensure all stakeholder voices heard."
  },
  {
    name: "pm",
    title: "Product Manager",
    icon: "📋",
    persona: "Product Manager specializing in collaborative PRD creation through user interviews, requirement discovery, and stakeholder alignment. Product management veteran with 8+ years launching B2B and consumer products. Expert in market research, competitive analysis, and user behavior insights.",
    communication_style: "Asks 'WHY?' relentlessly like a detective on a case. Direct and data-sharp, cuts through fluff to what actually matters.",
    principles: "Channel expert product manager thinking: draw upon deep knowledge of user-centered design, Jobs-to-be-Done framework, opportunity scoring. PRDs emerge from user interviews, not template filling - discover what users actually need. Ship the smallest thing that validates the assumption - iteration over perfection. Technical feasibility is a constraint, not the driver - user value first."
  },
  {
    name: "architect",
    title: "Architect",
    icon: "🏗️",
    persona: "System Architect + Technical Design Leader. Senior architect with expertise in distributed systems, cloud infrastructure, and API design. Specializes in scalable patterns and technology selection.",
    communication_style: "Speaks in calm, pragmatic tones, balancing 'what could be' with 'what should be.'",
    principles: "Channel expert lean architecture wisdom: draw upon deep knowledge of distributed systems, cloud patterns, scalability trade-offs, and what actually ships successfully. User journeys drive technical decisions. Embrace boring technology for stability. Design simple solutions that scale when needed. Developer productivity is architecture. Connect every decision to business value and user impact."
  },
  {
    name: "dev",
    title: "Developer Agent",
    icon: "💻",
    persona: "Senior Software Engineer. Executes approved stories with strict adherence to acceptance criteria, using Story Context XML and existing code to minimize rework and hallucinations.",
    communication_style: "Ultra-succinct. Speaks in file paths and AC IDs - every statement citable. No fluff, all precision.",
    principles: "The Story File is the single source of truth - tasks/subtasks sequence is authoritative over any model priors. Follow red-green-refactor cycle: write failing test, make it pass, improve code while keeping tests green. Never implement anything not mapped to a specific task/subtask in the story file. All existing tests must pass 100% before story is ready for review."
  },
  {
    name: "sm",
    title: "Scrum Master",
    icon: "🏃",
    persona: "Technical Scrum Master + Story Preparation Specialist. Certified Scrum Master with deep technical background. Expert in agile ceremonies, story preparation, and creating clear actionable user stories.",
    communication_style: "Crisp and checklist-driven. Every word has a purpose, every requirement crystal clear. Zero tolerance for ambiguity.",
    principles: "Strict boundaries between story prep and implementation. Stories are single source of truth. Perfect alignment between PRD and dev execution. Enable efficient sprints. Deliver developer-ready specs with precise handoffs."
  },
  {
    name: "ux_designer",
    title: "UX Designer",
    icon: "🎨",
    persona: "User Experience Designer + UI Specialist. Senior UX Designer with 7+ years creating intuitive experiences across web and mobile. Expert in user research, interaction design, AI-assisted tools.",
    communication_style: "Paints pictures with words, telling user stories that make you FEEL the problem. Empathetic advocate with creative storytelling flair.",
    principles: "Every decision serves genuine user needs. Start simple, evolve through feedback. Balance empathy with edge case attention. AI tools accelerate human-centered design. Data-informed but always creative."
  },
  {
    name: "tea",
    title: "Master Test Architect",
    icon: "🧪",
    persona: "Master Test Architect. Test architect specializing in API testing, backend services, UI automation, CI/CD pipelines, and scalable quality gates. Equally proficient in pure API/service-layer testing as in browser-based E2E testing.",
    communication_style: "Blends data with gut instinct. 'Strong opinions, weakly held' is their mantra. Speaks in risk calculations and impact assessments.",
    principles: "Risk-based testing - depth scales with impact. Quality gates backed by data. Tests mirror usage patterns (API, UI, or both). Flakiness is critical technical debt. Tests first AI implements suite validates. Calculate risk vs value for every testing decision. Prefer lower test levels (unit > integration > E2E) when possible."
  },
  {
    name: "tech_writer",
    title: "Technical Writer",
    icon: "📚",
    persona: "Technical Documentation Specialist + Knowledge Curator. Experienced technical writer expert in CommonMark, DITA, OpenAPI. Master of clarity - transforms complex concepts into accessible structured documentation.",
    communication_style: "Patient educator who explains like teaching a friend. Uses analogies that make complex simple, celebrates clarity when it shines.",
    principles: "Documentation is teaching. Every doc helps someone accomplish a task. Clarity above all. Docs are living artifacts that evolve with code. Know when to simplify vs when to be detailed."
  },
  {
    name: "bmad_master",
    title: "BMad Master",
    icon: "🧙",
    persona: "Master Task Executor + BMad Expert + Guiding Facilitator Orchestrator. Master-level expert in the BMAD Core Platform and all loaded modules with comprehensive knowledge of all resources, tasks, and workflows. Experienced in direct task execution and runtime resource management.",
    communication_style: "Direct and comprehensive, refers to himself in the 3rd person. Expert-level communication focused on efficient task execution, presenting information systematically using numbered lists.",
    principles: "Load resources at runtime never pre-load, and always present numbered lists for choices."
  }
]

bmad_agents.each do |agent_data|
  agent = test_company.agents.find_or_create_by!(name: agent_data[:name]) do |a|
    a.title = agent_data[:title]
    a.icon = agent_data[:icon]
    a.persona = agent_data[:persona]
    a.communication_style = agent_data[:communication_style]
    a.principles = agent_data[:principles]
    a.source = :bmad_import
  end
  puts "Agent created: #{agent.icon} #{agent.title} (#{agent.name})"
end

# ===========================================================================
# Project-scoped agents
# ===========================================================================
puts "Creating project-scoped agents..."

palad_agents = [
  {
    name: "ruby_expert",
    title: "Ruby/Rails Expert",
    icon: "💎",
    persona: "Senior Ruby on Rails engineer with 10+ years of experience. Deep expertise in Rails 7+, ActiveRecord, service objects, Sidekiq, and Temporal workflows. Follows Rails conventions strictly.",
    communication_style: "Concise and pragmatic. Explains trade-offs clearly. Prefers showing code over describing it.",
    principles: "Convention over configuration. Fat models are OK if well-tested. Service objects for complex business logic. Always write tests first. Prefer composition over inheritance."
  },
  {
    name: "frontend_dev",
    title: "React/TypeScript Frontend Developer",
    icon: "⚛️",
    persona: "Senior frontend engineer specializing in React 18+, TypeScript, RTK Query, and modern CSS. Builds accessible, performant UI components following design system patterns.",
    communication_style: "Visual thinker. Describes UI in terms of components and user interactions. Uses concrete examples.",
    principles: "Components should be small and focused. Type everything. Use RTK Query for server state, Zustand for UI state. Accessibility is not optional. Performance budgets matter."
  }
]

palad_agents.each do |agent_data|
  agent = palad_project.agents.find_or_create_by!(name: agent_data[:name]) do |a|
    a.title = agent_data[:title]
    a.icon = agent_data[:icon]
    a.persona = agent_data[:persona]
    a.communication_style = agent_data[:communication_style]
    a.principles = agent_data[:principles]
    a.source = :custom
  end
  puts "  Agent created: #{agent.icon} #{agent.title} (project: #{palad_project.name})"
end

# ===========================================================================
# Skills
# ===========================================================================
puts "Creating skills..."

# Company-scoped skills
company_skills = [
  {
    name: "clean-code",
    title: "Clean Code Guidelines",
    description: "Company-wide clean code standards and conventions",
    content: <<~MD
      # Clean Code Guidelines

      ## Naming
      - Use descriptive, intention-revealing names
      - Classes: nouns (UserService, PaymentProcessor)
      - Methods: verbs (calculate_total, send_notification)
      - Booleans: prefix with is/has/can (is_active, has_permission)

      ## Functions
      - Keep functions small (< 20 lines ideal)
      - Single responsibility — one reason to change
      - Max 3 parameters; use options hash or value object for more
      - Avoid side effects — prefer pure functions where possible

      ## Error Handling
      - Use exceptions for exceptional cases, not control flow
      - Create custom exception classes for domain errors
      - Always log with context (user_id, request_id, operation)
      - Never swallow exceptions silently

      ## Testing
      - Every public method should have tests
      - Test behavior, not implementation
      - Use factories, not fixtures
      - Name tests: test_<method>_<scenario>_<expected_result>
    MD
  },
  {
    name: "git-workflow",
    title: "Git Workflow & Commit Conventions",
    description: "Git branching strategy and commit message format",
    content: <<~MD
      # Git Workflow

      ## Branch Naming
      - feature/<ticket>-<short-description>
      - fix/<ticket>-<short-description>
      - refactor/<description>

      ## Commit Messages
      Format: `<type>(<scope>): <description>`

      Types: feat, fix, refactor, test, docs, chore, perf
      Scope: component or area (api, ui, auth, db)

      Examples:
      - feat(api): add session context assembly endpoint
      - fix(auth): handle expired OAuth token refresh
      - test(skills): add adapter skill_files coverage

      ## PR Guidelines
      - Keep PRs focused (< 400 lines ideal)
      - Include test coverage for all changes
      - Link to story/ticket in description
      - Request review from at least 1 team member
    MD
  },
  {
    name: "rails-conventions",
    title: "Rails Project Conventions",
    description: "Rails patterns, service objects, and testing standards",
    content: <<~MD
      # Rails Conventions

      ## Service Objects
      - Place in app/services/
      - Use class methods for stateless operations
      - Name with verb: CreateUser, ProcessPayment, InjectConfig
      - Return result objects or raise domain exceptions

      ## Models
      - Keep validations in model
      - Use scopes for common queries
      - Extract complex queries to query objects
      - Use concerns sparingly — prefer composition

      ## Controllers
      - Thin controllers — delegate to services
      - Use strong parameters
      - Respond with proper HTTP status codes
      - API controllers inherit from Api::BaseController

      ## Testing
      - Use Minitest + FactoryBot
      - Run: `bundle exec rails test`
      - Lint: `bundle exec rubocop`
      - All tests must pass before PR review
      - Use mocha for mocking (expects/stubs)
    MD
  }
]

company_skills.each do |skill_data|
  skill = test_company.skills.find_or_create_by!(name: skill_data[:name]) do |s|
    s.title = skill_data[:title]
    s.description = skill_data[:description]
    s.content = skill_data[:content]
    s.kind = :custom
  end
  puts "  Skill created: #{skill.title} (company)"
end

# Project-scoped skills
project_skills = [
  {
    name: "palad-architecture",
    title: "Palad Architecture Overview",
    description: "Palad platform architecture patterns and key decisions",
    content: <<~MD
      # Palad Architecture

      ## Stack
      - Backend: Ruby on Rails 7.2, PostgreSQL, Redis, Temporal
      - Frontend: React 18, TypeScript, RTK Query, TailwindCSS
      - Infrastructure: Docker, Kubernetes, S3

      ## Key Patterns
      - **Container Execution**: ContainerService.execute(strategy:, input:) with lifecycle hooks
      - **Session Context**: SessionContextService orchestrates all container context injection
      - **Adapter Pattern**: Per-CLI adapters (ClaudeCode, Codex, GeminiCli, CursorCli) handle format differences
      - **MCP Integration**: Internal palad-tools server + external MCP servers (Tavily, Context7)

      ## Container Lifecycle
      1. before_create → create → before_start → start
      2. before_exec (inject credentials, config, MCP, skills, context)
      3. exec (agent runs)
      4. before_cleanup (collect artifacts) → cleanup

      ## File Paths
      - Agent configs: ~/.<cli>/ (home directory, not /workspace)
      - User assets: /workspace/input/ (read-only)
      - Agent outputs: /workspace/output/ (collected as artifacts)
    MD
  },
  {
    name: "docker-development",
    title: "Docker Development Workflow",
    description: "How to run and test in the Docker development environment",
    content: <<~MD
      # Docker Development

      ## Starting Services
      ```bash
      docker-compose up -d        # Start all services
      docker-compose logs -f web   # Follow web logs
      ```

      ## Running Commands
      ```bash
      docker-compose run --rm web bundle exec rails test          # Run tests
      docker-compose run --rm web bundle exec rubocop             # Run linter
      docker-compose run --rm web bundle exec rails db:migrate    # Migrations
      docker-compose run --rm web bundle exec rails console       # Console
      ```

      ## Key Services
      - web: Rails app (port 3000)
      - db: PostgreSQL (port 5432)
      - redis: Redis (port 6379)
      - temporal: Temporal server
      - temporal-worker: Temporal worker

      ## Troubleshooting
      - `bundle install` errors: Run `docker-compose run --rm web bundle install`
      - DB issues: `docker-compose run --rm web bundle exec rails db:reset`
      - Clear containers: `docker-compose down -v`
    MD
  }
]

project_skills.each do |skill_data|
  skill = palad_project.skills.find_or_create_by!(name: skill_data[:name]) do |s|
    s.title = skill_data[:title]
    s.description = skill_data[:description]
    s.content = skill_data[:content]
    s.kind = :custom
  end
  puts "  Skill created: #{skill.title} (project: #{palad_project.name})"
end

# ===========================================================================
# MCP Servers
# ===========================================================================
puts "Creating MCP servers..."

# Company-scoped MCP servers
company_mcp_servers = [
  {
    name: "context7",
    display_name: "Context7 Documentation",
    description: "Library documentation search. Retrieves up-to-date API docs, code examples, and best practices for programming libraries and frameworks.",
    url: "https://mcp.context7.com/mcp",
    transport: :sse,
    headers: { CONTEXT7_API_KEY: "REDACTED_CONTEXT7_API_KEY" }
  }
]

company_mcp_servers.each do |server_data|
  server = test_company.mcp_servers.find_or_create_by!(name: server_data[:name]) do |s|
    s.display_name = server_data[:display_name]
    s.description = server_data[:description]
    s.url = server_data[:url]
    s.transport = server_data[:transport]
    s.headers = server_data[:headers]
    s.kind = :custom
    s.enabled = true
  end
  puts "  MCP Server created: #{server.display_name} (company)"
end

puts "Creating config items for MCP server authentication..."

tool = test_company.tools.find_or_create_by!(name: "slack_history", scope: test_company) do |t|
  t.display_name = "Slack History"
  t.description = "Fetch messages from a Slack channel for a given time range"
  t.docker_image = "ruby:3.3-slim"
  t.command = "ruby /workspace/main.rb"
  t.required_config_items = %w[SLACK_TOKEN SLACK_CHANNEL SLACK_RANGE]
  t.input_schema = {
    type: "object",
    properties: {
      SLACK_RANGE: { type: "string", description: "Time range (e.g. 24h, 7d, 1w)", default: "24h" }
    }
  }
end

# --- Tool File ---
tool.tool_files.find_or_create_by!(path: "/workspace/main.rb") do |f|
  f.content = <<~'RUBY'
    #!/usr/bin/env ruby
    require "net/http"
    require "uri"
    require "json"

    def env!(k)
      v = ENV[k].to_s.strip
      abort("missing #{k}") if v.empty?
      v
    end

    def secs(s)
      n, u = s.to_s.strip.match(/\A(\d+)([smhdw])\z/)&.captures
      abort("bad SLACK_RANGE (use 24h/7d/1d)") unless n
      n = n.to_i
      { "s"=>1, "m"=>60, "h"=>3600, "d"=>86400, "w"=>604800 }[u] * n
    end

    def slack_get(path, token, params = {})
      uri = URI("https://slack.com/api/#{path}")
      uri.query = URI.encode_www_form(params)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      data = JSON.parse(Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }.body)
      abort("slack error: #{data["error"]}") unless data["ok"]
      data
    end

    def resolve_channel(name, token)
      return name if name.match?(/\A[CGD][A-Z0-9]+\z/)
      name = name.delete_prefix("#")
      cursor = nil
      loop do
        data = slack_get("conversations.list", token, { "limit"=>"200", "types"=>"public_channel,private_channel", "cursor"=>cursor.to_s })
        ch = data["channels"].find { |c| c["name"] == name }
        return ch["id"] if ch
        cursor = data.dig("response_metadata", "next_cursor").to_s.strip
        abort("channel '#{name}' not found") if cursor.empty?
      end
    end

    token   = env!("SLACK_TOKEN")
    channel = resolve_channel(env!("SLACK_CHANNEL"), token)
    range   = ENV.fetch("SLACK_RANGE", "24h")

    now = Time.now.to_i
    oldest = (now - secs(range)).to_s
    latest = now.to_s

    cursor = nil
    loop do
      q = { "channel"=>channel, "oldest"=>oldest, "latest"=>latest, "limit"=>"200" }
      q["cursor"] = cursor unless cursor.to_s.empty?
      data = slack_get("conversations.history", token, q)

      (data["messages"] || []).each { |m| STDOUT.puts(JSON.generate(m)) }

      cursor = data.dig("response_metadata", "next_cursor").to_s.strip
      break if cursor.empty?
    end
  RUBY
end

puts "Seed data created successfully!"
