# Functional Requirements

## Agent Sessions

- **FR1:** User can start a new agent session with selected agent type (Claude Code, Codex, Gemini CLI, Cursor CLI)
- **FR2:** User can choose between Interactive and Non-interactive mode when starting a session
- **FR3:** User can interact with agent through web terminal in Interactive mode
- **FR4:** User can view file tree of session workspace in real-time
- **FR5:** User can view and browse files in session workspace (code, images, PDF)
- **FR6:** User can stop an active session
- **FR7:** User can view session history with status and outcomes
- **FR8:** System automatically tracks token usage during session via MITM proxy
- **FR9:** User can see session cost (tokens, USD) after session completes

## Workflow Management

- **FR10:** Admin can create new workflow with name, description, and steps
- **FR11:** Admin can define workflow steps with agent type, prompt template, and expected artifacts
- **FR12:** Admin can edit existing workflows
- **FR13:** Admin can delete workflows
- **FR14:** User can view list of available workflows
- **FR15:** User can start workflow execution with selected input assets
- **FR16:** User can execute workflow steps in Interactive mode (step-by-step with approval)
- **FR17:** User can execute workflow in Non-interactive mode (automated)
- **FR18:** System passes artifacts between workflow steps automatically

## Artifact Management

- **FR19:** User can upload assets (files, archives) to project
- **FR20:** User can view list of artifacts in project
- **FR21:** User can download artifacts
- **FR22:** User can delete artifacts
- **FR23:** System stores artifacts in S3 with metadata in database
- **FR24:** System preserves artifact history and versioning
- **FR25:** Workflow steps can reference artifacts from previous steps as input

## Project & Collaboration

- **FR26:** Admin can create new project within company
- **FR27:** Admin can add collaborators to project
- **FR28:** Admin can remove collaborators from project
- **FR29:** Collaborator can access all project resources (sessions, workflows, artifacts)
- **FR30:** User can view list of projects they have access to
- **FR31:** User can switch between projects

## Secrets Management

- **FR32:** Admin can create secrets at platform level
- **FR33:** Admin can create secrets at workflow level
- **FR34:** System injects appropriate secrets into agent sessions
- **FR35:** Secrets are encrypted at rest
- **FR36:** User cannot view secret values after creation (write-only)

## Agent Management

- **FR37:** Admin can create agent with name, title, persona, and communication style
- **FR38:** Admin can edit and delete agents
- **FR39:** Admin can import agents from BMAD files
- **FR40:** User can select agent when starting a session
- **FR41:** Agent persona is injected as system prompt for LLM
- **FR42:** Agents can be scoped to company or project level

## Tools Framework

- **FR43:** Admin can create custom tool with Docker image and configuration
- **FR44:** Admin can specify required secrets for tool
- **FR45:** Admin can define tool input schema (JSON Schema)
- **FR46:** Tools can be scoped to company or project level (project overrides company)
- **FR47:** System executes tool as Temporal Activity (sync)
- **FR48:** Tool results are returned to agent

## MCP Server Management

- **FR49:** Admin can configure MCP servers at company/project level
- **FR50:** Admin can select which tools are exposed via MCP server
- **FR51:** MCP server starts alongside agent session
- **FR52:** CLI agents connect to MCP server for tool access

## Session Context

- **FR53:** Admin can configure session context per CLI type (Claude Code, Cursor, Gemini, Codex)
- **FR54:** System injects config files into container based on CLI type
- **FR55:** System injects environment variables with resolved secrets
- **FR56:** System connects configured MCP servers to session

## Billing & Analytics

- **FR57:** User can view total cost for project
- **FR58:** User can view cost breakdown by workflow
- **FR59:** User can view cost breakdown by user
- **FR60:** User can view session history with costs
- **FR61:** Admin can view company-wide usage statistics

## User Management

- **FR62:** User can sign in via Google OAuth
- **FR63:** Admin can invite users to company
- **FR64:** Admin can assign user roles (Admin, Collaborator)
- **FR65:** Admin can remove users from company

## Integrations

- **FR66:** System can export tasks to Linear from workflow output
- **FR67:** System can load code context from GitHub repository
- **FR68:** System can create PR in GitHub from session output

---
