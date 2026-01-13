# Create users with different roles
puts "Creating users..."
admin_password = Settings.admin.password
user_password = 'REDACTED_SEED_USER_PASSWORD'

# Create individual users
super_admin = User.find_or_create_by!(email: '3po@dualbootpartners.com') do |user|
  user.name = 'Super Admin'
  user.password = admin_password
  user.password_confirmation = admin_password
  user.status = 'active'
end

# Assign global super admin role
puts "Assigning super admin role..."
super_admin.add_role(:super_admin) unless super_admin.has_role?(:super_admin)

# Stop here in production environment
if Rails.env.production?
  puts "Skipping test data creation in production environment"
  return
end

account_writer = User.find_or_create_by!(email: 'account.writer@example.com') do |user|
  user.name = 'Account Writer'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
  user.status = 'active'
end

workspace_writer = User.find_or_create_by!(email: 'workspace.writer@example.com') do |user|
  user.name = 'Workspace Writer'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
  user.status = 'active'
end

specification_writer = User.find_or_create_by!(email: 'specification.writer@example.com') do |user|
  user.name = 'Specification Writer'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
  user.status = 'active'
end

account_reader = User.find_or_create_by!(email: 'account.reader@example.com') do |user|
  user.name = 'Account Reader'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
    user.status = 'active'
end

workspace_reader = User.find_or_create_by!(email: 'workspace.reader@example.com') do |user|
  user.name = 'Workspace Reader'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
  user.status = 'active'
end

specification_reader = User.find_or_create_by!(email: 'specification.reader@example.com') do |user|
  user.name = 'Specification Reader'
  user.password = user_password
  user.password_confirmation = user_password
  user.otp_secret = ROTP::Base32.random
  user.status = 'active'
end

# Create accounts with write and read roles
puts "Creating accounts with roles..."
accounts = 3.times.map do |i|
  account = Account.find_or_create_by!(name: "Account #{i + 1}") do |acc|
    acc.status = 'active'
  end

  # Assign account roles
  account_writer.add_role(:write, account) unless account_writer.has_role?(:write, account)
  AccountUser.find_or_create_by!(account: account, user: account_writer, status: :active)
  account_reader.add_role(:read, account) unless account_reader.has_role?(:read, account)
  AccountUser.find_or_create_by!(account: account, user: account_reader, status: :active)

  account
end

# Create workspaces with write and read roles
puts "Creating workspaces with roles..."
workspaces = accounts.flat_map do |account|
  2.times.map do |i|
    workspace = Workspace.find_or_create_by!(name: "#{account.name} - Workspace #{i + 1}", account: account) do |ws|
      ws.status = 'active'
    end

    # Assign workspace roles
    workspace_writer.add_role(:write, workspace) unless workspace_writer.has_role?(:write, workspace)
    workspace_reader.add_role(:read, workspace) unless workspace_reader.has_role?(:read, workspace)
    AccountUser.find_or_create_by!(account: workspace.account, user: workspace_writer, status: :active)
    AccountUser.find_or_create_by!(account: workspace.account, user: workspace_reader, status: :active)
    workspace
  end
end

# Create specifications with write and read roles
puts "Creating specifications with roles..."
workspaces.each do |workspace|
  2.times do |i|
    specification = Specification.find_or_create_by!(name: "#{workspace.name} - Specification #{i + 1}", workspace: workspace) do |spec|
      spec.status = 'active'
    end

    # Assign specification roles
    specification_writer.add_role(:write, specification) unless specification_writer.has_role?(:write, specification)
    specification_reader.add_role(:read, specification) unless specification_reader.has_role?(:read, specification)
    AccountUser.find_or_create_by!(account: specification.account, user: specification_writer, status: :active)
    AccountUser.find_or_create_by!(account: specification.account, user: specification_reader, status: :active)
  end
end

puts "Creating default LLM preset..."
gemini_flash_id = "google/gemini-3-flash-preview"
gemini_model = ModelDefinition.find_by(identifier: gemini_flash_id)

if gemini_model
  Preset.find_or_create_by!(name: "Balanced") do |preset|
    preset.default = true
    preset.public = true

    # Asset Roles
    preset.codebase_indexing_model = gemini_model
    preset.codebase_reporting_model = gemini_model
    preset.document_analysis_model = gemini_model
    preset.ui_vision_model = gemini_model
    preset.ui_critic_model = gemini_model
    preset.ui_summary_model = gemini_model

    # Specification Roles
    preset.domain_analysis_model = gemini_model
    preset.feature_extraction_model = gemini_model
    preset.user_story_model = gemini_model
    preset.use_case_model = gemini_model
    preset.diagram_model = gemini_model
    preset.data_flow_model = gemini_model
  end
else
  puts "Skipping default preset: Gemini Flash model not found. Run sync_model_list workflow first."
end

puts "Seed data created successfully!"
