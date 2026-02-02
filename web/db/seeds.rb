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

puts "Seed data created successfully!"
