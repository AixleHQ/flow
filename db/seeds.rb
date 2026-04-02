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

require_relative "seeds/platform_tools"
Seeds::PlatformTools.seed!

require_relative "seeds/internal_skills"
Seeds::InternalSkills.seed!

require_relative "seeds/aixle_builder"
Seeds::AixleBuilder.seed!

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

# Project 1: Aixle MVP - owned by Artem
aixle_project = Project.find_or_create_by!(company: test_company, slug: "aixle-mvp") do |project|
  project.name = "Aixle MVP"
  project.description = "MVP development of Aixle platform"
  project.state = :active
  project.owner = artem
  project.settings = {
    linear_team_id: nil,
    github_repo: "aixle/aixle"
  }
end

# Add collaborators
aixle_project.add_collaborator(andrey)
aixle_project.add_collaborator(alex)

puts "Project created: #{aixle_project.name} (owner: #{aixle_project.owner.name}, collaborators: #{aixle_project.collaborators.count})"

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
