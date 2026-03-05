# System Workflow: BMAD Method Integration

**Date:** 2026-03-02
**Status:** Draft / RFC
**Author:** Artem Petrov + AI Analysis
**Depends on:** [workflow-architecture.md](./workflow-architecture.md), [meta-workflow-design.md](./meta-workflow-design.md), [BMAD-structure-description.md](./BMAD-structure-description.md)

---

## 1. Goal and motivation

### 1.1 Problem

The BMAD method (v6) is an aggregate of agents and workflows for the full cycle of product development (analysis → planning → architecture → implementation). Currently BMAD works as a set of prompts in the IDE: each workflow is launched manually via a command, context is lost between sessions, and there is no orchestration between phases.

Palad is already a **persistent BMAD runtime** at the level of individual workflows (one BMAD workflow = one Palad Step). But there is no mechanism that:
1. Runs the **full cycle** of the BMAD method as a single managed process
2. **Maps** BMAD agents and configuration into Palad entities
3. Allows **reuse** of new BMAD modules (bmb, cis, future npm packages)
4. Differs from ordinary workflows by having **custom mappings**

### 1.2 Goal

Create a **System Workflow** — a special type of workflow that:
- Orchestrates the BMAD method as a whole (or a subset of it chosen by the user)
- Automatically maps BMAD artifacts (agents, workflows, config vars) into Palad entities
- Supports modularity: install a new BMAD module → its workflows become available in the system workflow
- Is the "single source of truth" for the configuration of the BMAD environment in Palad

### 1.3 How a System Workflow differs from an ordinary one

| Ordinary Workflow | System Workflow |
|---|---|
| Created by the user | Shipped with the platform or generated from BMAD modules |
| Fixed set of Steps | Dynamic: Steps are determined from the BMAD module catalog |
| Agents bound by hand | Agents are mapped automatically from BMAD agent definitions |
| Config via UI | Config includes the BMAD config layer (config.yaml vars) |
| `scope: Project / Company` | `scope: System` (visible to everyone, not editable) |
| No knowledge of external methodologies | Knows the BMAD structure (phases, modules, dependencies) |

---

## 2. Architecture

### 2.1 Three levels

```
┌───────────────────────────────────────────────────────────────────────────┐
│  Level 3: System Workflow "BMAD Full Lifecycle"                            │
│                                                                           │
│  An orchestrator that knows about BMAD phases and offers the user        │
│  to compose a path from the available workflows. It can include steps from different │
│  modules (bmm, cis, bmb).                                                │
├───────────────────────────────────────────────────────────────────────────┤
│  Level 2: BMAD Module Catalog (Registry)                                  │
│                                                                           │
│  A catalog of all imported BMAD modules with their agents, workflows.     │
│  Each workflow from the catalog = a ready-made template for a Palad Step. │
│  The Registry knows the dependencies between workflows (PRD is needed for Architecture).│
├───────────────────────────────────────────────────────────────────────────┤
│  Level 1: Palad Runtime (existing)                                        │
│                                                                           │
│  Workflow → Step → SubStep                                                │
│  WorkflowRun → StepRun → SubStepRun                                     │
│  TerminalSession, Agent, Tools, Skills, MCP Servers                      │
└───────────────────────────────────────────────────────────────────────────┘
```

### 2.2 BMAD Module Registry

The central component is the registry of imported BMAD modules:

```ruby
class BmadModule < ApplicationRecord
  belongs_to :company
  has_many :bmad_agents, dependent: :destroy
  has_many :bmad_workflows, dependent: :destroy

  # name: string ("bmm", "cis", "bmb")
  # version: string ("6.0.1")
  # source: string ("built-in", "npm:bmad-method", "npm:bmad-creative-intelligence-suite")
  # config: jsonb (parsed module config.yaml)
  # manifest: jsonb (parsed module manifest — lists of agents, workflows, teams)
  # installed_at: datetime
  # updated_at: datetime
end

class BmadAgent < ApplicationRecord
  belongs_to :bmad_module
  belongs_to :palad_agent, class_name: 'Agent', optional: true

  # bmad_name: string ("analyst", "architect", "pm")
  # display_name: string ("Mary", "Winston", "John")
  # title: string ("Business Analyst", "Architect", "Product Manager")
  # role: text
  # persona: text (full persona from BMAD agent file)
  # communication_style: text
  # principles: text
  # capabilities: string
  # source_path: string ("_bmad/bmm/agents/analyst.md")
  # source_hash: string (for tracking changes)
end

class BmadWorkflow < ApplicationRecord
  belongs_to :bmad_module
  has_many :bmad_workflow_steps, dependent: :destroy, order: :position

  # bmad_name: string ("create-product-brief", "create-architecture")
  # description: text
  # phase: string ("1-analysis", "2-planning", "3-solutioning", "4-implementation")
  # category: string ("research", "planning", "solutioning", "implementation", "quick-flow", "qa")
  # agent_name: string ("analyst", "architect") — which BMAD agent runs this
  # source_path: string ("_bmad/bmm/workflows/3-solutioning/create-architecture/workflow.md")
  # workflow_type: string ("step-file", "yaml-config")
  # config: jsonb (parsed workflow.yaml or workflow.md frontmatter)
  # depends_on: string[] (other bmad_workflow names this depends on)
  # produces: string[] (artifact names this produces)
  # requires: string[] (artifact names this needs as input)
end

class BmadWorkflowStep < ApplicationRecord
  belongs_to :bmad_workflow

  # position: integer
  # name: string ("step-01-init", "step-02-discovery")
  # source_path: string (path to step file)
  # description: text (extracted from step file)
end
```

### 2.3 Mapping Engine

Mapping Engine — a service that translates BMAD entities into Palad entities:

```
┌─────────────────┐        ┌──────────────────┐        ┌─────────────────┐
│  BMAD Source     │        │  Mapping Engine   │        │  Palad Entities │
│                  │        │                   │        │                 │
│ BmadAgent        │───────▶│ AgentMapper       │───────▶│ Agent           │
│  analyst.md      │        │  - persona → sys  │        │  system_prompt  │
│  persona, role   │        │    prompt          │        │  principles     │
│                  │        │  - principles      │        │  comm_style     │
│                  │        │  - comm_style      │        │                 │
├─────────────────┤        ├──────────────────┤        ├─────────────────┤
│ BmadWorkflow     │───────▶│ WorkflowMapper    │───────▶│ Workflow        │
│  create-arch     │        │  - workflow →     │        │  Steps          │
│  steps/          │        │    Palad Workflow  │        │  SubSteps       │
│  instructions    │        │  - BMAD steps →   │        │  instructions   │
│                  │        │    Palad SubSteps  │        │  agent_id       │
├─────────────────┤        ├──────────────────┤        ├─────────────────┤
│ BmadModule       │───────▶│ ConfigMapper      │───────▶│ WorkflowRun     │
│  config.yaml     │        │  - config vars → │        │  shared_context  │
│  project_name    │        │    shared_context │        │  (BMAD vars)    │
│  output_folder   │        │  - paths →       │        │                 │
│                  │        │    workspace dirs  │        │                 │
└─────────────────┘        └──────────────────┘        └─────────────────┘
```

### 2.4 Custom mappings (the key difference)

A System Workflow contains a **mapping configuration** — translation rules that ordinary workflows do not have:

```ruby
class SystemWorkflowMapping < ApplicationRecord
  belongs_to :workflow  # system workflow

  # mapping_type: enum
  #   :agent_mapping      — BmadAgent → Agent
  #   :config_mapping     — BMAD config var → shared_context key
  #   :artifact_mapping   — BMAD artifact name → WorkflowRunAsset name pattern
  #   :phase_mapping      — BMAD phase → Step group
  #   :instruction_transform — rules for adapting BMAD instructions to Palad context

  # source_ref: string (BMAD-side reference, e.g. "bmm:analyst" or "config:output_folder")
  # target_ref: string (Palad-side reference, e.g. "agent:42" or "shared_context.bmad_output_folder")
  # transform: jsonb (transformation rules, if any)
  # auto_sync: boolean (re-apply mapping when BMAD module updates)
end
```

#### 2.4.1 Agent Mapping

BMAD agents → Palad agents:

```ruby
class BmadAgentMapper
  PERSONA_TRANSFORM = {
    role: :persona,
    identity: :system_prompt_identity_section,
    communication_style: :communication_style,
    principles: :principles,
    capabilities: :description
  }

  def map(bmad_agent, target_scope:)
    existing = bmad_agent.palad_agent

    attrs = {
      title: bmad_agent.title,
      description: "#{bmad_agent.title} — #{bmad_agent.capabilities}",
      persona: build_persona(bmad_agent),
      communication_style: bmad_agent.communication_style,
      principles: bmad_agent.principles,
      source: :bmad_import,
      source_ref: "#{bmad_agent.bmad_module.name}:#{bmad_agent.bmad_name}",
      scope: target_scope
    }

    if existing
      existing.update!(attrs) if bmad_agent.source_hash_changed?
      existing
    else
      agent = Agent.create!(attrs)
      bmad_agent.update!(palad_agent: agent)
      agent
    end
  end

  private

  def build_persona(bmad_agent)
    <<~PROMPT
      You are #{bmad_agent.display_name}, #{bmad_agent.title}.

      ## Role
      #{bmad_agent.role}

      ## Communication Style
      #{bmad_agent.communication_style}

      ## Principles
      #{bmad_agent.principles}
    PROMPT
  end
end
```

#### 2.4.2 Config Mapping

BMAD config.yaml → Palad WorkflowRun shared_context:

```ruby
class BmadConfigMapper
  STANDARD_MAPPINGS = {
    'project_name' => 'bmad.project_name',
    'user_name' => 'bmad.user_name',
    'communication_language' => 'bmad.communication_language',
    'document_output_language' => 'bmad.document_output_language',
    'user_skill_level' => 'bmad.user_skill_level',
    'output_folder' => 'bmad.output_folder',
    'planning_artifacts' => 'bmad.planning_artifacts',
    'implementation_artifacts' => 'bmad.implementation_artifacts',
    'project_knowledge' => 'bmad.project_knowledge'
  }.freeze

  def map(bmad_module, workflow_run:)
    config = bmad_module.config
    context = workflow_run.shared_context || {}

    STANDARD_MAPPINGS.each do |bmad_key, palad_key|
      value = config[bmad_key]
      next unless value

      value = resolve_path(value, workflow_run.project)
      deep_set(context, palad_key, value)
    end

    workflow_run.update!(shared_context: context)
  end

  private

  def resolve_path(value, project)
    value
      .gsub('{project-root}', '/workspace')
      .gsub('{config_source}', '/workspace/_bmad/bmm/config.yaml')
  end
end
```

#### 2.4.3 Instruction Transform

BMAD workflow instructions → Palad Step instructions:

```ruby
class BmadInstructionTransformer
  def transform(bmad_workflow, step)
    original = bmad_workflow.raw_instructions

    transformed = original
      .then { |text| strip_bmad_activation(text) }
      .then { |text| replace_path_variables(text) }
      .then { |text| inject_palad_context_refs(text) }
      .then { |text| adapt_menu_handling(text) }

    step.update!(instructions: build_step_instructions(bmad_workflow, transformed))
  end

  private

  def strip_bmad_activation(text)
    # BMAD agents have <activation> blocks that handle config loading,
    # greeting, menu display. In Palad, this is handled by SessionContextConstructor.
    # Strip activation blocks and replace with Palad-native context reference.
    text.gsub(/<activation.*?<\/activation>/m, '')
  end

  def replace_path_variables(text)
    text
      .gsub('{project-root}', '/workspace')
      .gsub('{output_folder}', '/workspace/output')
      .gsub('{planning_artifacts}', '/workspace/input/planning')
      .gsub('{implementation_artifacts}', '/workspace/input/implementation')
  end

  def inject_palad_context_refs(text)
    # Add Palad-specific instructions at the top
    palad_header = <<~MD
      ## Palad Integration Notes
      - Your workflow context (previous steps, sub-steps) is in the WORKFLOW CONTEXT section above
      - Use `mark_sub_step` to track progress
      - Save outputs to `/workspace/output/`
      - Previous step outputs are in `/workspace/input/`

    MD
    palad_header + text
  end

  def adapt_menu_handling(text)
    # BMAD workflows in IDE present interactive menus (A/P/C).
    # In Palad interactive mode, these are preserved as-is (agent presents them in terminal).
    # In Palad non-interactive mode, default choices are auto-selected.
    text
  end
end
```

---

## 3. BMAD Module Import Flow

### 3.1 How modules get into the system

```
┌─────────────────────────────────────────────────────────────────────┐
│  Import Sources                                                      │
│                                                                      │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ _bmad/ folder │  │ npm package      │  │ Git repository       │  │
│  │ (in project)  │  │ (bmad-method,    │  │ (custom module)      │  │
│  │               │  │  bmad-creative-  │  │                      │  │
│  │               │  │  intelligence)   │  │                      │  │
│  └──────┬───────┘  └────────┬─────────┘  └──────────┬───────────┘  │
│         │                   │                        │              │
│         ▼                   ▼                        ▼              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  BmadModuleImporter                                          │   │
│  │                                                              │   │
│  │  1. Scan source (manifest.yaml, config.yaml)                │   │
│  │  2. Parse agent files (.md with YAML frontmatter)           │   │
│  │  3. Parse workflow files (workflow.md / workflow.yaml)       │   │
│  │  4. Parse step files (steps/step-*.md)                      │   │
│  │  5. Extract dependencies (requires/produces)                 │   │
│  │  6. Create BmadModule + BmadAgents + BmadWorkflows          │   │
│  │  7. Run AgentMapper → create/update Palad Agents            │   │
│  │  8. Build dependency graph between workflows                 │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Import service

```ruby
class BmadModuleImporter
  def import(company:, source_path:)
    manifest = parse_manifest(source_path)
    config = parse_config(source_path, manifest[:name])

    bmad_module = BmadModule.find_or_initialize_by(
      company: company,
      name: manifest[:name]
    )
    bmad_module.assign_attributes(
      version: manifest[:version],
      source: detect_source(source_path),
      config: config,
      manifest: manifest
    )
    bmad_module.save!

    import_agents(bmad_module, source_path)
    import_workflows(bmad_module, source_path)
    build_dependency_graph(bmad_module)

    bmad_module
  end

  private

  def import_agents(bmad_module, source_path)
    agent_files = Dir.glob("#{source_path}/agents/**/*.md")
    agent_files.each do |file|
      parsed = BmadAgentParser.parse(file)
      BmadAgent.find_or_create_by!(
        bmad_module: bmad_module,
        bmad_name: parsed[:name]
      ).update!(
        display_name: parsed[:display_name],
        title: parsed[:title],
        role: parsed[:role],
        persona: parsed[:persona],
        communication_style: parsed[:communication_style],
        principles: parsed[:principles],
        capabilities: parsed[:capabilities],
        source_path: file,
        source_hash: Digest::SHA256.file(file).hexdigest
      )
    end
  end

  def import_workflows(bmad_module, source_path)
    workflow_manifest = CSV.parse(
      File.read("#{source_path}/../_config/workflow-manifest.csv"),
      headers: true
    )

    workflow_manifest.select { |w| w['module'] == bmad_module.name }.each do |entry|
      wf_path = "#{source_path}/../#{entry['path']}"
      parsed = BmadWorkflowParser.parse(wf_path)

      bw = BmadWorkflow.find_or_create_by!(
        bmad_module: bmad_module,
        bmad_name: entry['name']
      )
      bw.update!(
        description: entry['description'],
        phase: detect_phase(entry['path']),
        category: detect_category(entry['path']),
        agent_name: parsed[:agent_name],
        source_path: entry['path'],
        workflow_type: parsed[:type],
        config: parsed[:config],
        produces: parsed[:produces],
        requires: parsed[:requires]
      )

      import_workflow_steps(bw, parsed[:steps_path]) if parsed[:steps_path]
    end
  end

  def build_dependency_graph(bmad_module)
    # Analyze requires/produces to build the dependency graph
    bmad_module.bmad_workflows.each do |wf|
      deps = bmad_module.bmad_workflows.select do |other|
        wf.requires.present? &&
        other.produces.present? &&
        (wf.requires & other.produces).any?
      end
      wf.update!(depends_on: deps.map(&:bmad_name))
    end
  end
end
```

### 3.3 Parsing BMAD artifacts

#### Agent Parser

```ruby
class BmadAgentParser
  def self.parse(file_path)
    content = File.read(file_path)
    frontmatter = YAML.safe_load(content.match(/---\n(.*?)\n---/m)&.[](1) || '{}')

    # Extract from XML-embedded persona
    xml_content = content.match(/<agent.*?>(.*?)<\/agent>/m)&.[](1) || ''

    {
      name: frontmatter['name'],
      display_name: extract_xml_attr(content, 'agent', 'name'),
      title: extract_xml_attr(content, 'agent', 'title'),
      role: extract_xml_section(xml_content, 'role'),
      persona: extract_xml_section(xml_content, 'identity'),
      communication_style: extract_xml_section(xml_content, 'communication-style'),
      principles: extract_xml_section(xml_content, 'principles'),
      capabilities: extract_xml_attr(content, 'agent', 'capabilities')
    }
  end
end
```

#### Workflow Parser

```ruby
class BmadWorkflowParser
  def self.parse(file_path)
    content = File.read(file_path)

    if file_path.end_with?('.yaml')
      parse_yaml_workflow(content, file_path)
    else
      parse_md_workflow(content, file_path)
    end
  end

  def self.parse_md_workflow(content, file_path)
    frontmatter = YAML.safe_load(content.match(/---\n(.*?)\n---/m)&.[](1) || '{}')
    dir = File.dirname(file_path)
    steps_dir = "#{dir}/steps"

    steps = if Dir.exist?(steps_dir)
              Dir.glob("#{steps_dir}/step-*.md").sort.map.with_index do |f, i|
                { position: i + 1, name: File.basename(f, '.md'), source_path: f }
              end
            else
              []
            end

    {
      name: frontmatter['name'],
      type: 'step-file',
      agent_name: detect_agent_from_content(content),
      config: frontmatter,
      steps_path: steps_dir,
      steps: steps,
      produces: detect_outputs(content),
      requires: detect_inputs(content)
    }
  end

  def self.parse_yaml_workflow(content, file_path)
    config = YAML.safe_load(content)
    {
      name: config['name'],
      type: 'yaml-config',
      agent_name: nil,
      config: config,
      steps_path: nil,
      steps: [],
      produces: detect_yaml_outputs(config),
      requires: detect_yaml_inputs(config)
    }
  end
end
```

---

## 4. System Workflow: Structure and Execution

### 4.1 Two types of System Workflows

#### Type A: BMAD Phase Workflow (pre-built)

One system workflow = one BMAD phase. Created automatically when a module is imported.

```
System Workflow: "BMM: Analysis Phase"
  Step 1: "Domain Research" → BmadWorkflow(domain-research), Agent: analyst
  Step 2: "Market Research" → BmadWorkflow(market-research), Agent: analyst  
  Step 3: "Technical Research" → BmadWorkflow(technical-research), Agent: analyst
  Step 4: "Create Product Brief" → BmadWorkflow(create-product-brief), Agent: analyst

System Workflow: "BMM: Planning Phase"
  Step 1: "Create PRD" → BmadWorkflow(create-prd), Agent: pm
  Step 2: "Create UX Design" → BmadWorkflow(create-ux-design), Agent: ux-designer

System Workflow: "BMM: Solutioning Phase"
  Step 1: "Create Architecture" → BmadWorkflow(create-architecture), Agent: architect
  Step 2: "Create Epics & Stories" → BmadWorkflow(create-epics-and-stories), Agent: pm/sm
  Step 3: "Check Readiness" → BmadWorkflow(check-implementation-readiness), Agent: architect

System Workflow: "BMM: Implementation Phase"
  Step 1: "Sprint Planning" → BmadWorkflow(sprint-planning), Agent: sm
  Step 2: "Create Story" → BmadWorkflow(create-story), Agent: sm
  Step 3: "Dev Story" → BmadWorkflow(dev-story), Agent: dev
  Step 4: "Code Review" → BmadWorkflow(code-review), Agent: dev
  Step 5: "Retrospective" → BmadWorkflow(retrospective), Agent: sm
```

#### Type B: BMAD Composite Workflow (user-assembled)

The user assembles their own path from the catalog of available BMAD workflows:

```
Custom System Workflow: "My Product Launch Process"
  Step 1: "Research" → from BMM/1-analysis/research
  Step 2: "Product Brief" → from BMM/1-analysis/create-product-brief
  Step 3: "PRD" → from BMM/2-planning/create-prd
  Step 4: "Architecture" → from BMM/3-solutioning/create-architecture
  Step 5: "Brainstorming" → from CIS/brainstorming   ← cross-module!
  Step 6: "Epics" → from BMM/3-solutioning/create-epics-and-stories
```

### 4.2 System Workflow Model

```ruby
class Workflow < ApplicationRecord
  # Existing fields...

  # New fields for system workflows:
  # scope_type: string (Company, Project, System)
  # system_workflow_type: string (nil, "bmad_phase", "bmad_composite", "meta")
  # bmad_module_id: integer (optional — for auto-generated phase workflows)

  has_many :system_workflow_mappings, dependent: :destroy

  def system_workflow?
    scope_type == 'System'
  end

  def bmad_workflow?
    system_workflow_type.in?(%w[bmad_phase bmad_composite])
  end
end
```

### 4.3 Step ↔ BmadWorkflow Link

```ruby
class Step < ApplicationRecord
  # Existing fields...

  # New field:
  # bmad_workflow_id: integer (optional — links this step to a BMAD workflow definition)
  belongs_to :bmad_workflow, optional: true

  def bmad_step?
    bmad_workflow_id.present?
  end
end
```

When a Step is bound to a BmadWorkflow, on StepRun launch:
1. BMAD workflow instructions are injected into the agent context
2. BMAD step files → SubSteps
3. BMAD config vars → available via shared_context
4. BMAD agent → the mapped Agent is selected automatically

### 4.4 Execution Flow

```
The user selects a System Workflow (e.g. "BMM: Solutioning Phase")
    │
    ├─→ The UI shows steps with descriptions from BMAD
    ├─→ The user can skip/reorder steps (if skip_policy allows)
    ├─→ The user selects input assets and mode
    │
    ▼
A WorkflowRun is created
    │
    ├─→ BmadConfigMapper injects BMAD config vars into shared_context
    │   {
    │     "bmad": {
    │       "project_name": "my-app",
    │       "communication_language": "Russian",
    │       "document_output_language": "English",
    │       "user_skill_level": "expert"
    │     }
    │   }
    │
    ▼
Step 1: "Create Architecture"
    │
    ├─→ step.bmad_workflow → loads BmadWorkflow(create-architecture)
    │
    ├─→ BmadWorkflow.bmad_workflow_steps → creates SubStepRuns:
    │     1. step-01-init
    │     2. step-02-load-docs
    │     3. step-03-context-analysis
    │     4. step-04-decisions
    │     5. step-05-patterns
    │     6. step-06-project-structure
    │     7. step-07-validation
    │
    ├─→ Agent: mapped architect → Palad Agent "Winston" (auto-selected via mapping)
    │
    ├─→ SessionContextConstructor builds context:
    │     ┌─────────────────────────────────────┐
    │     │  AGENTS.md                            │
    │     │                                       │
    │     │  ## Agent: Winston (Architect)         │
    │     │  [persona from mapped Agent]          │
    │     │                                       │
    │     │  ## BMAD Configuration                │
    │     │  project_name: my-app                 │
    │     │  communication_language: Russian       │
    │     │  document_output_language: English     │
    │     │                                       │
    │     │  ## Workflow Context                   │
    │     │  [standard Palad workflow context]     │
    │     │                                       │
    │     │  ## Step Instructions                  │
    │     │  [transformed BMAD instructions]       │
    │     │  [references to step files in          │
    │     │   /workspace/input/_bmad/...]          │
    │     └─────────────────────────────────────┘
    │
    ├─→ /workspace/input/ contains:
    │     _bmad/bmm/workflows/3-solutioning/create-architecture/  (step files)
    │     _bmad/bmm/config.yaml
    │     prd.md (from previous step output)
    │     product-brief.md (from previous step output)
    │
    ▼
Agent runs in container, follows BMAD instructions natively
    │
    ├─→ Agent reads step files, follows BMAD workflow
    ├─→ Uses mark_sub_step to report progress
    ├─→ Saves output to /workspace/output/architecture.md
    │
    ▼
Step completes → next step starts
```

---

## 5. Context Builder: BMAD Layer

### 5.1 New Context Builder

```ruby
module ContextBuilders
  class BmadContext
    def initialize(step_run)
      @step_run = step_run
      @workflow_run = step_run.workflow_run
      @step = step_run.step
    end

    def applicable?
      @step.bmad_step?
    end

    def build
      return '' unless applicable?

      sections = []
      sections << bmad_config_section
      sections << bmad_workflow_instructions_section
      sections << bmad_artifacts_reference_section
      sections.compact.join("\n\n")
    end

    private

    def bmad_config_section
      config = @workflow_run.shared_context&.dig('bmad')
      return nil unless config.present?

      lines = ["## BMAD Configuration"]
      config.each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines.join("\n")
    end

    def bmad_workflow_instructions_section
      bw = @step.bmad_workflow
      return nil unless bw

      <<~MD
        ## BMAD Workflow: #{bw.bmad_name}
        #{bw.description}

        ### Instructions
        Follow the workflow defined in the BMAD workflow files mounted at:
        `/workspace/input/_bmad/#{bw.source_path}`

        The step files are sequential. Process them in order.
        Use `mark_sub_step` to report progress on each step file.
      MD
    end

    def bmad_artifacts_reference_section
      bw = @step.bmad_workflow
      return nil unless bw

      requires = bw.requires
      return nil unless requires.present?

      lines = ["## Required Input Artifacts"]
      requires.each do |artifact_name|
        lines << "- #{artifact_name} (check /workspace/input/ for this file)"
      end
      lines.join("\n")
    end
  end
end
```

### 5.2 Integration into SessionContextConstructor

```ruby
class SessionContextConstructor
  BUILDERS = [
    ContextBuilders::CriticalRules,
    ContextBuilders::AgentRole,
    ContextBuilders::SessionInfo,
    ContextBuilders::Workspace,
    ContextBuilders::WorkflowContext,
    ContextBuilders::BmadContext,      # ← NEW: added after WorkflowContext
    ContextBuilders::BoardContext,
    ContextBuilders::Tools,
    ContextBuilders::Resources,
    ContextBuilders::OutputRules,
  ].freeze
end
```

---

## 6. BMAD Module Extensibility

### 6.1 Installing a new module

```
The user (admin) → Settings → BMAD Modules → "Install Module"
    │
    ├─→ Option 1: "Import from project" → scans _bmad/ in the project repository
    ├─→ Option 2: "Install from npm" → npm install bmad-creative-intelligence-suite
    ├─→ Option 3: "Import from URL" → git clone custom module
    │
    ▼
BmadModuleImporter.import(company: current_company, source_path: path)
    │
    ├─→ Creates BmadModule
    ├─→ Creates BmadAgents → maps to Palad Agents
    ├─→ Creates BmadWorkflows → available in System Workflow catalog
    ├─→ Builds dependency graph
    │
    ▼
New workflows appear in:
  - System Workflow builder (for creating composite workflows)
  - Phase-based auto-generated System Workflows
  - BMAD Module catalog (for browsing)
```

### 6.2 Updating a module

```ruby
class BmadModuleUpdater
  def update(bmad_module, new_source_path:)
    old_version = bmad_module.version
    importer = BmadModuleImporter.new

    ActiveRecord::Base.transaction do
      importer.import(
        company: bmad_module.company,
        source_path: new_source_path
      )

      # Re-map agents if source_hash changed
      bmad_module.bmad_agents.each do |ba|
        if ba.source_hash_changed?
          BmadAgentMapper.new.map(ba, target_scope: bmad_module.company)
        end
      end

      # Re-generate system workflows if workflow structure changed
      regenerate_phase_workflows(bmad_module) if workflows_changed?(bmad_module)
    end

    notify_update(bmad_module, old_version)
  end
end
```

### 6.3 Future BMAD modules

When BMAD builds an extensible module system, our architecture is ready:

```
npm install bmad-security-module

→ BmadModuleImporter detects:
   - config.yaml with the security module settings
   - agents/: security-auditor.md, penetration-tester.md
   - workflows/: vulnerability-scan/, compliance-check/, threat-model/

→ Automatically creates:
   - BmadModule(name: "security")
   - BmadAgent → Agent(title: "Security Auditor", ...)
   - BmadAgent → Agent(title: "Penetration Tester", ...)
   - BmadWorkflow(vulnerability-scan, compliance-check, threat-model)
   - System Workflow: "Security: Full Audit" (auto-generated phase workflow)

→ The user can:
   - Run "Security: Full Audit" as a system workflow
   - Add a "vulnerability-scan" step to their composite workflow
   - Use the security-auditor agent in a standalone session
```

---

## 7. UI

### 7.1 BMAD Module Management

```
┌─────────────────────────────────────────────────────────────────────┐
│  Settings → BMAD Modules                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ 📦 BMM (BMAD Method Module)                  v6.0.1     │       │
│  │    Source: built-in                                       │       │
│  │    Agents: 10 (analyst, architect, pm, dev, ...)         │       │
│  │    Workflows: 22                                          │       │
│  │    [View Details] [Update] [Re-import]                   │       │
│  ├──────────────────────────────────────────────────────────┤       │
│  │ 📦 CIS (Creative Intelligence Suite)         v0.1.6     │       │
│  │    Source: npm:bmad-creative-intelligence-suite           │       │
│  │    Agents: 6 (brainstorming-coach, storyteller, ...)     │       │
│  │    Workflows: 4                                           │       │
│  │    [View Details] [Update] [Re-import]                   │       │
│  ├──────────────────────────────────────────────────────────┤       │
│  │ 📦 BMB (BMAD Builder)                        v0.1.6     │       │
│  │    Source: npm:bmad-builder                               │       │
│  │    Agents: 3 (agent-builder, module-builder, ...)        │       │
│  │    Workflows: 11                                          │       │
│  │    [View Details] [Update] [Re-import]                   │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  [+ Install Module]                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 System Workflow Catalog

```
┌─────────────────────────────────────────────────────────────────────┐
│  Workflows → System Workflows                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  📋 BMAD Method Phases                                               │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ 🔍 Analysis Phase              4 steps | BMM             │       │
│  │    Research → Product Brief                               │       │
│  │    [Run] [Customize]                                      │       │
│  ├──────────────────────────────────────────────────────────┤       │
│  │ 📋 Planning Phase              2 steps | BMM             │       │
│  │    PRD → UX Design                                        │       │
│  │    [Run] [Customize]                                      │       │
│  ├──────────────────────────────────────────────────────────┤       │
│  │ 🏗️ Solutioning Phase           3 steps | BMM             │       │
│  │    Architecture → Epics → Readiness Check                 │       │
│  │    [Run] [Customize]                                      │       │
│  ├──────────────────────────────────────────────────────────┤       │
│  │ 💻 Implementation Phase        5 steps | BMM             │       │
│  │    Sprint Planning → Story → Dev → Review → Retro         │       │
│  │    [Run] [Customize]                                      │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  🎨 Creative Intelligence Suite                                      │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ 🧠 Design Thinking             1 step | CIS              │       │
│  │ 💡 Innovation Strategy          1 step | CIS              │       │
│  │ 🔬 Problem Solving             1 step | CIS              │       │
│  │ 📖 Storytelling                1 step | CIS              │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  📐 Custom Compositions                                              │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ 🚀 My Product Launch Process    6 steps | BMM + CIS      │       │
│  │    Research → Brief → PRD → Arch → Brainstorm → Epics     │       │
│  │    [Run] [Edit]                                           │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                      │
│  [+ Create Composite Workflow]                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.3 Composite Workflow Builder

```
┌─────────────────────────────────────────────────────────────────────┐
│  Create Composite Workflow                                           │
├────────────────────────────────┬────────────────────────────────────┤
│  Available BMAD Workflows      │  Your Workflow                     │
│  ┌────────────────────────┐   │  ┌──────────────────────────────┐ │
│  │ Filter: [All modules ▼]│   │  │ Name: [My Product Process   ]│ │
│  │                        │   │  │                              │ │
│  │ BMM / Analysis         │   │  │ Step 1: Market Research  ✕  │ │
│  │   ☐ Domain Research    │   │  │   Agent: Mary (Analyst)     │ │
│  │   ✓ Market Research    │→  │  │                              │ │
│  │   ☐ Technical Research │   │  │ Step 2: Product Brief    ✕  │ │
│  │   ✓ Product Brief      │→  │  │   Agent: Mary (Analyst)     │ │
│  │                        │   │  │                              │ │
│  │ BMM / Planning         │   │  │ Step 3: Create PRD       ✕  │ │
│  │   ✓ Create PRD         │→  │  │   Agent: John (PM)         │ │
│  │   ☐ Create UX Design   │   │  │                              │ │
│  │                        │   │  │ Step 4: Architecture     ✕  │ │
│  │ BMM / Solutioning      │   │  │   Agent: Winston (Arch)    │ │
│  │   ✓ Create Architecture│→  │  │                              │ │
│  │   ✓ Create Epics       │→  │  │ Step 5: Epics & Stories  ✕  │ │
│  │   ☐ Check Readiness    │   │  │   Agent: John (PM)         │ │
│  │                        │   │  │                              │ │
│  │ CIS                    │   │  │        [↑ Move] [↓ Move]     │ │
│  │   ☐ Design Thinking    │   │  │                              │ │
│  │   ☐ Brainstorming      │   │  │ Dependencies: auto-detected │ │
│  │   ☐ Storytelling       │   │  │ PRD → Architecture ✓        │ │
│  │                        │   │  │ Brief → PRD ✓               │ │
│  └────────────────────────┘   │  └──────────────────────────────┘ │
│                                │                                    │
│                                │  [Save as Draft] [Save & Run]     │
└────────────────────────────────┴────────────────────────────────────┘
```

---

## 8. Dependency Resolution

### 8.1 BMAD Workflow Dependencies

BMAD workflows have implicit dependencies through artifacts:
- `create-architecture` **requires** PRD.md → depends on `create-prd`
- `create-epics-and-stories` **requires** PRD.md + architecture.md → depends on `create-prd` + `create-architecture`
- `dev-story` **requires** sprint-status.yaml + story file → depends on `sprint-planning` + `create-story`

### 8.2 Dependency Graph (BMM)

```
domain-research ──────┐
market-research ──────┤
technical-research ───┴──→ create-product-brief ──→ create-prd ──┬──→ create-architecture ──┬──→ create-epics-and-stories ──→ check-implementation-readiness
                                                                  │                          │
                                                                  └──→ create-ux-design ─────┘
                                                                  
                                                                  create-epics-and-stories ──→ sprint-planning ──→ create-story ──→ dev-story ──→ code-review
                                                                                                                                                      │
                                                                                                                                                      ▼
                                                                                                                                               retrospective
```

### 8.3 Automatic Step Dependency Setting

When the user assembles a composite workflow, the system automatically sets `depends_on_step_ids` based on the artifact-dependency graph:

```ruby
class BmadDependencyResolver
  def resolve(workflow)
    workflow.steps.each do |step|
      next unless step.bmad_step?

      required_artifacts = step.bmad_workflow.requires || []
      next if required_artifacts.empty?

      # Find steps that produce required artifacts
      producer_steps = workflow.steps.select do |other|
        next if other == step
        next unless other.bmad_step?

        produced = other.bmad_workflow.produces || []
        (required_artifacts & produced).any?
      end

      step.update!(depends_on_step_ids: producer_steps.map(&:id))
    end
  end
end
```

---

## 9. BMAD → Palad: Workspace Preparation

### 9.1 BMAD Files in Workspace

When a StepRun for a BMAD step is launched, the workspace is prepared with BMAD files:

```
/workspace/
├── input/
│   ├── _index.md
│   ├── _bmad/                          ← BMAD module files
│   │   ├── bmm/
│   │   │   ├── config.yaml
│   │   │   └── workflows/
│   │   │       └── 3-solutioning/
│   │   │           └── create-architecture/
│   │   │               ├── workflow.md
│   │   │               ├── steps/
│   │   │               │   ├── step-01-init.md
│   │   │               │   ├── step-02-load-docs.md
│   │   │               │   └── ...
│   │   │               └── data/
│   │   │                   └── architecture-decision-template.md
│   │   └── _config/
│   │       └── workflow-manifest.csv
│   ├── prd.md                          ← from previous step output
│   └── product-brief.md               ← from previous step output
│
└── output/
    └── (agent saves architecture.md here)
```

### 9.2 WorkflowStepStrategy Enhancement

```ruby
class ContainerStrategies::WorkflowStepStrategy
  def prepare_workspace(step_run, workspace_path)
    super # existing: mount input assets, workflow run assets

    if step_run.step.bmad_step?
      prepare_bmad_files(step_run, workspace_path)
    end
  end

  private

  def prepare_bmad_files(step_run, workspace_path)
    bmad_workflow = step_run.step.bmad_workflow
    bmad_module = bmad_workflow.bmad_module

    bmad_input_path = "#{workspace_path}/input/_bmad"
    FileUtils.mkdir_p(bmad_input_path)

    # Mount the specific workflow directory
    source = resolve_bmad_source_path(bmad_module, bmad_workflow)
    FileUtils.cp_r(source, "#{bmad_input_path}/#{bmad_module.name}/workflows/")

    # Mount module config
    config_source = resolve_config_path(bmad_module)
    FileUtils.cp(config_source, "#{bmad_input_path}/#{bmad_module.name}/config.yaml")
  end
end
```

---

## 10. Comparison of approaches

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Static mapping** (one huge workflow) | Simplicity; a single seed | Inflexible; not all projects need all phases; 20+ steps | ❌ |
| **B. Phase workflows + Composite builder** | Flexible; auto-generated + custom; understandable to the user | More complex, more code | ✅ Chosen |
| **C. Meta-workflow builds on the fly** | Maximum flexibility; AI decides | Unpredictability; expensive (agent + container for "planning") | ❌ For a different use case |
| **D. BMAD as a "plugin" to regular workflows** | Minimal changes | No unified concept; custom mappings scattered around | ❌ |

Choice **B**: Phase Workflows (auto-generated) + Composite Workflow Builder (user-assembled) + Module Registry (extensible).

---

## 11. Difference from Meta-Workflow

| Meta-Workflow (existing design) | System Workflow (this document) |
|---|---|
| **Builds** new workflows (constructor) | **Runs** existing BMAD workflows |
| Result: a new Workflow in the DB | Result: artifacts (PRD, architecture, epics) |
| Uses meta_create_* tools | Uses standard workflow tools + BMAD context |
| Always interactive | Supports all modes (interactive / non-interactive / mixed) |
| One system workflow | Multiple system workflows (per phase + composite) |
| Scope: System | Scope: System |
| Agent: Workflow Architect | Agents: mapped from BMAD (analyst, architect, pm, dev) |

These two mechanisms **do not conflict**, but complement each other:
- Meta-Workflow can **create** a new composite system workflow
- System Workflow **runs** BMAD processes

---

## 12. Implementation Plan

### Phase 1: BMAD Module Registry (3-4 days)
- [ ] Migrations: `bmad_modules`, `bmad_agents`, `bmad_workflows`, `bmad_workflow_steps`
- [ ] `BmadModuleImporter` with parsers (agent, workflow, step)
- [ ] `BmadAgentMapper` → creating Palad Agents from BMAD agents
- [ ] `BmadConfigMapper` → injection into shared_context
- [ ] Seed: import modules from `_bmad/` of the current project

### Phase 2: System Workflow Generation (3-4 days)
- [ ] `scope_type: System` for the Workflow model
- [ ] `bmad_workflow_id` for the Step model
- [ ] `SystemWorkflowGenerator` — auto-creation of phase workflows from the registry
- [ ] `BmadDependencyResolver` — auto-dependency setting
- [ ] `BmadInstructionTransformer` — instruction adaptation
- [ ] `SystemWorkflowMapping` model

### Phase 3: Runtime Integration (3-4 days)
- [ ] `ContextBuilders::BmadContext` — BMAD section in agent context
- [ ] `WorkflowStepStrategy` enhancement — mount BMAD files
- [ ] Adapting `PrepareStepActivity` for BMAD steps
- [ ] SubStep auto-creation from BMAD step files
- [ ] Testing: running a BMAD workflow through a system workflow

### Phase 4: Composite Builder UI (4-5 days)
- [ ] BMAD Module Management page (Settings)
- [ ] System Workflow Catalog page
- [ ] Composite Workflow Builder (drag & drop)
- [ ] Dependency visualization
- [ ] Phase workflow auto-generation UI

### Phase 5: Module Extensibility (2-3 days)
- [ ] npm-based module installation
- [ ] Module update flow (version diff + re-mapping)
- [ ] Cross-module composite workflows
- [ ] Module uninstall (with dependency check)

**Overall estimate: 15-20 days**

---

## 13. Open Questions

| # | Question | Proposal |
|---|--------|-------------|
| 1 | Where to store BMAD source files? In the DB (as a blob) or on the file system? | File system (mount from git/npm), only metadata in the DB |
| 2 | How to handle BMAD workflows with `step-file architecture` (multiple step-*.md files)? | Each step-file → SubStep. The agent receives all files in the workspace and follows them. |
| 3 | How to handle BMAD config vars in non-interactive mode? Some workflows ask for user_name. | ConfigMapper substitutes from the BMAD config. In non-interactive mode — automatically. |
| 4 | Is it necessary to support BMAD "teams" (groups of agents)? | Not for now. Teams are just a pre-set for Party Mode and do not affect workflow execution. |
| 5 | How to map BMAD "menu handlers" (workflow/exec/action)? | Palad has no interactive agent menus. Menu → instructions in step.instructions. |
| 6 | How to handle BMAD validation workflows (validate-prd, validate-agent)? | Separate Steps with `allow_non_interactive: true`. Output = validation report. |
| 7 | Is a versioned migration of system workflows needed when BMAD is updated? | Yes: on a module update → re-generate phase workflows. Running WorkflowRuns are not affected. |

---

## 14. Glossary

| Term | Definition |
|--------|-------------|
| **System Workflow** | A Workflow with `scope_type: System`, shipped by the platform, containing BMAD mapping configuration |
| **BMAD Module** | A package (bmm, cis, bmb) with agents, workflows, config — the unit of extension |
| **BMAD Module Registry** | A catalog of imported modules in Palad (the `bmad_modules` table) |
| **Phase Workflow** | An auto-generated System Workflow corresponding to one BMAD phase (Analysis, Planning, etc.) |
| **Composite Workflow** | A user-assembled System Workflow from workflows of different modules |
| **Mapping** | A rule for translating a BMAD entity into a Palad entity (agent → Agent, config var → shared_context) |
| **BmadInstructionTransformer** | A service that adapts BMAD workflow instructions for the Palad runtime |

---

_Document v1 generated 2026-03-02_
