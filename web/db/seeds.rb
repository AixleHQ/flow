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
  company.state = :active
  company.settings = {
    billing: { enabled: false },
    features: { workflows: true, sessions: true }
  }
end

puts "Test company created: #{test_company.name}"

# Stop here in production environment
if Rails.env.production?
  puts "Skipping test data creation in production environment"
  return
end

puts "Creating test users..."
test_password = Settings.admin.password

# Company users
artem = User.find_or_create_by!(email: "artem@dualboot.dev") do |user|
  user.name = "Artem"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
end
puts "User created: #{artem.email}"

andrey = User.find_or_create_by!(email: "andrey@dualboot.dev") do |user|
  user.name = "Andrey"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
end
puts "User created: #{andrey.email}"

alex = User.find_or_create_by!(email: "alex@dualboot.dev") do |user|
  user.name = "Alexander"
  user.password = test_password
  user.password_confirmation = test_password
  user.state = :active
  user.company = test_company
end
puts "User created: #{alex.email}"

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

puts "Seed data created successfully!"
