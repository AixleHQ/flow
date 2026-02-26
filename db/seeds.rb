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

# Agents are seeded per-workflow in db/seeds/ files

# Skills are seeded per-workflow in db/seeds/ files when needed

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

# ===========================================================================
# Platform Tools (system, internal, workflow — no user scope)
# ===========================================================================
puts "Creating platform tools..."

# -- Workflow tools: auto-injected into workflow_step sessions --

Tool.find_or_initialize_by(name: "list_sub_steps", kind: :workflow).update!(
  display_name: "List Sub-Steps",
  description: "List current step's sub-steps with their statuses. Only available during workflow execution.",
  input_schema: { type: "object", properties: {} },
  execution_mode: :app
)

Tool.find_or_initialize_by(name: "mark_sub_step", kind: :workflow).update!(
  display_name: "Mark Sub-Step",
  description: "Update sub-step status with optional note and structured data. Only available during workflow execution.",
  input_schema: {
    type: "object",
    properties: {
      id: { type: "integer", description: "Sub-step run ID" },
      status: { type: "string", enum: %w[in_progress completed skipped], description: "New status" },
      note: { type: "string", description: "What was done, decisions made" },
      data: { type: "object", description: "Structured data — decisions, metrics, findings" }
    },
    required: %w[id status]
  },
  execution_mode: :app
)

Tool.find_or_initialize_by(name: "write_step_note", kind: :workflow).update!(
  display_name: "Write Step Note",
  description: "Save a note for this step. Visible to agents in subsequent steps via workflow context.",
  input_schema: {
    type: "object",
    properties: {
      note: { type: "string", description: "Note text to append" }
    },
    required: %w[note]
  },
  execution_mode: :app
)

# -- Internal tools: invisible, auto-injected when container tools present --

Tool.find_or_initialize_by(name: "read_tool_result", kind: :internal).update!(
  display_name: "Read Tool Result",
  description: "Retrieve status and download URLs for an async tool execution. " \
               "Returns presigned URLs valid for 1 hour. " \
               "Download files using curl: curl -o /tmp/result.json <url>",
  input_schema: {
    type: "object",
    properties: {
      tool_result_id: { type: "string", description: "Execution ID (e.g. tr-abc123...)" }
    },
    required: %w[tool_result_id]
  },
  execution_mode: :app
)

puts "  Platform tools: #{Tool.system_tools.count} system, #{Tool.internal_tools.count} internal, #{Tool.workflow_tools.count} workflow"

# ===========================================================================
# Internal Skills (from db/internal_skills/*.md)
# ===========================================================================
puts "Syncing internal skills..."
Dir.glob(Rails.root.join("db/internal_skills/*.md")).sort.each do |file_path|
  name = File.basename(file_path, ".md")
  raw = File.read(file_path)

  title, description, content = if raw.start_with?("---")
    parts = raw.split("---", 3)
    meta = parts.length >= 3 ? (YAML.safe_load(parts[1]) || {}) : {}
    [meta["title"], meta["description"], (parts[2] || "").strip]
  else
    [nil, nil, raw.strip]
  end

  skill = Skill.find_or_initialize_by(name: name, kind: :internal)
  skill.assign_attributes(title: title, description: description, content: content)
  skill.save! if skill.new_record? || skill.changed?
  puts "  Internal skill: #{name} — #{title}"
end

require_relative "seeds/slack_history_go"
Seeds::SlackHistoryGo.seed!(test_company)

require_relative "seeds/semgrep"
Seeds::Semgrep.seed!(test_company)

# ===========================================================================
# Workflows (loaded from db/seeds/)
# ===========================================================================
require_relative "seeds/code_report"

puts "Creating workflows..."
Seeds::CodeReport.seed!(test_company)

puts "Seed data created successfully!"
