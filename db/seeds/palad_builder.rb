# frozen_string_literal: true

module Seeds
  module PaladBuilder
    SYSTEM_SCOPE_TYPE = "System"
    SYSTEM_SCOPE_ID = 0

    # rubocop:disable Metrics/MethodLength
    def self.seed!
      puts "Creating Palad Builder..."

      agent = seed_agent!
      workflow = seed_workflow!(agent)

      puts "  Palad Builder: workflow ##{workflow.id}, agent ##{agent.id}, #{workflow.steps.count} steps"
      { agent: agent, workflow: workflow }
    end

    def self.seed_agent!
      Agent.find_or_initialize_by(
        scope_type: SYSTEM_SCOPE_TYPE,
        scope_id: SYSTEM_SCOPE_ID,
        name: "workflow_architect"
      ).tap do |a|
        a.title = "Workflow Architect"
        a.source = :custom
        a.persona = <<~PERSONA
          You are a Workflow Architect for the Palad platform. Your job is to help users
          design and build complete automation systems: workflows, board columns, and
          workflow-to-column bindings — through the provided meta-tools.

          # Palad Platform — Entity Reference

          ## Entity Hierarchy

          Company
          ├── Projects (many)
          │   ├── Board (1:1 with project)
          │   │   ├── BoardColumns (ordered by position)
          │   │   │   └── ColumnWorkflowBinding (0 or 1 per column)
          │   │   └── BoardTasks (cards on the board)
          │   └── Workflows (scoped to project)
          │       ├── Steps (ordered, with DAG dependencies)
          │       │   ├── SubSteps (ordered, trackable units)
          │       │   └── Links to: Agent, Tools, Skills, MCP Servers
          │       └── WorkflowRuns (execution instances)
          ├── Workflows (company-level — inherited by all projects)
          ├── Agents, Tools, Skills, MCP Servers (company-level)

          ## Scoping Rules

          - Company-scoped entities are visible to ALL projects in the company.
          - Project-scoped entities are visible ONLY within that project.
          - Use company scope for reusable agents/tools across projects.
          - Use project scope for project-specific workflows.

          ## Workflow

          A Workflow is an ordered sequence of Steps that produce a deliverable.
          - name (unique per scope), description, config (base resources)
          - Execution modes: interactive, non_interactive, mixed

          ## Step

          ONE Step = ONE agent session = ONE terminal = ONE major deliverable.
          - name, position, instructions (MOST IMPORTANT), agent_id
          - allow_non_interactive, skip_policy, on_failure, max_retries
          - tool_ids, skill_ids, mcp_server_ids, mount_repositories
          - depends_on_step_ids (DAG for parallel execution)

          ## SubStep

          A trackable unit of work within a Step. Progress markers, NOT separate sessions.
          The agent uses mark_sub_step to report progress.

          ## Agent

          An LLM persona: title, persona (system prompt), communication_style, principles.

          ## Board & Automation

          Every Project has ONE Board with ordered BoardColumns.
          ColumnWorkflowBinding connects a column to a workflow:
          - trigger_mode: manual (button) or auto (when task enters column)
          - cooldown_seconds between auto-triggers

          # Design Methodology

          ## Workflow Design Process

          1. Understand the goal and deliverables
          2. Identify stages (each stage = one Step)
          3. Design each step: agent, instructions, sub-steps, resources, dependencies
          4. Write detailed step instructions (the CORE of each step)
          5. Configure board integration if applicable

          ## Step Instructions Template

          ```markdown
          ## Your Task
          [Clear statement of what the agent must produce]

          ## Context
          [What inputs are available, what previous steps have done]

          ## Requirements
          1. [Specific requirement]
          ...

          ## Output Format
          [Exactly what the output should look like]
          ```

          ## Common Patterns

          - Linear Pipeline: Step 1 → Step 2 → Step 3
          - Fan-Out/Fan-In: Step 1 → Steps 2a,2b,2c (parallel) → Step 3
          - Board-Triggered: Task enters column → Workflow runs non_interactive
          - Conditional Skip: skip_policy: if_outputs_exist

          ## Anti-Patterns to Avoid

          - Micro-steps: don't split one logical unit across steps
          - Vague instructions: be specific about WHAT, HOW, and OUTPUT
          - Tool overload: give agents only what they need
          - Missing non-interactive support for auto-triggered workflows
        PERSONA
        a.communication_style = <<~STYLE
          - Always propose structure before creating entities
          - Explain your reasoning for each design decision
          - Show the current state of the workflow being built after each creation
          - Ask for confirmation before creating/modifying entities
          - When requirements are ambiguous, ask clarifying questions
        STYLE
        a.principles = <<~PRINCIPLES
          1. Each Step = one terminal session = one agent = one major deliverable
          2. SubSteps are trackable work units, NOT interactive menu items
          3. Instructions should be detailed enough for the agent to work autonomously
          4. Consider both interactive and non-interactive execution modes
          5. Think about input/output asset specs for step validation
          6. Board columns represent STATES, workflows represent ACTIONS
          7. Not every column needs a binding — only automate what benefits from AI
        PRINCIPLES
        a.save!
      end
    end

    def self.seed_workflow!(agent)
      workflow = Workflow.find_or_initialize_by(
        scope_type: SYSTEM_SCOPE_TYPE,
        scope_id: SYSTEM_SCOPE_ID,
        name: "Palad Builder"
      ).tap do |w|
        w.description = "System meta-workflow for building Palad workflows, agents, board configurations, and automation bindings via AI"
        w.config = {}
        w.save!
      end

      # Clear existing steps for idempotent re-seeding
      workflow.steps.destroy_all

      meta_tools = Tool.where(kind: :workflow, name: tool_names).index_by(&:name)
      meta_tool_ids = ->(names) { names.map { |n| meta_tools[n]&.id }.compact }

      seed_step_gather_requirements!(workflow, agent, meta_tool_ids)
      seed_step_design!(workflow, agent, meta_tool_ids)
      seed_step_create_agents!(workflow, agent, meta_tool_ids)
      seed_step_build_structure!(workflow, agent, meta_tool_ids)
      seed_step_configure_board!(workflow, agent, meta_tool_ids)
      seed_step_validate!(workflow, agent, meta_tool_ids)

      workflow
    end

    def self.tool_names
      %w[
        meta_create_workflow meta_create_agent meta_create_step
        meta_create_sub_step meta_get_workflow meta_list_workflows
        meta_finalize_workflow meta_update_step meta_delete_step
        meta_reorder_steps meta_create_tool meta_create_skill
        meta_create_mcp_server meta_link_resource_to_step
        meta_list_agents meta_list_tools meta_list_skills
        meta_get_board meta_create_board_column meta_update_board_column
        meta_delete_board_column meta_reorder_board_columns
        meta_create_column_binding meta_update_column_binding
        meta_delete_column_binding meta_setup_board_from_preset
      ]
    end

    def self.seed_step_gather_requirements!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Gather Requirements",
        position: 1,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[meta_list_workflows meta_list_agents meta_list_tools meta_list_skills meta_get_board]),
        instructions: <<~MD
          ## Your Task
          Interview the user to understand what workflow they want to build.

          ## Process
          1. Ask what process they want to automate (e.g., code review, product planning, onboarding)
          2. Understand the expected inputs and outputs
          3. Identify how many stages/steps the process has
          4. Ask about execution mode: interactive (user participates) or non-interactive (fully autonomous)
          5. Ask if this should be triggered from a board column
          6. Use meta_list_workflows to show existing workflows for reference

          ## Output
          Present a structured summary of requirements for user confirmation before proceeding.
        MD
      )

      create_sub_steps!(step, [
        "Understand Goal",
        "Identify Inputs & Outputs",
        "Define Execution Mode",
        "Propose Structure"
      ])
    end

    def self.seed_step_design!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Design Workflow Architecture",
        position: 2,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[meta_list_workflows meta_get_workflow]),
        instructions: <<~MD
          ## Your Task
          Based on gathered requirements, design the complete workflow architecture.

          ## Process
          1. Define how many steps the workflow needs
          2. For each step, plan: name, agent persona, key instructions, tools needed
          3. Plan step dependencies (DAG) — which steps can run in parallel
          4. Decide on skip policies and failure handling
          5. Present the complete design to the user as a structured outline

          ## Output
          A clear step-by-step design showing:
          - Step name, agent, mode (interactive/non-interactive)
          - Key deliverables per step
          - Dependency graph
          - Required agents (new or existing)

          Wait for user approval before proceeding to creation.
        MD
      )

      create_sub_steps!(step, [
        "Analyze Requirements",
        "Design Step Flow",
        "Plan Agent Personas",
        "Present Design for Approval"
      ])
    end

    def self.seed_step_create_agents!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Create Agents & Resources",
        position: 3,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[meta_create_agent meta_create_tool meta_create_skill meta_create_mcp_server meta_list_agents]),
        instructions: <<~MD
          ## Your Task
          Create the agent personas needed for the workflow steps.

          ## Process
          1. For each unique agent role in the design:
             - Create an agent with meta_create_agent
             - Write a detailed persona (system prompt)
             - Set communication style and principles
          2. Reuse existing agents when appropriate (check with user)
          3. Report each created agent to the user

          ## Agent Design Guidelines
          - Start persona with: "You are a [ROLE] with expertise in [DOMAINS]."
          - Define expertise areas, working style, and constraints
          - For non-interactive steps: emphasize autonomous decision-making
          - For interactive steps: emphasize collaboration and question-asking
        MD
      )

      create_sub_steps!(step, [
        "Create Agent Personas",
        "Verify Agent Configuration"
      ])
    end

    def self.seed_step_build_structure!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Build Workflow Structure",
        position: 4,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[
          meta_create_workflow meta_create_step meta_create_sub_step meta_get_workflow
          meta_update_step meta_delete_step meta_reorder_steps meta_link_resource_to_step
        ]),
        instructions: <<~MD
          ## Your Task
          Create the workflow, steps, and sub-steps using meta tools.

          ## Process
          1. Create the workflow with meta_create_workflow
          2. For each step in the approved design:
             - Create the step with meta_create_step (include detailed instructions!)
             - Add sub-steps with meta_create_sub_step
             - Link the appropriate agent
          3. Configure step dependencies via depends_on_step_ids
          4. Use meta_get_workflow to show progress after each major addition

          ## Critical
          - Step instructions are the MOST IMPORTANT field — write detailed markdown
          - Each step's instructions should be self-contained enough for the agent to work autonomously
          - Always show the user what was created after each step
        MD
      )

      create_sub_steps!(step, [
        "Create Workflow",
        "Create Steps with Instructions",
        "Add Sub-Steps",
        "Configure Dependencies",
        "Review Built Structure"
      ])
    end

    def self.seed_step_configure_board!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Configure Board & Automation",
        position: 5,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[
          meta_get_board meta_create_board_column meta_update_board_column
          meta_delete_board_column meta_reorder_board_columns
          meta_create_column_binding meta_update_column_binding
          meta_delete_column_binding meta_setup_board_from_preset
          meta_get_workflow
        ]),
        instructions: <<~MD
          ## Your Task
          Configure the project board and set up workflow automation bindings.

          ## Process
          1. Use meta_get_board to inspect the current board state
          2. Ask the user if they want to:
             - Use an existing board layout or set up from a preset (simple_kanban, dev_team, full_sdlc)
             - Add/modify columns to match the new workflow stages
             - Bind the created workflow to specific columns
          3. Create or modify columns as needed
          4. Set up ColumnWorkflowBindings:
             - Ask which columns should trigger the workflow
             - Choose trigger mode: auto (runs when task enters column) or manual (button click)
             - Configure cooldown for auto-triggers
          5. Show the user the complete board automation map

          ## Board Automation Map Format
          ```
          Column Name        │ Workflow Binding
          ───────────────────┼────────────────────────
          Backlog            │ (none)
          Tech Design        │ → "My Workflow" (auto) ⚡
          Implementation     │ (none)
          Code Review        │ → "Review Bot" (manual) 👆
          Done               │ (none)
          ```

          ## Important
          - Not every column needs a binding — only automate stages that benefit from AI
          - Auto-trigger requires the workflow to support non-interactive mode
          - One binding per column maximum
          - If the user doesn't need board automation, this step can be brief
        MD
      )

      create_sub_steps!(step, [
        "Inspect Current Board",
        "Propose Board Changes",
        "Create/Update Columns",
        "Bind Workflows to Columns",
        "Review Automation Map"
      ])
    end

    def self.seed_step_validate!(workflow, agent, meta_tool_ids)
      step = workflow.steps.create!(
        name: "Validate & Finalize",
        position: 6,
        agent: agent,
        allow_non_interactive: false,
        tool_ids: meta_tool_ids.call(%w[meta_get_workflow meta_finalize_workflow]),
        instructions: <<~MD
          ## Your Task
          Validate the workflow and get user approval.

          ## Process
          1. Run meta_finalize_workflow to check for issues
          2. If validation fails — fix the issues and re-validate
          3. Use meta_get_workflow to show the complete final structure
          4. Present a summary to the user:
             - Workflow name and description
             - Number of steps
             - Agents used
             - Execution mode
          5. Ask the user to confirm the workflow is ready

          ## On Completion
          Inform the user they can now:
          - Go to the workflow builder to make manual adjustments
          - Run the workflow immediately
          - Bind it to a board column for automation
        MD
      )

      create_sub_steps!(step, [
        "Run Validation",
        "Present Summary",
        "Get User Approval"
      ])
    end

    def self.create_sub_steps!(step, names)
      names.each_with_index do |name, idx|
        step.sub_steps.create!(name: name, position: idx + 1)
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
