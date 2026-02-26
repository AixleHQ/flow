# Workflow: Code Report Generation & Formatting

## Overview

Three-step workflow for generating a comprehensive code report from a repository, running Semgrep static analysis, and formatting it into a shareable HTML document.

## Data Model

```
Workflow: "Code Report"

Wave 0 (parallel):
├── Step 1: "Generate Code Report" (position: 1, depends_on: [])
│   ├── SubStep 1.1: Overview (position: 1)
│   ├── SubStep 1.2: Static Analysis (position: 2)
│   ├── SubStep 1.3: Technology Stack (position: 3)
│   ├── SubStep 1.4: Code Quality Summary (position: 4)
│   ├── SubStep 1.5: Infrastructure Analysis (position: 5)
│   ├── SubStep 1.6: Backend Analysis (position: 6)
│   └── SubStep 1.7: Frontend Analysis (position: 7)
│
├── Step 2: "Run Semgrep" (position: 2, depends_on: [], on_failure: skip)
│   └── SubStep 2.1: Run Analysis (position: 1)

Wave 1 (after wave 0):
└── Step 3: "Format & Share Report" (position: 3, depends_on: [Step 1, Step 2])
    ├── SubStep 3.1: Select Sections (position: 1)
    └── SubStep 3.2: Generate HTML Document (position: 2)
```

### Step Dependency Model

Steps declare their dependencies via `depends_on_step_ids`. Steps with no dependencies (root steps) can run in parallel. Steps with dependencies wait for all dependencies to complete before starting.

The Temporal workflow engine groups steps into "waves" based on the dependency graph (DAG). All steps within a wave execute in parallel (for auto-run steps) or sequentially (for interactive steps).

---

## Step 1: Generate Code Report

### Configuration

| Field | Value |
|-------|-------|
| name | Generate Code Report |
| position | 1 |
| agent | code_reporter (Code Report Analyst) |
| allow_non_interactive | true |
| skip_policy | if_outputs_exist |
| on_failure | retry |
| max_retries | 1 |
| mount_repositories | true |

### Instructions

```
You are generating a comprehensive code report for the uploaded repository.

For each sub-step, analyze the relevant source files and produce a well-structured Markdown section. Use the Map-Reduce approach:
1. Scan repository files, categorize by type
2. For each sub-step, focus on the specified file categories
3. Generate the section following the prompt instructions exactly
4. Combine all sections into a single Markdown document

Save the final output as `code_report.md` in the output directory.

The report must be data-driven, cite specific files, and provide actionable recommendations.
```

### Input Assets

| Name | Asset Type | Required |
|------|-----------|----------|
| repository | repository | true |

### Output Assets

| Name | Asset Type | Required |
|------|-----------|----------|
| code_report.md | document | true |

### Sub-steps

Each sub-step corresponds to one section of the code report. The prompt for each sub-step is taken verbatim from `web_references/ai-engine/app/agents/assets/code_report_section_agent/prompts.py`.

#### SubStep 1.1: Overview

- **Position:** 1
- **Required:** true
- **Description:** Executive summary synthesizing all analyses into business-focused assessment
- **Instructions:** (OVERVIEW_PROMPT — full text in `ai/code-report-prompts.md` Section 1)

#### SubStep 1.2: Static Analysis

- **Position:** 2
- **Required:** true
- **Description:** Codebase metrics, file distribution, language breakdown
- **Instructions:** (STATIC_ANALYSIS_PROMPT — full text in `ai/code-report-prompts.md` Section 2)

#### SubStep 1.3: Technology Stack

- **Position:** 3
- **Required:** true
- **Description:** Technologies, frameworks, tools inventory grouped by purpose
- **Instructions:** (TECHNOLOGY_STACK_PROMPT — full text in `ai/code-report-prompts.md` Section 3)

#### SubStep 1.4: Code Quality Summary

- **Position:** 4
- **Required:** true
- **Description:** Code quality audit with severity scoring and recommendations
- **Instructions:** (QUALITY_SUMMARY_PROMPT — full text in `ai/code-report-prompts.md` Section 4)

#### SubStep 1.5: Infrastructure Analysis

- **Position:** 5
- **Required:** false
- **Description:** DevOps, containerization, deployment, monitoring assessment
- **Instructions:** (INFRASTRUCTURE_ANALYSIS_PROMPT — full text in `ai/code-report-prompts.md` Section 5)

#### SubStep 1.6: Backend Analysis

- **Position:** 6
- **Required:** true
- **Description:** Backend architecture, data layer, API design, security, testing
- **Instructions:** (BACKEND_ANALYSIS_PROMPT — full text in `ai/code-report-prompts.md` Section 6)

#### SubStep 1.7: Frontend Analysis

- **Position:** 7
- **Required:** false
- **Description:** Frontend architecture, components, styling, state, UX assessment
- **Instructions:** (FRONTEND_ANALYSIS_PROMPT — full text in `ai/code-report-prompts.md` Section 7)

---

## Step 2: Run Semgrep

### Configuration

| Field | Value |
|-------|-------|
| name | Run Semgrep |
| position | 2 |
| allow_non_interactive | true |
| skip_policy | manual |
| on_failure | skip |
| max_retries | 1 |
| mount_repositories | false |

### Instructions

```
Run the Semgrep static analysis tool on the project repository.

1. Identify the repository attached to this session (use repository_id from context)
2. Call the `semgrep` tool with the repository_id
3. Wait for the tool to complete by reading the tool result
4. Parse the JSON output and save it as `semgrep_report.json`
5. Briefly summarize: total findings, breakdown by severity (ERROR/WARNING/INFO), top rule categories

If the tool fails, note the error and continue — this step should not block the workflow.
```

### Input Assets

None — the tool resolves the repository from the session.

### Output Assets

| Name | Asset Type | Required |
|------|-----------|----------|
| semgrep_report.json | document | false |

### Sub-steps

#### SubStep 2.1: Run Analysis

- **Position:** 1
- **Required:** true
- **Description:** Call Semgrep tool and save results
- **Instructions:**

```
1. Call the `semgrep` tool via MCP with the repository_id and optionally BRANCH
2. Use `read_tool_result` to poll until the result is completed
3. Download and save the JSON output to semgrep_report.json as a step output asset
4. Summarize findings: total issues, breakdown by severity, top 5 rule categories
5. If the analysis fails, note the error and continue — do not fail the step
```

---

## Step 3: Format & Share Report

### Configuration

| Field | Value |
|-------|-------|
| name | Format & Share Report |
| position | 2 |
| allow_non_interactive | true |
| skip_policy | never |
| on_failure | retry |
| max_retries | 1 |
| mount_repositories | false |

### Instructions

```
You are formatting a code report into a beautiful, shareable HTML document.

Input: code_report.md (from Step 1) and code_report_template.html (HTML template).
Optional input: semgrep_report.json (from Step 2) — if present, include Semgrep findings as an appendix.

**Interactive mode:** Present available sections to the user and ask which to include, then generate the document.
**Non-interactive mode:** Include all sections from code_report.md. If a Semgrep report is present, include a summary as an appendix.

The output should be a polished, professional document suitable for sharing with clients.
```

### Input Assets

| Name | Asset Type | Required |
|------|-----------|----------|
| code_report.md | document | true |
| code_report_template.html | document | true |
| semgrep_report.json | document | false |

### Output Assets

| Name | Asset Type | Required |
|------|-----------|----------|
| code_report.html | document | true |

### Sub-steps

#### SubStep 2.1: Select Sections

- **Position:** 1
- **Required:** true
- **Description:** Determine which sections to include — interactively ask user or use all by default
- **Instructions:**

```
Read the generated code_report.md and identify all sections.
Check if a Semgrep report (semgrep_report.json) is available in the input assets.

**If running interactively:**
Present the user with a numbered list of available sections:
1. Overview
2. Static Analysis
3. Technology Stack
4. Code Quality Summary
5. Infrastructure Analysis
6. Backend Analysis
7. Frontend Analysis
8. Semgrep Security Report (if semgrep_report.json is available)

Ask the user which sections they want to include in the final document.
Also ask if they want to customize the order or exclude any sub-sections.
Wait for user confirmation before proceeding.

**If running non-interactively:**
Include all sections found in code_report.md.
If semgrep_report.json is present in inputs, include a Semgrep findings appendix.
Proceed immediately to the next sub-step.
```

#### SubStep 2.2: Generate HTML Document

- **Position:** 2
- **Required:** true
- **Description:** Apply HTML template to selected sections and produce polished shareable document
- **Instructions:**

```
Using the selected sections from the previous sub-step and the code_report_template.html template:

1. Parse the code_report.md and extract only the selected sections
2. Convert Markdown content to HTML
3. Apply the template styling and structure from code_report_template.html
4. Ensure proper formatting:
   - Tables are styled and responsive
   - Code blocks have syntax highlighting
   - Score indicators (🔴🟡🟢) are preserved
   - Charts/graphs rendered where data supports it
   - Professional header with project name and date
   - Table of contents with links to sections
5. Save as code_report.html

The final document should look professional and be ready to share with clients.
```

---

## Execution Modes

Three workflow modes control step advancement:

| Mode | Step 1 (allow_ni=true) | Step 2 (allow_ni=true) | Step 3 (allow_ni=false) |
|------|----------------------|----------------------|------------------------|
| `non_interactive` | auto | auto | auto (all sections) |
| `mixed` | auto | auto | **pauses** — user picks sections |
| `interactive` | pauses | pauses | pauses |

- **`non_interactive`** — fully automated: all steps auto-advance, all sections included, Semgrep appended if available
- **`mixed`** — Steps 1 & 2 run automatically, Step 3 pauses for user to select sections for the final report
- **`interactive`** — every step pauses for user decision (complete / skip / retry)

## Notes

- Prompts are copied verbatim from the Python ai-engine to maintain consistency
- Infrastructure Analysis and Frontend Analysis sub-steps are optional (`required: false`) since not all repos have these components
- The HTML template (`code_report_template.html`) must be provided as input asset to Step 3
- Step 1 outputs feed into Step 3, Step 2 outputs (Semgrep) feed into Step 3 as optional asset
- Step 2 (Semgrep) has `on_failure: skip` — if the tool is unavailable or fails, the workflow continues without it
