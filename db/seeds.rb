# frozen_string_literal: true

# Stop here in production environment
if Rails.env.production?
  puts "Skipping all seed data creation in production environment"
  return
end

# Create super admin user (platform-level admin)
puts "Creating super admin user..."
super_admin_email = Settings.admin.email
super_admin_password = Settings.admin.password

super_admin = User.find_or_create_by!(email: super_admin_email) do |user|
  user.name = "Super Admin"
  user.password = super_admin_password
  user.password_confirmation = super_admin_password
  user.super_admin = true # Platform-level admin, no company membership
  user.state = :active
end

# Platform tools are code-defined (InternalTools::* `tool do` blocks) and
# reconciled into shadow rows — see Tools::Reconciler.
puts "Reconciling platform tools..."
Tools::Reconciler.run!

require_relative "seeds/aixle_builder"
Seeds::AixleBuilder.seed!

seed_company_slug = ENV.fetch("SEED_COMPANY_SLUG", "demo")
seed_company_name = ENV.fetch("SEED_COMPANY_NAME", "Demo Company")
seed_company_email_domain = ENV.fetch("SEED_COMPANY_EMAIL_DOMAIN", "example.com")

puts "Creating test company..."
test_company = Company.find_or_create_by!(slug: seed_company_slug) do |company|
  company.name = seed_company_name
  company.email_domain = seed_company_email_domain
  company.state = :active
  company.auto_accept_users = true
  company.settings = {
    billing: { enabled: false },
    features: { workflows: true, sessions: true }
  }
end

puts "Test company created: #{test_company.name} (#{test_company.email_domain})"

# Second company with a different domain — demo for multi-company membership
puts "Creating client company..."
client_company = Company.find_or_create_by!(slug: "client-co") do |company|
  company.name = "Client Co"
  company.email_domain = "client-co.example"
  company.state = :active
  company.auto_accept_users = false
end
puts "Client company created: #{client_company.name} (#{client_company.email_domain})"

# Onboarding lives on the MEMBERSHIP (per company: own role, own agents, own
# separately-billed credential), so seeding a "ready to use" user means seeding a
# completed membership, not user columns.
ensure_membership = lambda do |user, company, role, position: :dev, language: "en", onboarded: true|
  CompanyMembership.find_or_create_by!(user: user, company: company) do |membership|
    membership.role = role
    membership.state = :active
    membership.accepted_at = Time.current
    membership.position = position
    membership.preferred_agent_language = language
    if onboarded
      membership.onboarding_state = "completed"
      membership.onboarding_completed_at = Time.current
    end
  end
end

puts "Creating test users..."
test_password = Settings.admin.password
seed_company_admin_email = ENV.fetch("SEED_COMPANY_ADMIN_EMAIL", "admin@#{seed_company_email_domain}")

company_admin = User.find_or_create_by!(email: seed_company_admin_email) do |user|
  user.name = "Company Admin"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
end
ensure_membership.call(company_admin, test_company, :admin, position: :pm_po_ba)
puts "User created: #{company_admin.email} (company admin)"

# Company users with onboarding completed
john = User.find_or_create_by!(email: "john@#{seed_company_email_domain}") do |user|
  user.name = "John"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
end
ensure_membership.call(john, test_company, :employee, position: :dev)
# Dual-membership demo: John is also a viewer in Client Co
ensure_membership.call(john, client_company, :viewer, position: :dev)
puts "User created: #{john.email} (also viewer in #{client_company.name})"

joane = User.find_or_create_by!(email: "joane@#{seed_company_email_domain}") do |user|
  user.name = "Joane"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
end
ensure_membership.call(joane, test_company, :employee, position: :dev, language: "ru")
puts "User created: #{joane.email}"

ivan = User.find_or_create_by!(email: "ivan@#{seed_company_email_domain}") do |user|
  user.name = "Ivan"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
end
ensure_membership.call(ivan, test_company, :employee, position: :qa)
puts "User created: #{ivan.email}"

# Create agent credentials for test users
puts "Creating test agent credentials..."
AgentCredential.find_or_create_by!(user: john, company: test_company, agent_type: "claude_code") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: john, company: test_company, agent_type: "cursor_cli") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: joane, company: test_company, agent_type: "codex") do |cred|
  cred.config_data = { "test" => "data" }
end
AgentCredential.find_or_create_by!(user: ivan, company: test_company, agent_type: "claude_code") do |cred|
  cred.config_data = { "test" => "data" }
end
puts "Agent credentials created"

puts "Creating test projects..."

# Project 1: Demo Alpha - owned by John
primary_project = Project.find_or_create_by!(company: test_company, slug: "demo-alpha") do |project|
  project.name = "Demo Alpha"
  project.description = "Primary demo project for onboarding"
  project.state = :active
  project.owner = john
  project.settings = {
    linear_team_id: nil,
    github_repo: "demo/demo-alpha"
  }
end

# Add collaborators
primary_project.add_collaborator(joane)
primary_project.add_collaborator(ivan)

puts "Project created: #{primary_project.name} (owner: #{primary_project.owner.name}, collaborators: #{primary_project.collaborators.count})"

# Project 2: Demo Beta - owned by Joane
research_project = Project.find_or_create_by!(company: test_company, slug: "demo-beta") do |project|
  project.name = "Demo Beta"
  project.description = "Secondary demo project for experimentation"
  project.state = :active
  project.owner = joane
  project.settings = {}
end

research_project.add_collaborator(ivan)

puts "Project created: #{research_project.name} (owner: #{research_project.owner.name}, collaborators: #{research_project.collaborators.count})"

# Agents are seeded per-workflow in db/seeds/ files

# ===========================================================================
# Board demo data
# ===========================================================================
puts "Creating board demo data..."

demo_board = Board.find_or_create_by!(project: primary_project) do |board|
  board.name = "Development Board"
end

board_columns_data = [
  { name: "Backlog", position: 1, purpose: "Planned work and ideas" },
  { name: "In Progress", position: 2, purpose: "Tasks currently in delivery" },
  { name: "Done", position: 3, purpose: "Completed tasks" }
]

board_columns_data.each do |column_data|
  column = demo_board.board_columns.find_or_initialize_by(name: column_data[:name])
  column.update!(
    position: column_data[:position],
    purpose: column_data[:purpose]
  )
end

backlog_column = demo_board.board_columns.find_by!(name: "Backlog")
demo_task = demo_board.board_tasks.find_or_initialize_by(title: "Set up project workflows")
demo_task.update!(
  board_column: backlog_column,
  assignee: john,
  task_type: :story,
  priority: :medium,
  description: "Initial workflow setup task created by seeds",
  tags: [ "seed", "demo" ]
)

puts "Board seeded: #{demo_board.name} (#{demo_board.board_columns.count} columns, #{demo_board.board_tasks.count} tasks)"

# NOTE: Company-scoped demo seeds (Context7 MCP server, Semgrep tool, Code Report
# agent/workflow) were removed along with the company-level entity screens —
# these resources now live at the project level. System-scoped platform tools are
# still reconciled above via Tools::Reconciler.

puts "Seed data created successfully!"
puts ""
puts "========== QUICK START =========="
puts "App URL: http://localhost:4000"
puts "Super admin: #{super_admin_email}"
puts "Company admin: #{company_admin.email}"
puts "Demo users: #{john.email}, #{joane.email}, #{ivan.email}"
puts "Password for all seeded users: #{test_password}"
puts "================================="
