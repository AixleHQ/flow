# frozen_string_literal: true

module Seeds
  module CodeReport
    TEMPLATE_PATH = File.expand_path("assets/code_report_template.html", __dir__)

    def self.seed!(company)
      agent = seed_agent!(company)
      workflow = seed_workflow!(company, agent)
      template = seed_template_asset!(company)

      { agent: agent, workflow: workflow, template: template }
    end

    def self.seed_agent!(company)
      company.agents.find_or_create_by!(name: "code_reporter") do |a|
        a.title = "Code Report Analyst"
        a.icon = "🔍"
        a.persona = <<~PERSONA.strip
          Senior Technical Auditor and Codebase Analyst. You perform deep, evidence-based analysis of software repositories. \
          You act as an independent auditor presenting findings to engineering leadership and external stakeholders. \
          Every claim is backed by file paths, line counts, or tool output. You never speculate — if data is unavailable, you state it explicitly.
        PERSONA
        a.communication_style = <<~STYLE.strip
          Dry, precise, audit-report tone. Writes in third person ("the codebase exhibits…", "the project relies on…"). \
          Avoids conversational filler, hedging, and flattery. Findings are structured as scored assessments with supporting evidence.
        STYLE
        a.principles = <<~PRINCIPLES.strip
          STATIC REPORT: You produce final, self-contained documents. Never ask questions, request follow-ups, \
          or offer additional work ("If you want…", "I can…", "Let me know…"). \
          Actionable recommendations are phrased directly in imperative or declarative form. End after the last section — no trailing notes.

          ANTI-LLM STYLE: No emojis or emoji-like status markers. \
          Avoid clichéd adjectives: "comprehensive", "robust", "seamless", "cutting-edge", "state-of-the-art", "leverages", "ensures". \
          Avoid templated meta-phrases: "This document outlines…", "The following section describes…". \
          Prefer prose over tables where text is more natural. Vary sentence and paragraph structure. \
          No inline ASCII diagrams — diagrams must be structurally correct or provided in a dedicated format.

          DATA-DRIVEN: Ground every section in quantitative evidence — cloc output, dependency counts, test coverage numbers, \
          file tree depth, cyclomatic complexity. Cite specific files and line numbers.
        PRINCIPLES
        a.source = :custom
      end
    end

    def self.seed_template_asset!(company)
      user = company.users.find_by(role: :admin) || company.users.first || User.first!
      asset = Asset.find_or_create_by!(
        scope_type: "Company",
        scope_id: company.id,
        name: "code_report_template.html",
        folder: "templates"
      ) do |a|
        a.created_by = user
        a.status = "active"
        a.tags = %w[template code-report html]
      end

      if asset.versions.empty?
        File.open(TEMPLATE_PATH, "r") do |f|
          version = asset.versions.build(
            uploaded_by: user,
            source: :upload,
            content_type: "text/html"
          )
          version.asset = asset
          version.file = f
          version.save!
        end
        puts "  Template asset created: #{asset.name} v1"
      else
        puts "  Template asset exists: #{asset.name} v#{asset.latest_version.version}"
      end

      asset
    end

    def self.seed_workflow!(company, agent)
      workflow = company.workflows.find_or_create_by!(name: "Code Report") do |w|
        w.description = "Generate a comprehensive code report from a repository and format it into a shareable HTML document"
        w.config = {}
      end

      step1 = seed_step_generate!(workflow, agent)
      step2 = seed_step_semgrep!(workflow)
      step3 = seed_step_format!(workflow, depends_on: [step1.id, step2.id])

      puts "Workflow '#{workflow.name}' seeded: #{workflow.steps.count} steps"

      workflow
    end

    # --- Step 1: Generate Code Report ---
    def self.seed_step_generate!(workflow, agent)
      step = workflow.steps.find_or_initialize_by(name: "Generate Code Report")
      step.update!(
        workflow: workflow,
        position: 1,
        agent: agent,
        description: "Analyze repository and generate a comprehensive code report with 7 sections",
        instructions: <<~MD,
          The repository is mounted at /workspace/repo/. You have access to shell tools: `tree`, `cloc`, `rg` (ripgrep), `fd`, `jq`.

          Work through sub-steps **in order** (by position). Each sub-step produces one section of the report:
          1. Overview — high-level project description and structure
          2. Static Analysis — gather quantitative metrics
          3. Technology Stack — inventory all technologies
          4. Code Quality Summary — assess quality and technical debt
          5. Infrastructure Analysis — evaluate DevOps setup
          6. Backend Analysis — analyze backend architecture
          7. Frontend Analysis — analyze frontend architecture

          For each sub-step:
          1. Use the available tools to gather quantitative data about the codebase
          2. Analyze the relevant source files directly
          3. Generate the section following the sub-step instructions exactly
          4. Mark each sub-step complete with `mark_sub_step`

          After all sub-steps are done, combine all sections into a single Markdown document.
          Save the final output as `code_report.md` in `/workspace/outputs/`.
        MD
        allow_non_interactive: true,
        skip_policy: :if_outputs_exist,
        on_failure: :retry,
        max_retries: 1,
        mount_repositories: true,
        input_asset_specs: [],
        output_asset_specs: [
          { name: "code_report.md", assetType: "document", required: true }
        ]
      )

      generate_sub_steps(step)
      puts "  Step 1: #{step.name} (#{step.sub_steps.count} sub-steps)"
      step
    end

    # --- Step 2: Run Semgrep ---
    def self.seed_step_semgrep!(workflow)
      semgrep_tool = Tool.find_by(name: "semgrep")

      step = workflow.steps.find_or_initialize_by(name: "Run Semgrep")
      step.update!(
        workflow: workflow,
        position: 2,
        description: "Run Semgrep static analysis on the project repository",
        instructions: <<~MD,
          Run the `semgrep` tool on the project repository.

          1. Identify the repository attached to this session (use repository_id from context)
          2. Call the `semgrep` tool with the repository_id
          3. Wait for the tool to complete by reading the tool result using `read_tool_result`
          4. Parse the JSON output and save it as `semgrep_report.json`
          5. Briefly summarize: total findings, breakdown by severity (ERROR/WARNING/INFO), top rule categories

          If the tool fails, note the error and continue — this step should not block the workflow.
        MD
        allow_non_interactive: true,
        skip_policy: :manual,
        on_failure: :skip,
        max_retries: 1,
        mount_repositories: true,
        tool_ids: [semgrep_tool&.id].compact,
        input_asset_specs: [],
        output_asset_specs: [
          { name: "semgrep_report.json", assetType: "document", required: false }
        ]
      )

      semgrep_sub_steps(step)
      puts "  Step 2: #{step.name} (#{step.sub_steps.count} sub-steps)"
      step
    end

    def self.semgrep_sub_steps(step)
      sub_steps = [
        {
          name: "Run Analysis", position: 1, required: true,
          description: "Call Semgrep tool and save results",
          instructions: <<~PROMPT
            1. Call the `semgrep` tool via MCP with the repository_id and optionally BRANCH
            2. Use `read_tool_result` to poll until the result is completed
            3. Download and save the JSON output to semgrep_report.json as a step output asset
            4. Summarize findings: total issues, breakdown by severity, top 5 rule categories
            5. If the analysis fails, note the error and continue — do not fail the step
          PROMPT
        }
      ]

      upsert_sub_steps(step, sub_steps)
    end

    # --- Step 3: Format & Share Report ---
    def self.seed_step_format!(workflow, depends_on: [])
      step = workflow.steps.find_or_initialize_by(name: "Format Report")
      step.update!(
        workflow: workflow,
        position: 3,
        depends_on_step_ids: depends_on,
        description: "Populate the HTML template with data from code report and optional Semgrep results",
        instructions: <<~MD,
          You are populating an existing HTML template with data from prior workflow steps.

          **All input files are pre-loaded in /workspace/assets/:**
          - `code_report.md` — the generated code report from Step 1 (required)
          - `code_report_template.html` — the HTML template to populate (required)
          - `semgrep_report.json` — Semgrep static analysis results from Step 2 (optional, may not exist)

          **Your task:**
          1. Read `/workspace/assets/code_report_template.html` — this is the master template. Do NOT create a new template.
          2. Read `/workspace/assets/code_report.md` — extract each section (Overview, Static Analysis, Technology Stack, etc.)
          3. If `/workspace/assets/semgrep_report.json` exists, read it and prepare a summary of findings.
          4. Convert each Markdown section to HTML and insert it into the corresponding section placeholder in the template.
          5. Replace template placeholders: {{PROJECT_NAME}}, {{DATE}}, section content areas.
          6. If Semgrep data exists, populate the security analysis section or add an appendix.
          7. If a section is missing from code_report.md, hide or remove that section from the template.
          8. Save the final populated HTML as `/workspace/outputs/code_report.html`

          **Critical rules:**
          - Do NOT redesign or recreate the template — only fill in data
          - Preserve all CSS, JS (mermaid, etc.), and layout from the template
          - The output must be a complete, self-contained HTML file
        MD
        allow_non_interactive: true,
        skip_policy: :never,
        on_failure: :retry,
        max_retries: 1,
        mount_repositories: false,
        input_asset_specs: [
          { name: "code_report.md", assetType: "document", required: true },
          { name: "code_report_template.html", assetType: "document", required: true },
          { name: "semgrep_report.json", assetType: "document", required: false }
        ],
        output_asset_specs: [
          { name: "code_report.html", assetType: "document", required: true }
        ]
      )

      format_sub_steps(step)
      puts "  Step 2: #{step.name} (#{step.sub_steps.count} sub-steps)"
      step
    end

    # rubocop:disable Metrics/MethodLength
    def self.generate_sub_steps(step)
      sub_steps = [
        {
          name: "Overview", position: 1, required: true,
          description: "High-level project overview: purpose, structure, tech stack summary",
          instructions: <<~PROMPT
            You are a technical lead performing initial project reconnaissance.

            **Task:** Produce a high-level overview of the project — what it is, what it does, how it's structured.

            **Context:** You have direct access to the full repository at /workspace/repo/. Start by running:
            - `tree -d -L 2` — directory structure
            - `cloc .` — lines of code summary
            - Review key files: README, package.json, Gemfile, docker-compose.yml, Makefile, etc.

            **Output Format:** Concise markdown overview with:
            - Project name and purpose (what problem it solves)
            - Key technologies (languages, frameworks, databases)
            - High-level architecture (monolith/microservices, frontend/backend split)
            - Directory structure summary
            - How to run/deploy (if evident from configs)

            **Guidelines:**
            - Keep it factual and concise — this is an orientation section, not an assessment
            - Reference specific files as evidence
            - Do NOT assess quality or make recommendations here — that comes in later sections
            - Focus on answering "what is this project and how is it organized?"
          PROMPT
        },
        {
          name: "Static Analysis", position: 2, required: true,
          description: "Codebase metrics, file distribution, language breakdown",
          instructions: <<~PROMPT
            You are a code analysis expert specializing in codebase metrics and structure.

            **Task:** Analyze the repository and generate a comprehensive static analysis report in markdown format.

            **Context:** You have direct access to the repository at /workspace/repo/. Use these tools to gather data:
            - `cloc .` — lines of code by language
            - `cloc --by-file-by-lang .` — detailed per-file breakdown
            - `tree -d -L 3` — directory structure
            - `fd -e rb | wc -l` — count files by extension
            - `rg -l 'class ' --type ruby | wc -l` — count files with patterns

            **Output Format:** Well-structured markdown report with:
            - File distribution table (category, file count, percentage)
            - Language breakdown with line counts and statistics
            - Directory structure analysis
            - Structural insights and observations

            **Guidelines:**
            - Provide quantifiable metrics with file counts, line counts, and percentages
            - Use clear markdown tables for structured data
            - Keep analysis factual and data-driven — every number must come from actual tool output
            - Highlight key patterns and organizational structure
            - Compare ratios (test code vs production code, config vs logic, etc.)
          PROMPT
        },
        {
          name: "Technology Stack", position: 3, required: true,
          description: "Technologies, frameworks, tools inventory grouped by purpose",
          instructions: <<~PROMPT
            You are a technical architect specializing in technology stack assessment.

            **Task:** Identify and document all technologies, frameworks, and tools used in the codebase.

            **Context:** You have direct access to the repository at /workspace/repo/. Examine:
            - Dependency files: package.json, Gemfile, requirements.txt, go.mod, Cargo.toml, pom.xml, etc.
            - Configuration files: docker-compose.yml, Dockerfile, .github/workflows/, CI configs
            - Framework-specific files: config/routes.rb, next.config.js, angular.json, etc.
            - Lock files for exact versions: Gemfile.lock, package-lock.json, yarn.lock

            **Output Format:** Categorized markdown report with:
            - Technologies grouped by purpose (Backend, Frontend, Infrastructure, Data, DevTools)
            - Framework names with versions (from lock files)
            - Primary use cases for each technology

            **Guidelines:**
            - Extract actual versions from lock files, not just dependency declarations
            - Group logically by technology purpose
            - Identify both explicit dependencies and implicit technology usage (e.g., PostgreSQL from database.yml)
            - Note outdated or deprecated dependencies
            - Highlight version conflicts or compatibility concerns
          PROMPT
        },
        {
          name: "Code Quality Summary", position: 4, required: true,
          description: "Code quality audit with severity scoring and recommendations",
          instructions: <<~PROMPT
            You are a code quality auditor specializing in technical debt assessment.

            **Task:** Analyze code quality across the codebase and provide a comprehensive quality summary.

            **Context:** You have direct access to the repository at /workspace/repo/. Analyze quality by:
            - Searching for TODO/FIXME/HACK comments: `rg -c 'TODO|FIXME|HACK|XXX' --type-add 'src:*.{rb,py,ts,tsx,js,jsx,go,rs}' --type src`
            - Finding large files: `fd -e rb -e py -e ts -e tsx -x wc -l {} | sort -rn | head -20`
            - Checking test coverage indicators: test directories, CI configs
            - Looking for code smells: long methods, deep nesting, duplicated patterns

            **Semgrep integration:** A Semgrep scan runs as a separate workflow step. If semgrep_report.json
            is available in inputs, incorporate its findings into your quality assessment — cite severity counts,
            top rule categories, and specific high-severity findings with file paths.

            **Output Format:** Structured markdown with:
            - Overall quality score assessment (1-10)
            - Issue breakdown by severity (🔴 High, 🟡 Medium, 🟢 Low)
            - Top priority fixes with specific file references
            - Quality recommendations with estimated effort
            - Positive highlights

            **Guidelines:**
            - Prioritize high-severity issues with specific file:line citations
            - Include business impact assessment for each issue category
            - Provide actionable recommendations with estimated effort (hours/days)
            - Balance criticism with positive observations
            - Back every claim with evidence (file paths, line counts, tool output)
          PROMPT
        },
        {
          name: "Infrastructure Analysis", position: 5, required: false,
          description: "DevOps, containerization, deployment, monitoring assessment",
          instructions: <<~PROMPT
            You are an infrastructure architect specializing in DevOps and cloud deployments.

            **Task:** Assess infrastructure readiness and generate a comprehensive analysis report.

            **Context:** You have direct access to the repository at /workspace/repo/. Examine:
            - Dockerfiles and docker-compose.yml
            - CI/CD configs: .github/workflows/, .gitlab-ci.yml, Jenkinsfile, etc.
            - Infrastructure as Code: terraform/, k8s/, helm/, etc.
            - Environment configs: .env.example, config/environments/
            - Monitoring/logging setup: prometheus.yml, grafana/, sentry config, etc.
            - Security configs: SSL certs, CORS, CSP headers, secret management

            **Output Format:** Markdown report with scored sections:
            - Containerization assessment (score 1-10, strengths, weaknesses, recommendations)
            - Deployment setup analysis
            - Monitoring and observability evaluation
            - Security posture

            **Guidelines:**
            - Cite specific files and configuration lines as evidence
            - Score each dimension (1-10) with clear justification
            - Focus on security vulnerabilities and operational risks
            - Provide practical, actionable recommendations
            - Flag any hardcoded secrets or credentials immediately
          PROMPT
        },
        {
          name: "Backend Analysis", position: 6, required: true,
          description: "Backend architecture, data layer, API design, security, testing",
          instructions: <<~PROMPT
            You are a senior backend architect specializing in API design and service architecture.

            **Task:** Evaluate backend quality across multiple dimensions.

            **Context:** You have direct access to the repository at /workspace/repo/. Analyze:
            - Architecture: directory structure, service boundaries, dependency graph
            - Data layer: models, migrations, queries, indexes
            - API design: routes, controllers, serializers, error handling
            - Security: authentication, authorization, input validation, CORS
            - Testing: test coverage, test patterns, CI integration

            Use `tree -L 3 app/` (or equivalent) to understand the structure, `cloc` for size metrics, and `rg` for pattern analysis.

            **Output Format:** Markdown report with scored assessments (1-10):
            - Architecture quality
            - Data layer implementation
            - API design
            - Security practices
            - Testing coverage

            Each section: Score → Key Findings → Strengths → Weaknesses → Recommendations

            **Guidelines:**
            - Reference specific files and code patterns as evidence
            - Balance technical assessment with business impact
            - Provide evidence-based scoring — justify every score
            - Focus on practical, prioritized improvements
            - Identify architectural patterns (MVC, DDD, CQRS, etc.) and assess their application
          PROMPT
        },
        {
          name: "Frontend Analysis", position: 7, required: false,
          description: "Frontend architecture, components, styling, state, UX assessment",
          instructions: <<~PROMPT
            You are a senior frontend architect specializing in modern web applications and UX.

            **Task:** Assess frontend quality across architecture, components, styling, state management, and UX.

            **Context:** You have direct access to the repository at /workspace/repo/. Analyze:
            - Component structure: `tree -L 3 src/` or equivalent frontend directory
            - Component size: `fd -e tsx -e jsx -x wc -l {} | sort -rn | head -20`
            - State management patterns, routing, data fetching
            - Styling approach: CSS modules, Tailwind, styled-components, etc.
            - Accessibility: ARIA attributes, semantic HTML, keyboard navigation
            - Bundle configuration: webpack, vite, next.config, etc.

            **Output Format:** Markdown report with scored dimensions (1-10):
            - Frontend architecture
            - Component structure
            - Styling approach
            - State management
            - User experience / accessibility

            Each section: Score → Analysis → Strengths → Weaknesses → Recommendations

            **Guidelines:**
            - Connect weaknesses to UX impact
            - Evaluate both technical quality and user experience
            - Provide specific, actionable improvements
            - Consider accessibility and performance
            - Check for large components (>300 lines) and suggest decomposition
          PROMPT
        }
      ]

      upsert_sub_steps(step, sub_steps)
    end
    # rubocop:enable Metrics/MethodLength

    def self.format_sub_steps(step)
      sub_steps = [
        {
          name: "Read Inputs", position: 1, required: true,
          description: "Read the template, code report, and optional Semgrep data from /workspace/assets/",
          instructions: <<~PROMPT
            1. Read `/workspace/assets/code_report_template.html` — understand the HTML structure, section placeholders, and styling
            2. Read `/workspace/assets/code_report.md` — identify all sections and their content
            3. Check if `/workspace/assets/semgrep_report.json` exists — if yes, read and parse it
            4. List all available sections that can be populated into the template
          PROMPT
        },
        {
          name: "Populate Template", position: 2, required: true,
          description: "Insert report data into the HTML template and save as code_report.html",
          instructions: <<~PROMPT
            Using the template from sub-step 1:

            1. Take the HTML template as the base document — do not modify its CSS, JS, or layout structure
            2. For each section in code_report.md, convert the Markdown to HTML and insert into the matching template section
            3. Replace placeholders: {{PROJECT_NAME}} with the actual project name, {{DATE}} with today's date
            4. Build a table of contents from the populated sections
            5. If Semgrep data is available, populate the security/static analysis section or add an appendix with:
               - Total findings count and severity breakdown
               - Top rule categories
               - Notable high-severity findings with file paths
            6. Remove or hide any template sections that have no corresponding data
            7. Save the complete HTML to `/workspace/outputs/code_report.html`

            The output must preserve the template's visual design — only data changes, not structure.
          PROMPT
        }
      ]

      upsert_sub_steps(step, sub_steps)
    end

    def self.upsert_sub_steps(step, sub_steps)
      sub_steps.each do |data|
        ss = step.sub_steps.find_or_initialize_by(name: data[:name])
        ss.update!(
          position: data[:position],
          required: data[:required],
          description: data[:description],
          instructions: data[:instructions]
        )
      end
    end
  end
end
