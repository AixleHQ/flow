---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - ai/prd.md
  - ai/architecture.md
  - ai/ux-design-specification.md
---

# app - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for app, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: User can start a new agent session with selected agent type (Claude Code, Codex, Gemini CLI, Cursor CLI)
FR2: User can choose between Interactive and Non-interactive mode when starting a session
FR3: User can interact with agent through web terminal in Interactive mode
FR4: User can view file tree of session workspace in real-time
FR5: User can view and browse files in session workspace (code, images, PDF)
FR6: User can stop an active session
FR7: User can view session history with status and outcomes
FR8: System automatically tracks token usage during session via MITM proxy
FR9: User can see session cost (tokens, USD) after session completes
FR10: Admin can create new workflow with name, description, and steps
FR11: Admin can define workflow steps with agent type, prompt template, and expected artifacts
FR12: Admin can edit existing workflows
FR13: Admin can delete workflows
FR14: User can view list of available workflows
FR15: User can start workflow execution with selected input assets
FR16: User can execute workflow steps in Interactive mode (step-by-step with approval)
FR17: User can execute workflow in Non-interactive mode (automated)
FR18: System passes artifacts between workflow steps automatically
FR19: User can upload assets (files, archives) to project
FR20: User can view list of artifacts in project
FR21: User can download artifacts
FR22: User can delete artifacts
FR23: System stores artifacts in S3 with metadata in database
FR24: System preserves artifact history and versioning
FR25: Workflow steps can reference artifacts from previous steps as input
FR26: Admin can create new project within company
FR27: Admin can add collaborators to project
FR28: Admin can remove collaborators from project
FR29: Collaborator can access all project resources (sessions, workflows, artifacts)
FR30: User can view list of projects they have access to
FR31: User can switch between projects
FR32: Admin can create secrets at platform level
FR33: Admin can create secrets at workflow level
FR34: System injects appropriate secrets into agent sessions
FR35: Secrets are encrypted at rest
FR36: User cannot view secret values after creation (write-only)
FR37: Admin can create custom tool with Docker image and configuration
FR38: Admin can specify required secrets for tool
FR39: Agent can invoke tools during session via MCP
FR40: System executes tool as Temporal Activity (sync)
FR41: Tool results are returned to agent
FR42: User can view total cost for project
FR43: User can view cost breakdown by workflow
FR44: User can view cost breakdown by user
FR45: User can view session history with costs
FR46: Admin can view company-wide usage statistics
FR47: User can sign in via Google OAuth
FR48: Admin can invite users to company
FR49: Admin can assign user roles (Admin, Collaborator)
FR50: Admin can remove users from company
FR51: System can export tasks to Linear from workflow output
FR52: System can load code context from GitHub repository
FR53: System can create PR in GitHub from session output

### NonFunctional Requirements

NFR-S1: All API keys and secrets encrypted at rest (AES-256) - Protect sensitive credentials
NFR-S2: All data in transit encrypted via TLS 1.2+ - Standard security practice
NFR-S3: Session data isolated by company_id — no cross-tenant access - Multi-tenancy isolation
NFR-S4: Audit log for all admin actions (user management, secrets, workflows) - SOC 2 preparation
NFR-S5: Secrets never logged or displayed after creation - Prevent credential exposure
NFR-S6: Docker containers isolated per session - Prevent cross-session data leakage
NFR-R1: Session failure rate < 1% - Core success metric
NFR-R2: Zero data loss for artifacts (stored in S3 with redundancy) - Business critical
NFR-R3: Billing accuracy ≥ 95% of actual token usage - Key differentiator
NFR-R4: Graceful degradation when LLM provider unavailable - Fallback to alternative
NFR-R5: Session state preserved on unexpected termination - User doesn't lose work
NFR-I1: Support multiple LLM providers (Anthropic, OpenAI, OpenRouter) - Provider agnostic
NFR-I2: MITM proxy compatible with all 4 target agents - Core billing feature
NFR-I3: GitHub API integration for repo access and PR creation - Core workflow feature
NFR-I4: Linear API integration for task export - Planning workflow output
NFR-I5: Temporal orchestration for all workflow execution - Reliability, retry, visibility
NFR-O1: Structured logging for all services - Debugging, monitoring
NFR-O2: Health checks for all containers - Kubernetes readiness
NFR-O3: Temporal UI accessible for workflow debugging - Developer experience

### Additional Requirements

**From Architecture:**
- Brownfield project - no starter template needed (Rails 8.0.2 + React 19 already initialized)
- Multi-tenancy isolation via company_id filtering on all tenant tables
- Row-level security patterns for data access
- MITM proxy integration for billing tracking (innovative approach)
- Temporal orchestration for all workflow execution
- Docker containers for agent isolation per session
- S3 storage for artifacts with metadata in PostgreSQL
- ActiveSupport::MessageEncryptor for secrets encryption
- Google OAuth authentication (already implemented)
- RBAC + Pundit policies for authorization
- Feature-Sliced Design structure for frontend
- Redux Toolkit + Zustand for state management
- TanStack Router for type-safe routing
- REST API design pattern
- Structured logging via Lograge
- Health checks for all containers
- Temporal UI for workflow debugging

**From UX Design:**
- Desktop-only platform (1024px minimum)
- Dark theme only for MVP
- WCAG 2.1 AA accessibility compliance
- Real-time updates for file tree and workflow status
- Command Palette (Cmd+K) for global search
- WorkflowStepper component for workflow visualization
- StatusBar component for session info
- FileTree component for session workspace
- Artifact provenance display everywhere
- Cost visibility at every level (step, workflow, project, user)
- Keyboard-first interactions
- Performance: < 100ms for artifact search, < 30 seconds for session start
- Responsive design considerations (desktop breakpoints: 1024px, 1280px, 1440px, 1920px+)
- MUI 6 + Custom Dark Theme
- Grayscale foundation with accent colors
- Inter font for UI, JetBrains Mono for code

### FR Coverage Map

FR1: Epic 4 - Start agent session with selected agent type
FR2: Epic 4 - Choose Interactive/Non-interactive mode
FR3: Epic 4 - Interact with agent through web terminal
FR4: Epic 4 - View file tree in real-time
FR5: Epic 4 - View and browse files in workspace
FR6: Epic 4 - Stop active session
FR7: Epic 4 - View session history
FR8: Epic 4 - Track token usage via MITM proxy
FR9: Epic 4 - See session cost
FR10: Epic 6 - Create new workflow
FR11: Epic 6 - Define workflow steps
FR12: Epic 6 - Edit existing workflows
FR13: Epic 6 - Delete workflows
FR14: Epic 6 - View list of workflows
FR15: Epic 6 - Start workflow execution
FR16: Epic 6 - Execute in Interactive mode
FR17: Epic 6 - Execute in Non-interactive mode
FR18: Epic 6 - Pass artifacts between steps
FR19: Epic 5 - Upload assets to project
FR20: Epic 5 - View list of artifacts
FR21: Epic 5 - Download artifacts
FR22: Epic 5 - Delete artifacts
FR23: Epic 5 - Store artifacts in S3 with metadata
FR24: Epic 5 - Preserve artifact history and versioning
FR25: Epic 5 - Reference artifacts between workflow steps
FR26: Epic 3 - Create new project
FR27: Epic 3 - Add collaborators to project
FR28: Epic 3 - Remove collaborators from project
FR29: Epic 3 - Collaborator access to project resources
FR30: Epic 3 - View list of projects
FR31: Epic 3 - Switch between projects
FR32: Epic 7 - Create secrets at company level
FR33: Epic 7 - (Removed - workflow-level secrets not needed)
FR34: Epic 7 - Inject secrets into agent sessions
FR35: Epic 7 - Encrypt secrets at rest
FR36: Epic 7 - Write-only access to secrets
FR37: Epic 8 - Create custom tool with Docker image (via workflow)
FR38: Epic 8 - Specify required secrets for tool
FR39: Epic 8 - Agent invokes tools via Tool Use API
FR40: Epic 8 - Execute tool as Temporal Activity
FR41: Epic 8 - Return tool results to agent
FR42: Epic 9 - View total cost for project
FR43: Epic 9 - View cost breakdown by workflow
FR44: Epic 9 - View cost breakdown by user
FR45: Epic 9 - View session history with costs
FR46: Epic 9 - View company-wide usage statistics
FR47: Epic 1 - Sign in via Google OAuth
FR48: Epic 1 - Invite users to company
FR49: Epic 1 - Assign user roles
FR50: Epic 1 - Remove users from company
FR51: Epic 10 - Export tasks to Linear
FR52: Epic 10 - Load code context from GitHub
FR53: Epic 10 - Create PR in GitHub

## Epic List

### Epic 1: Authentication & User Management
Users can sign in to the platform and manage user access to the company.

**FRs covered:** FR47, FR48, FR49, FR50

**User Outcome:** Complete authentication system and basic user management for the company.

---

### Epic 2: Agent Onboarding & Configuration
New users can configure their AI agents and save personal settings for each agent.

**FRs covered:** (Prepares infrastructure for Epic 4, based on UX Design requirements)
- Select agents to use (Claude Code, Codex, Gemini CLI, Cursor CLI)
- Authenticate/configure each selected agent
- Save user's personal settings for each agent
- Manage agent settings (edit, disable)

**User Outcome:** User has configured their agents and is ready to work with sessions. Settings are saved and used in all future sessions.

**Note:** This epic prepares infrastructure for Epic 4 (Agent Sessions), ensuring user agent settings are available when starting sessions.

---

### Epic 3: Project & Collaboration Foundation
Users can create projects and manage team access.

**FRs covered:** FR26, FR27, FR28, FR29, FR30, FR31

**User Outcome:** Complete multi-tenancy system and project management with team collaboration.

---

### Epic 4: Agent Sessions Core
Users can start sessions with AI agents and interact with them.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9

**User Outcome:** Complete agent session workflow with cost tracking and interactive interaction.

---

### Epic 5: Artifact Management
Users can upload, view, and manage artifacts.

**FRs covered:** FR19, FR20, FR21, FR22, FR23, FR24, FR25

**User Outcome:** Complete artifact management system with provenance and versioning.

---

### Epic 6: Workflow Management
Users can create and execute workflows with step-by-step execution.

**FRs covered:** FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17, FR18

**User Outcome:** Complete workflow system with support for both execution modes.

---

### Epic 7: Secrets Management
Admins can securely manage secrets for agents and workflows.

**FRs covered:** FR32, FR33, FR34, FR35, FR36

**User Outcome:** Secure secrets management system with hierarchy of levels.

---

### Epic 8: Tools Framework
Admins can create custom tools to extend agent capabilities.

**FRs covered:** FR37, FR38, FR39, FR40, FR41

**User Outcome:** Extensible tools system for agents via Docker and MCP.

---

### Epic 9: Billing & Analytics Dashboard
Users and admins can track costs and usage analytics.

**FRs covered:** FR42, FR43, FR44, FR45, FR46

**User Outcome:** Complete cost transparency at all levels (step, workflow, project, user, company).

---

### Epic 10: External Integrations
System can integrate with external services to extend functionality.

**FRs covered:** FR51, FR52, FR53

**User Outcome:** Integrations with external development tools for seamless workflow.

---

## Epic 1: Authentication & User Management

Users can sign in to the platform and manage user access to the company.

**FRs covered:** FR47, FR48, FR49, FR50

### Story 1.0: Initial Super Admin Setup

As a platform deployer,
I want to configure the initial super admin user,
So that platform administration is available after deployment.

**Acceptance Criteria:**

**Given** the platform is being deployed for the first time
**When** I set the `SUPER_ADMIN_EMAIL` environment variable
**Then** when a user with that email signs in via Google OAuth for the first time
**And** they are automatically assigned the `super_admin` role
**And** they have access to the Platform Admin panel
**And** only users with `super_admin` role can access Platform Admin features
**And** super admin role cannot be assigned through regular user management (only via environment variable or direct database update)

### Story 1.1: Platform Admin Company Management

As a super admin,
I want to create companies and specify their email domains,
So that users with matching email domains are automatically assigned to the correct company.

**Acceptance Criteria:**

**Given** I am a super admin
**When** I navigate to the Platform Admin panel
**Then** I can see a list of all companies
**And** I can create a new company by providing:
  - Company name
  - Email domain(s) (e.g., "company.com", "subsidiary.com")
  - Initial admin user email (optional)
**When** I create a company with email domain "example.com"
**Then** the company is saved in the database
**And** users signing in with emails ending in "@example.com" are automatically assigned to this company
**And** if an initial admin email is provided, that user is assigned Admin role when they first sign in
**And** I can edit company details (name, domains)
**And** I can view company details including user count
**And** I can delete companies (with appropriate safeguards)
**And** non-super-admin users cannot access Platform Admin panel (403 Forbidden)

### Story 1.2: Google OAuth Sign In with Domain-Based Company Assignment

As a user,
I want to sign in using my Google account,
So that I am automatically assigned to the correct company based on my email domain.

**Acceptance Criteria:**

**Given** a company exists with email domain "example.com"
**When** a user with email "user@example.com" signs in via Google OAuth
**Then** they are redirected to Google OAuth consent screen
**And** after successful authentication, a User record is created/updated with their Google email and profile information
**And** the user is automatically assigned to the company matching their email domain
**And** if no company matches their domain, they see an error message: "No company found for your email domain. Please contact your administrator."
**And** if the user already exists, they are logged in to their existing account
**And** the user is redirected to onboarding flow (Epic 2) if it's their first login
**And** the user is redirected to Projects Dashboard if they've completed onboarding
**And** if the company has an initial admin email matching the user's email, they are assigned Admin role
**And** if the user's email matches SUPER_ADMIN_EMAIL environment variable, they are assigned super_admin role

### Story 1.3: User Profile & Company Assignment

As a user,
I want to view and update my profile information,
So that my account information is accurate and up-to-date.

**Acceptance Criteria:**

**Given** I am a signed-in user
**When** I navigate to my profile page
**Then** I can see my:
  - Email address (from Google OAuth, read-only)
  - Display name (editable)
  - Company name (read-only, shows my assigned company)
  - Role within company (read-only)
**When** I update my display name
**Then** the changes are saved
**And** I see a success message
**And** the updated name appears throughout the platform

### Story 1.4: Invite Users to Company

As a company admin,
I want to invite users to my company by email,
So that they can join the platform and access company resources.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Members
**Then** I can see a list of all company members
**And** I can click "Invite User" button
**When** I enter an email address and click "Send Invite"
**Then** an invitation email is sent to that address
**And** the invitation includes a link to sign in via Google OAuth
**And** when the invited user signs in with matching email domain
**Then** they are automatically added to my company
**And** they are assigned Collaborator role by default
**And** I receive a notification that the user has joined
**And** if the email domain doesn't match company domain, invitation fails with appropriate error message

### Story 1.5: Assign User Roles

As a company admin,
I want to assign roles to company members,
So that I can control access to company resources.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Members
**Then** I can see each member's current role
**When** I change a member's role from Collaborator to Admin
**Then** the role change is saved
**And** the member immediately has Admin permissions
**And** I see a success message
**And** I cannot change my own role (prevent lockout)
**And** I cannot change super admin roles (only platform-level)

### Story 1.6: Remove Users from Company

As a company admin,
I want to remove users from my company,
So that former team members no longer have access to company resources.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Members
**Then** I can see a "Remove" action for each member
**When** I click "Remove" for a member
**Then** I see a confirmation dialog
**When** I confirm the removal
**Then** the user is removed from the company
**And** they lose access to all company projects, workflows, and resources
**And** I see a success message
**And** I cannot remove myself from the company (prevent lockout)
**And** if the user has active sessions, they are terminated

---

## Epic 2: Agent Onboarding & Configuration

New users can configure their AI agents and save personal settings for each agent.

**FRs covered:** (Prepares infrastructure for Epic 4, based on UX Design requirements)

### Story 2.1: Onboarding Flow Entry

As a new user,
I want to be guided through agent setup after my first login,
So that I can configure my agents before starting work.

**Acceptance Criteria:**

**Given** I have just signed in for the first time (completed Epic 1 Story 1.2)
**When** the system detects I haven't completed onboarding
**Then** I am redirected to the Onboarding page
**And** I see a welcome message explaining the onboarding process
**And** I see progress indicators showing onboarding steps
**And** I can skip onboarding (with warning that agents won't be configured)
**And** if I skip, I can access onboarding later from Settings
**And** onboarding completion status is saved in my user profile

### Story 2.2: Select Agents for Configuration

As a new user,
I want to select which AI agents I want to use,
So that I only configure the agents I actually need.

**Acceptance Criteria:**

**Given** I am on the onboarding page
**When** I reach the "Select Agents" step
**Then** I see a list of available agents:
  - Claude Code
  - Codex
  - Gemini CLI
  - Cursor CLI
**And** each agent has a checkbox and brief description
**When** I select one or more agents
**Then** the selected agents are marked
**And** I can proceed to the next step
**And** I must select at least one agent to continue (validation)
**And** I can go back to change my selection

### Story 2.3: Configure Claude Code Agent

As a user,
I want to authenticate and configure my Claude Code agent,
So that I can use it in future sessions.

**Acceptance Criteria:**

**Given** I have selected Claude Code in the agent selection step
**When** I reach the Claude Code configuration step
**Then** I see instructions for configuring Claude Code
**And** I can authenticate with Claude Code in an embedded terminal
**And** I can specify Claude Code settings:
  - API key (stored as secret)
  - Default model preferences
  - Workspace preferences
**When** I complete the configuration
**Then** my Claude Code settings are saved to my user profile
**And** the settings are encrypted and associated with my account
**And** I can test the connection to verify it works
**And** I can skip this agent configuration and configure it later

### Story 2.4: Configure Codex Agent

As a user,
I want to authenticate and configure my Codex agent,
So that I can use it in future sessions.

**Acceptance Criteria:**

**Given** I have selected Codex in the agent selection step
**When** I reach the Codex configuration step
**Then** I see instructions for configuring Codex
**And** I can authenticate with Codex in an embedded terminal
**And** I can specify Codex settings:
  - API credentials (stored as secret)
  - Default model preferences
  - Workspace preferences
**When** I complete the configuration
**Then** my Codex settings are saved to my user profile
**And** the settings are encrypted and associated with my account
**And** I can test the connection to verify it works
**And** I can skip this agent configuration and configure it later

### Story 2.5: Configure Gemini CLI Agent

As a user,
I want to authenticate and configure my Gemini CLI agent,
So that I can use it in future sessions.

**Acceptance Criteria:**

**Given** I have selected Gemini CLI in the agent selection step
**When** I reach the Gemini CLI configuration step
**Then** I see instructions for configuring Gemini CLI
**And** I can authenticate with Gemini CLI in an embedded terminal
**And** I can specify Gemini CLI settings:
  - API credentials (stored as secret)
  - Default model preferences
  - Workspace preferences
**When** I complete the configuration
**Then** my Gemini CLI settings are saved to my user profile
**And** the settings are encrypted and associated with my account
**And** I can test the connection to verify it works
**And** I can skip this agent configuration and configure it later

### Story 2.6: Configure Cursor CLI Agent

As a user,
I want to authenticate and configure my Cursor CLI agent,
So that I can use it in future sessions.

**Acceptance Criteria:**

**Given** I have selected Cursor CLI in the agent selection step
**When** I reach the Cursor CLI configuration step
**Then** I see instructions for configuring Cursor CLI
**And** I can authenticate with Cursor CLI in an embedded terminal
**And** I can specify Cursor CLI settings:
  - API credentials (stored as secret)
  - Default model preferences
  - Workspace preferences
**When** I complete the configuration
**Then** my Cursor CLI settings are saved to my user profile
**And** the settings are encrypted and associated with my account
**And** I can test the connection to verify it works
**And** I can skip this agent configuration and configure it later

### Story 2.7: Save Agent Settings & Complete Onboarding

As a user,
I want to save my agent configurations and complete onboarding,
So that I can start using the platform with my configured agents.

**Acceptance Criteria:**

**Given** I have configured at least one agent
**When** I click "Complete Onboarding"
**Then** all my agent settings are saved
**And** my onboarding completion status is marked as complete
**And** I am redirected to the Projects Dashboard
**And** I see a success message: "Welcome! Your agents are configured and ready to use."
**And** I can access my agent settings later from Settings → Agents
**And** I can edit or add agent configurations at any time
**And** if I haven't configured any agents, I see a warning but can still complete onboarding

---

## Epic 3: Project & Collaboration Foundation

Users can create projects and manage team access.

**FRs covered:** FR26, FR27, FR28, FR29, FR30, FR31

### Story 3.1: Create New Project

As a company admin,
I want to create a new project within my company,
So that I can organize work and resources.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Projects Dashboard
**Then** I can see a "Create Project" button
**When** I click "Create Project"
**Then** I see a form with fields:
  - Project name (required)
  - Description (optional)
**When** I fill in the project name and click "Create"
**Then** a new project is created
**And** I am automatically added as a collaborator with Admin role
**And** I am redirected to the project overview page
**And** I see a success message
**And** the project is associated with my company (company_id)

### Story 3.2: View Projects List

As a user,
I want to view a list of all projects I have access to,
So that I can navigate to the project I need to work on.

**Acceptance Criteria:**

**Given** I am a signed-in user
**When** I navigate to Projects Dashboard
**Then** I can see all projects from my company that I have access to
**And** each project card shows:
  - Project name
  - Description (if available)
  - Number of collaborators
  - Last activity date
**And** I can see projects where I am a collaborator
**And** I can filter projects by name (search)
**And** I can click on a project card to navigate to that project
**And** projects are displayed in a grid layout (responsive)

### Story 3.3: Switch Between Projects

As a user,
I want to switch between projects I have access to,
So that I can work on different projects efficiently.

**Acceptance Criteria:**

**Given** I am viewing a project
**When** I click on the project name in the breadcrumb or header
**Then** I see a dropdown with all my accessible projects
**When** I select a different project from the dropdown
**Then** I am navigated to that project's overview page
**And** the current project context is updated
**And** all project-specific data (sessions, workflows, artifacts) loads for the selected project

### Story 3.4: Add Collaborators to Project

As a project admin,
I want to add collaborators to my project,
So that team members can access project resources.

**Acceptance Criteria:**

**Given** I am a project admin
**When** I navigate to Project Settings → Members
**Then** I can see a list of current project collaborators
**And** I can click "Add Collaborator" button
**When** I enter an email address of a user from my company
**Then** I can select that user from the dropdown
**And** I can assign them Collaborator role
**When** I click "Add"
**Then** the user is added as a collaborator to the project
**And** they immediately have access to all project resources
**And** I see a success message
**And** the user receives a notification that they've been added
**And** I can only add users from my company (validation)

### Story 3.5: Remove Collaborators from Project

As a project admin,
I want to remove collaborators from my project,
So that former team members lose access to project resources.

**Acceptance Criteria:**

**Given** I am a project admin
**When** I navigate to Project Settings → Members
**Then** I can see a list of current project collaborators
**When** I click "Remove" for a collaborator
**Then** I see a confirmation dialog
**When** I confirm the removal
**Then** the user is removed from the project
**And** they lose access to all project resources (sessions, workflows, artifacts)
**And** I see a success message
**And** I cannot remove myself from the project (prevent lockout)
**And** if the user has active sessions in this project, they are terminated

### Story 3.6: Collaborator Access to Project Resources

As a project collaborator,
I want to access all project resources,
So that I can work effectively within the project.

**Acceptance Criteria:**

**Given** I am a collaborator on a project
**When** I navigate to the project
**Then** I have full read/write access to:
  - Sessions (can start, view, stop)
  - Workflows (can view, run)
  - Artifacts (can view, download, upload, delete)
  - Project settings (can view, cannot modify members or delete project)
**And** I can see all project activity and history
**And** my actions are tracked and visible to other collaborators
**And** I cannot access projects where I am not a collaborator (403 Forbidden)

---

## Epic 4: Agent Sessions Core

Users can start sessions with AI agents and interact with them.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9

### Story 4.1: Start Agent Session

As a user,
I want to start a new agent session with a selected agent type,
So that I can work with an AI agent on my project.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to the Sessions tab in my project
**Then** I can see a "Start Session" button
**When** I click "Start Session"
**Then** I see a configuration modal with:
  - Agent type selector (Claude Code, Codex, Gemini CLI, Cursor CLI)
  - Mode selector (Interactive / Non-interactive)
  - Agent must be configured in my profile (validation)
**When** I select an agent type and mode, then click "Start"
**Then** a Docker container is created for the selected agent
**And** a session record is created in the database
**And** I am redirected to the Session View
**And** the session status is "starting"
**And** once the container is ready, the session status changes to "active"
**And** if the agent is not configured, I see an error message with link to settings

### Story 4.2: Web Terminal Interface

As a user,
I want to interact with the agent through a web terminal in Interactive mode,
So that I can communicate with the agent in real-time.

**Acceptance Criteria:**

**Given** I have started a session in Interactive mode
**When** the session becomes active
**Then** I see a web terminal interface (ttyd iframe)
**And** I can type commands and see output in real-time
**And** the terminal supports standard terminal features (cursor, scrolling, copy/paste)
**And** I can interact with the agent through the terminal
**And** terminal output is streamed in real-time
**And** terminal state is preserved if I navigate away and return
**And** terminal supports keyboard shortcuts (Ctrl+C, etc.)

### Story 4.3: Real-time File Tree

As a user,
I want to view the file tree of the session workspace in real-time,
So that I can see what files the agent is working with.

**Acceptance Criteria:**

**Given** I have an active session
**When** I view the Session View
**Then** I see a file tree panel showing the workspace structure
**And** the file tree updates in real-time as files are created/modified/deleted
**And** I can expand/collapse directories
**And** I can see file icons based on file type
**And** I can click on a file to view it in the file viewer
**And** the file tree shows file sizes and modification times
**And** updates happen via WebSocket connection

### Story 4.4: File Viewer & Browser

As a user,
I want to view and browse files in the session workspace,
So that I can see what the agent is working on.

**Acceptance Criteria:**

**Given** I have an active session
**When** I click on a file in the file tree
**Then** the file content is displayed in the file viewer panel
**And** I can view code files with syntax highlighting
**And** I can view images (PNG, JPG, SVG)
**And** I can view PDF files
**And** I can view text files
**And** I can navigate between files using the file tree
**And** I can see file path in the viewer header
**And** files are read-only (cannot edit through viewer)
**And** large files are handled gracefully (lazy loading or pagination)

### Story 4.5: Stop Active Session

As a user,
I want to stop an active session,
So that I can terminate the agent's work when needed.

**Acceptance Criteria:**

**Given** I have an active session
**When** I click the "Stop Session" button
**Then** I see a confirmation dialog
**When** I confirm the stop action
**Then** the Docker container is terminated
**And** the session status changes to "stopped"
**And** any unsaved work is preserved (files remain in workspace)
**And** I see a success message
**And** I am redirected to the session history view
**And** the session summary shows duration and final status

### Story 4.6: MITM Proxy Token Tracking

As a system,
I want to automatically track token usage during sessions via MITM proxy,
So that billing is accurate and transparent.

**Acceptance Criteria:**

**Given** a session is started with an agent
**When** the agent makes API calls to LLM providers
**Then** all API requests are intercepted by the MITM proxy
**And** token usage (input/output tokens) is tracked for each request
**And** token counts are stored in the database
**And** tracking works for all 4 supported agents (Claude Code, Codex, Gemini CLI, Cursor CLI)
**And** token tracking is accurate (≥95% of actual usage per NFR-R3)
**And** if MITM proxy fails, the session continues but tracking may be incomplete (graceful degradation)

### Story 4.7: Session Cost Display

As a user,
I want to see the session cost (tokens, USD) after the session completes,
So that I understand the cost of using the agent.

**Acceptance Criteria:**

**Given** a session has completed or been stopped
**When** I view the session summary
**Then** I can see:
  - Total input tokens used
  - Total output tokens used
  - Total cost in USD (calculated based on provider pricing)
  - Cost breakdown by API call (optional, expandable)
**And** costs are calculated using current provider pricing
**And** if tracking was incomplete, I see a warning message
**And** cost information is also visible in session history list

### Story 4.8: Session History View

As a user,
I want to view my session history with status and outcomes,
So that I can review past work and understand what was accomplished.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Sessions tab
**Then** I can see a list of all sessions for this project
**And** each session shows:
  - Agent type used
  - Mode (Interactive/Non-interactive)
  - Status (active, completed, stopped, failed)
  - Start time and duration
  - Cost (if available)
  - User who started the session
**When** I click on a session
**Then** I can view session details:
  - Full session summary
  - Terminal output (if Interactive mode)
  - Files created/modified
  - Token usage details
  - Cost breakdown
**And** I can filter sessions by agent type, status, or date range
**And** I can search sessions by keywords

---

## Epic 5: Artifact Management

Users can upload, view, and manage artifacts.

**FRs covered:** FR19, FR20, FR21, FR22, FR23, FR24, FR25

### Story 5.1: Upload Assets to Project

As a user,
I want to upload assets (files, archives) to my project,
So that I can use them as input for workflows or share them with the team.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Artifacts tab
**Then** I can see an "Upload" button
**When** I click "Upload"
**Then** I can select one or multiple files
**And** supported file types include: documents, images, archives, code files
**When** I select files and click "Upload"
**Then** files are uploaded to S3
**And** metadata is saved to the database (filename, size, type, uploader, timestamp)
**And** I see upload progress indicator
**And** after upload completes, files appear in the artifacts list
**And** I see a success message
**And** if upload fails, I see an error message with retry option

### Story 5.2: View Artifacts List

As a user,
I want to view a list of artifacts in my project,
So that I can find and access the artifacts I need.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Artifacts tab
**Then** I can see a list of all artifacts in the project
**And** each artifact shows:
  - Name and file type icon
  - Size
  - Upload date/time
  - Uploader name
  - Provenance (if from workflow: "Workflow X → Step Y")
**And** I can search artifacts by name
**And** I can filter artifacts by:
  - File type
  - Date range
  - Uploader
  - Source (manual upload vs workflow)
**And** artifacts are displayed in a grid or list view (toggle)
**And** I can sort by name, date, size
**And** performance is optimized (< 100ms search per UX requirement)

### Story 5.3: Download Artifacts

As a user,
I want to download artifacts from my project,
So that I can use them locally or share them outside the platform.

**Acceptance Criteria:**

**Given** I am viewing the artifacts list
**When** I click on an artifact or click "Download"
**Then** the artifact file is downloaded from S3
**And** the download starts immediately
**And** the original filename is preserved
**And** I can download multiple artifacts at once (bulk download)
**And** if download fails, I see an error message with retry option
**And** download progress is shown for large files

### Story 5.4: Delete Artifacts

As a user,
I want to delete artifacts from my project,
So that I can clean up unused files.

**Acceptance Criteria:**

**Given** I am viewing the artifacts list
**When** I click "Delete" on an artifact
**Then** I see a confirmation dialog
**When** I confirm the deletion
**Then** the artifact file is deleted from S3
**And** the metadata record is marked as deleted (soft delete)
**And** I see a success message
**And** the artifact disappears from the list
**And** if the artifact is referenced by a workflow, I see a warning but can still delete
**And** deleted artifacts can be restored (within retention period)

### Story 5.5: S3 Storage Integration

As a system,
I want to store artifacts in S3 with metadata in the database,
So that artifacts are reliably stored and efficiently accessible.

**Acceptance Criteria:**

**Given** an artifact is uploaded
**When** the upload completes
**Then** the file is stored in S3 bucket
**And** S3 path follows pattern: `projects/{project_id}/artifacts/{artifact_id}/{filename}`
**And** metadata is saved to PostgreSQL:
  - artifact_id (UUID)
  - project_id
  - filename
  - file_size
  - content_type
  - s3_key
  - uploaded_by (user_id)
  - created_at
  - updated_at
**And** S3 files are encrypted at rest
**And** S3 access is restricted to authenticated requests
**And** if S3 is unavailable, upload fails gracefully with error message

### Story 5.6: Artifact History & Versioning

As a system,
I want to preserve artifact history and versioning,
So that users can track changes and restore previous versions.

**Acceptance Criteria:**

**Given** an artifact exists in the project
**When** a new version of the same artifact is uploaded (same filename)
**Then** the previous version is preserved
**And** a new version record is created
**And** version numbers are assigned (v1, v2, v3, etc.)
**When** I view an artifact
**Then** I can see version history
**And** I can view/download any previous version
**And** version history shows:
  - Version number
  - Upload date/time
  - Uploader
  - File size
  - Changes summary (if available)
**And** old versions are retained according to retention policy

### Story 5.7: Artifact Provenance Tracking

As a system,
I want to track where artifacts came from,
So that users can understand the source and lineage of artifacts.

**Acceptance Criteria:**

**Given** an artifact is created
**When** it is uploaded manually
**Then** provenance shows: "Manual upload by {user_name} on {date}"
**When** it is created by a workflow step
**Then** provenance shows: "Workflow '{workflow_name}' → Step '{step_name}' by {user_name} on {date}"
**And** provenance information is stored in artifact metadata
**And** provenance is displayed everywhere the artifact is shown
**And** I can click on workflow/step in provenance to navigate to that workflow run
**And** if artifact is referenced by another workflow step, that relationship is tracked

---

## Epic 6: Workflow Management

Users can create and execute workflows with step-by-step execution.

**FRs covered:** FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17, FR18

### Story 6.1: Create New Workflow

As a company admin,
I want to create a new workflow with name, description, and steps,
So that I can define reusable processes for my team.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Project Settings → Workflows
**Then** I can see a "Create Workflow" button
**When** I click "Create Workflow"
**Then** I see a form with:
  - Workflow name (required)
  - Description (optional)
  - Steps section (initially empty)
**When** I fill in the workflow name and click "Save"
**Then** a new workflow is created
**And** I am redirected to workflow edit page
**And** I can add steps to the workflow (Story 6.2)
**And** the workflow is associated with the project

### Story 6.2: Define Workflow Steps

As a company admin,
I want to define workflow steps with agent type, prompt template, tools, MCPs, and interactivity settings,
So that workflows can be configured with all necessary details.

**Acceptance Criteria:**

**Given** I am editing a workflow
**When** I add a new step
**Then** I can configure:
  - Step name (required)
  - Step description (optional)
  - Prompt template (required, textarea with variable support)
  - Tools selection (multi-select from available tools, optional)
  - MCPs selection (multi-select from configured MCPs, optional)
  - Expected artifact name (optional, for artifact tracking)
  - Interactivity setting (checkbox: "Allow non-interactive execution")
**When** I configure a step
**Then** I can reorder steps (drag and drop)
**And** I can add multiple steps
**And** I can remove steps
**And** I can edit step configuration
**And** prompt template supports variables like {{artifact_from_step_1}} or {{input_artifact_name}}
**And** tools and MCPs are selected from project/company configured resources
**Note:** Agent type (Claude Code, Codex, etc.) is selected when starting workflow execution, not during step definition

### Story 6.3: Edit Existing Workflow

As a company admin,
I want to edit existing workflows,
So that I can update workflow definitions as requirements change.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Project Settings → Workflows
**Then** I can see a list of all workflows
**When** I click "Edit" on a workflow
**Then** I can modify:
  - Workflow name
  - Description
  - All step configurations (name, prompt, tools, MCPs, interactivity settings)
**When** I save changes
**Then** the workflow is updated
**And** existing workflow runs are not affected (they use the workflow version at time of execution)
**And** I see a success message
**And** if the workflow is currently running, I see a warning but can still edit

### Story 6.4: Delete Workflow

As a company admin,
I want to delete workflows,
So that I can remove unused or obsolete workflows.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Project Settings → Workflows
**Then** I can see a "Delete" action for each workflow
**When** I click "Delete"
**Then** I see a confirmation dialog
**When** I confirm deletion
**Then** the workflow is deleted
**And** I see a success message
**And** if the workflow has active runs, I see a warning but can still delete
**And** historical workflow runs remain accessible (for audit purposes)

### Story 6.5: View Workflows List

As a user,
I want to view a list of available workflows,
So that I can find and run the workflow I need.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Workflows tab
**Then** I can see a list of all workflows in the project
**And** each workflow shows:
  - Name and description
  - Number of steps
  - Last run date/time
  - Number of total runs
**And** I can search workflows by name
**And** I can filter workflows by tags or categories (if implemented)
**And** I can click on a workflow to view details or run it
**And** workflows are displayed in a grid or list view

### Story 6.6: Start Workflow Execution

As a user,
I want to start workflow execution with selected input assets and agent type,
So that I can run workflows with my chosen agent and provide initial artifacts.

**Acceptance Criteria:**

**Given** I am viewing a workflow
**When** I click "Run Workflow"
**Then** I see a configuration modal with:
  - Agent type selector (Claude Code, Codex, Gemini CLI, Cursor CLI) - required
  - Input artifacts selector (multi-select from all project artifacts) - optional
  - Execution mode selector (Interactive / Non-interactive) - required
**When** I select agent type, input artifacts, and mode, then click "Start"
**Then** a workflow run is created
**And** Temporal workflow is started
**And** selected input artifacts are available to all workflow steps
**And** I am redirected to Workflow Run view
**And** the workflow run shows progress with WorkflowStepper component
**And** if a step allows non-interactive execution and I selected Non-interactive mode, that step runs automatically
**And** if a step doesn't allow non-interactive execution, it waits for user interaction even in Non-interactive mode
**And** input artifacts can be referenced in prompt templates using variables like {{input_artifact_name}}

### Story 6.7: Interactive Mode Workflow Execution

As a user,
I want to execute workflow steps in Interactive mode with step-by-step approval,
So that I can review and approve each step before proceeding.

**Acceptance Criteria:**

**Given** I have started a workflow execution in Interactive mode
**When** a workflow step starts
**Then** a session is created with the selected agent type
**And** I see the WorkflowStepper showing current step status
**And** the step session opens in Interactive mode
**When** the agent completes the step work
**Then** I see the generated artifact (if expected)
**And** I can review the artifact
**And** I can approve the step to continue
**And** I can reject the step and retry
**When** I approve a step
**Then** the step is marked as completed
**And** the next step becomes available
**And** artifacts from this step are available for next steps
**And** I can see step cost and duration
**And** the process continues until all steps are completed

### Story 6.8: Non-interactive Mode Workflow Execution

As a user,
I want to execute workflows in Non-interactive mode,
So that workflows can run autonomously without my intervention.

**Acceptance Criteria:**

**Given** I have started a workflow execution in Non-interactive mode
**When** the workflow starts
**Then** all steps that allow non-interactive execution run automatically
**And** I see the WorkflowStepper showing progress in real-time
**And** steps execute sequentially
**When** a step completes
**Then** artifacts are automatically passed to the next step
**And** if a step doesn't allow non-interactive execution, execution pauses
**And** I receive a notification that manual approval is needed
**And** I can switch to Interactive mode for that step
**When** all steps complete
**Then** I receive a completion notification
**And** I can view all generated artifacts
**And** I can see total workflow cost and duration
**And** workflow run status is "completed"

### Story 6.9: Artifact Passing Between Steps

As a system,
I want to automatically pass artifacts between workflow steps,
So that steps can use outputs from previous steps and initial input artifacts.

**Acceptance Criteria:**

**Given** a workflow is executing
**When** the workflow starts with input artifacts
**Then** all input artifacts are available to all workflow steps
**When** Step 1 completes and generates an artifact
**Then** the artifact is saved and associated with the workflow run
**And** the artifact is available to subsequent steps
**When** Step 2 starts
**Then** artifacts from Step 1 are available in the step context
**And** input artifacts from workflow start are also available
**And** prompt template variables like {{artifact_from_step_1}} or {{input_artifact_name}} are replaced with actual artifact references
**And** the agent can access all available artifacts (input + previous steps)
**When** multiple steps generate artifacts
**Then** all artifacts are tracked and available to subsequent steps
**And** artifact provenance shows the workflow step that created it (or "Input artifact" for initial artifacts)
**And** artifacts are passed automatically without user intervention
**And** if an artifact is deleted, subsequent steps that reference it show an error
**And** I can see all available artifacts in the workflow run view (input + generated)

---

## Epic 7: Secrets Management

Admins can securely manage secrets for agents and tools.

**FRs covered:** FR32, FR34, FR35, FR36

### Story 7.1: Create Company-Level Secrets

As a company admin,
I want to create secrets at company level,
So that they are available to all tools and sessions in my company.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Secrets
**Then** I can see a list of company-level secrets
**And** I can click "Create Secret"
**When** I create a secret
**Then** I provide:
  - Secret name (required, unique within company)
  - Secret value (required, masked input)
  - Description (optional)
**When** I save the secret
**Then** the secret is encrypted and stored
**And** I cannot view the secret value after creation (write-only)
**And** the secret is available to all tools and agent sessions in my company
**And** I see a success message
**And** I can edit secret name/description but not value (must recreate to change value)
**And** I can delete secrets

### Story 7.2: Encrypt Secrets at Rest

As a system,
I want to encrypt secrets at rest,
So that sensitive credentials are protected even if the database is compromised.

**Acceptance Criteria:**

**Given** a secret is created
**When** the secret value is saved
**Then** it is encrypted using ActiveSupport::MessageEncryptor
**And** only the encrypted value is stored in the database
**And** the encryption key is stored securely (Rails credentials or environment variable)
**And** secrets are decrypted only when needed for injection into sessions
**And** decrypted secrets are never logged
**And** if encryption fails, secret creation fails with error message

### Story 7.3: Inject Secrets into Agent Sessions

As a system,
I want to inject appropriate secrets into agent sessions,
So that agents can access required credentials without exposing them to users.

**Acceptance Criteria:**

**Given** a session is started
**When** the session container is created
**Then** required secrets are decrypted
**And** secrets are injected as environment variables into the Docker container
**And** only secrets required for the agent/tools are injected
**And** secrets are not visible in container logs
**And** secrets are available to the agent during the session
**When** a workflow step uses tools that require secrets
**Then** those secrets are injected into the step session
**And** secrets are scoped to company (company-level secrets only)
**And** if a required secret doesn't exist, session fails with clear error message

### Story 7.4: Write-Only Secret Access

As a system,
I want to prevent viewing secret values after creation,
So that secrets remain secure even from administrators.

**Acceptance Criteria:**

**Given** a secret exists
**When** I view the secrets list
**Then** I can see secret names and descriptions
**And** secret values are never displayed (shows "••••••••" or similar)
**When** I try to view a secret value
**Then** I cannot see the actual value
**And** there is no "Show" or "View" button for secret values
**When** I need to update a secret value
**Then** I must delete and recreate the secret
**And** I see a warning that the old value will be lost
**And** audit log records secret creation/deletion but not values

---

## Epic 8: Tools Framework

Admins can create custom tools to extend agent capabilities.

**FRs covered:** FR37, FR38, FR39, FR40, FR41

### Story 8.1: Tool Creation Workflow

As a company admin,
I want to use a workflow to create custom tools with agent assistance,
So that I can easily create tools with proper configuration files.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Tools
**Then** I can see a "Create Tool with Agent" button
**When** I click this button
**Then** a special workflow starts with an agent
**And** the agent helps me:
  - Define tool purpose and functionality
  - Create Dockerfile
  - Create necessary configuration files
  - Define required inputs/outputs
  - Specify required secrets
**When** the workflow completes
**Then** all generated files are saved
**And** a Tool record is created with:
  - Tool name
  - Docker image reference
  - Configuration files
  - Required secrets list
**And** the tool is available for use in workflow steps
**And** I can review and edit the generated files before finalizing

### Story 8.2: Specify Required Secrets for Tool

As a company admin,
I want to specify which secrets a tool requires,
So that the system can inject them when the tool runs.

**Acceptance Criteria:**

**Given** I am creating or editing a tool
**When** I configure the tool
**Then** I can select required secrets from company-level secrets
**And** I can specify which secrets are required vs optional
**When** the tool is executed
**Then** only specified secrets are injected into the tool container
**And** if a required secret is missing, tool execution fails with clear error
**And** secret references are stored in tool configuration

### Story 8.3: Agent Invokes Tool via Tool Use API

As an agent,
I want to invoke tools during a session using the standard tool use API,
So that I can use custom functionality to accomplish tasks.

**Acceptance Criteria:**

**Given** a workflow step has tools configured
**When** the agent session starts
**Then** available tools are provided to the agent via API `tools` parameter
**And** each tool is defined with:
  - Tool name
  - Description
  - Input schema (JSON schema)
**When** the agent decides to use a tool
**Then** it returns a `tool_use` content block in the API response
**And** the `tool_use` block contains:
  - Tool name
  - Tool call ID
  - Input parameters (matching the schema)
**When** the system receives the `tool_use` request
**Then** it extracts the tool name and parameters
**And** it initiates tool execution (Story 8.4)
**And** after execution, results are returned to the agent in a `tool_result` content block
**And** the agent can use the results to continue its work

### Story 8.4: Temporal Activity Executes Tool

As a system,
I want to execute tools as synchronous Temporal Activities,
So that tool execution is reliable and trackable.

**Acceptance Criteria:**

**Given** an agent invokes a tool
**When** the tool invocation is received
**Then** a Temporal Activity is started (synchronous)
**And** the Activity:
  - Pulls the Docker image for the tool
  - Creates a container with the tool image
  - Injects required secrets as environment variables
  - Mounts/copies required files and artifacts into the container
  - Executes the tool with provided parameters
  - Waits for tool completion
**When** the tool completes
**Then** the Activity captures:
  - Exit code
  - stdout output
  - stderr output
  - Generated files (if any)
**And** the container is cleaned up
**And** results are returned to Temporal workflow

### Story 8.5: Return Tool Results to Agent

As a system,
I want to return tool execution results to the agent,
So that the agent can use the results to continue its work.

**Acceptance Criteria:**

**Given** a tool execution completes
**When** results are returned from Temporal Activity
**Then** results are formatted as `tool_result` content block
**And** results include:
  - Tool call ID (matching the original `tool_use` ID)
  - Success/failure status
  - Output data (stdout)
  - Error information (if failed)
  - Generated files references (if any)
**When** results are sent to the agent
**Then** they are included in the next API request as `tool_result` content block
**And** the agent receives them and can use the results in its work
**And** generated files are available in the session workspace
**And** tool execution is logged for audit purposes

---

## Epic 9: Billing & Analytics Dashboard

Users and admins can track costs and usage analytics.

**FRs covered:** FR42, FR43, FR44, FR45, FR46

### Story 9.1: View Total Cost for Project

As a user,
I want to view the total cost for my project,
So that I can understand spending on AI agent usage.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see total project cost displayed prominently
**And** total cost shows:
  - Total USD spent
  - Total tokens used (input + output)
  - Time period (all time, last month, last week, custom range)
**And** I can see cost trend chart (line chart over time)
**And** I can filter by date range
**And** costs are calculated from all sessions and workflow runs in the project
**And** cost data updates in real-time as new sessions complete
**And** I can see cost breakdown alongside other analytics metrics

### Story 9.2: View Cost Breakdown by Workflow

As a user,
I want to view cost breakdown by workflow,
So that I can identify which workflows are most expensive.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see cost breakdown by workflow section
**And** I can view:
  - Cost per workflow (total USD)
  - Cost per workflow run
  - Percentage of total project cost per workflow
**And** I can see cost breakdown charts:
  - Bar chart: cost by workflow
  - Pie chart: cost distribution by workflow
**And** I can click on a workflow to see detailed cost breakdown (by step, by user)
**And** I can filter by date range
**And** I can sort workflows by cost (highest to lowest)

### Story 9.3: View Cost Breakdown by User

As a user,
I want to view cost breakdown by user,
So that I can understand individual spending patterns.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see cost breakdown by user section
**And** I can view:
  - Cost per user (total USD)
  - Cost per user per session
  - Percentage of total project cost per user
**And** I can see cost breakdown charts:
  - Bar chart: cost by user
  - Pie chart: cost distribution by user
**And** I can click on a user to see detailed cost breakdown (by workflow, by session)
**And** I can filter by date range
**And** I can sort users by cost (highest to lowest)

### Story 9.4: Token Usage Analytics

As a user,
I want to view token usage analytics broken down by user and workflow,
So that I can understand how tokens are being consumed.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see token usage section
**And** I can view token usage breakdown:
  - By user (total tokens per user, input vs output tokens)
  - By workflow (total tokens per workflow, input vs output tokens)
**And** I can see token usage charts:
  - Bar chart: tokens by user
  - Bar chart: tokens by workflow
  - Line chart: token usage over time
**And** I can filter by date range
**And** I can see token efficiency metrics (tokens per task, tokens per step)

### Story 9.5: LLM Request Count Analytics

As a user,
I want to view the number of LLM API requests broken down by user and workflow,
So that I can understand API usage patterns.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see LLM requests section
**And** I can view request count breakdown:
  - By user (total requests per user)
  - By workflow (total requests per workflow)
**And** I can see request count charts:
  - Bar chart: requests by user
  - Bar chart: requests by workflow
  - Line chart: requests over time
**And** I can filter by date range
**And** I can see average requests per session/workflow

### Story 9.6: Workflow Steps Execution Analytics

As a user,
I want to view the number of executed workflow steps broken down by user,
So that I can understand workflow activity.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see workflow steps section
**And** I can view steps execution breakdown:
  - By user (total steps executed per user)
  - By workflow (total steps executed per workflow)
  - Steps completion rate (completed vs failed)
**And** I can see steps execution charts:
  - Bar chart: steps by user
  - Bar chart: steps by workflow
  - Pie chart: completion status breakdown
**And** I can filter by date range
**And** I can see average steps per workflow run

### Story 9.7: Task Completion Analytics

As a user,
I want to view the number of completed tasks broken down by user,
So that I can understand individual productivity.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Project → Analytics tab
**Then** I can see tasks section
**And** I can view task completion breakdown:
  - By user (total tasks completed per user)
  - Task completion rate (completed vs in-progress vs backlog)
**And** I can see task completion charts:
  - Bar chart: tasks completed by user
  - Pie chart: task status breakdown
  - Line chart: task completion over time
**And** I can filter by date range
**And** I can see average time to complete tasks

### Story 9.8: Session History with Costs

As a user,
I want to view session history with costs,
So that I can review past sessions and their expenses.

**Acceptance Criteria:**

**Given** I am a project collaborator
**When** I navigate to Sessions tab
**Then** I can see a list of all sessions
**And** each session shows:
  - Agent type used
  - Mode (Interactive/Non-interactive)
  - Status (active, completed, stopped, failed)
  - Start time and duration
  - Cost (USD and tokens)
  - User who started the session
**When** I click on a session
**Then** I can view detailed session information:
  - Full session summary
  - Token usage breakdown (input/output)
  - Cost breakdown by API call
  - Files created/modified
**And** I can filter sessions by agent type, status, user, or date range
**And** I can search sessions by keywords
**And** I can export session data with costs (CSV)

### Story 9.9: Company-Wide Usage Statistics

As a company admin,
I want to view company-wide usage statistics,
So that I can understand overall platform usage and costs.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → Analytics
**Then** I can see company-wide statistics:
  - Total cost across all projects
  - Total tokens used across all projects
  - Total LLM requests across all projects
  - Total workflow steps executed
  - Total tasks completed
  - Number of active users
  - Number of active projects
**And** I can view breakdowns:
  - Cost by project
  - Cost by user
  - Token usage by project/user
  - Request count by project/user
  - Steps executed by project/user
  - Tasks completed by project/user
**And** I can see company-wide charts and trends
**And** I can filter by date range
**And** I can export company analytics report

---

## Epic 10: External Integrations

System can integrate with external services to extend functionality.

**FRs covered:** FR51, FR52, FR53

### Story 10.1: Configure MCP Connections

As a company admin,
I want to configure MCP (Model Context Protocol) connections,
So that agents can access external services and data.

**Acceptance Criteria:**

**Given** I am a company admin
**When** I navigate to Company Settings → MCPs
**Then** I can see a list of configured MCP connections
**And** I can click "Add MCP"
**When** I add an MCP connection
**Then** I can configure:
  - MCP type (GitHub, Linear, Slack, etc.)
  - Connection name
  - Connection parameters (repository URL, workspace ID, etc.)
  - Required secrets (API keys, tokens)
**When** I save the MCP connection
**Then** the connection is tested
**And** if successful, the MCP is available for use in workflow steps
**And** I can edit MCP configuration
**And** I can delete MCP connections
**And** MCPs are exposed to agents via MCP protocol during sessions

### Story 10.2: Export Tasks to Linear

As a system,
I want to export tasks to Linear from workflow output,
So that planning workflows can create tasks in Linear automatically.

**Acceptance Criteria:**

**Given** a workflow completes and generates tasks
**When** the workflow has Linear integration configured
**Then** tasks are automatically exported to Linear
**And** each task includes:
  - Title (from workflow output)
  - Description (from workflow output)
  - Priority (if specified)
  - Labels/tags (if specified)
  - Assignee (if specified)
**When** tasks are exported
**Then** Linear task IDs are stored and linked to workflow artifacts
**And** I can see exported tasks in Linear
**And** I can navigate from workflow artifact to Linear task
**And** if export fails, I see an error message with retry option

### Story 10.3: Load Code Context from GitHub

As a system,
I want to load code context from GitHub repository,
So that agents can work with existing codebase.

**Acceptance Criteria:**

**Given** a project has GitHub repositories configured
**When** a session or workflow step needs code context
**Then** the system can load code from GitHub repositories
**And** code is loaded based on:
  - Repository URL
  - Branch/commit reference
  - File paths or patterns
**When** code is loaded
**Then** files are available in the session workspace
**And** agent can read and reference the code
**And** code context is cached for performance
**And** if repository is private, authentication uses configured GitHub secrets

### Story 10.4: Create PR in GitHub

As a system,
I want to create PR in GitHub from session output,
So that code changes can be reviewed and merged.

**Acceptance Criteria:**

**Given** a session has completed with code changes
**When** the user wants to create a PR
**Then** I can click "Create PR" button
**When** I create a PR
**Then** I provide:
  - PR title
  - PR description
  - Target repository and branch
  - Source branch (created from session changes)
**When** I submit the PR creation
**Then** a new branch is created in GitHub
**And** code changes are committed to that branch
**And** a PR is created with the specified title and description
**And** PR link is stored and displayed in session summary
**And** I can navigate to the PR in GitHub
**And** if PR creation fails, I see an error message with details

### Story 10.5: Configure GitHub Repositories for Project

As a project admin,
I want to configure GitHub repositories for my project,
So that agents can access code and create PRs.

**Acceptance Criteria:**

**Given** I am a project admin
**When** I navigate to Project Settings → Integrations
**Then** I can see GitHub integration section
**When** I configure GitHub repositories
**Then** I can add multiple repositories:
  - Repository URL (required)
  - Repository name/alias (for display)
  - Default branch
  - Authentication (uses company-level GitHub secret)
**When** I add a repository
**Then** the repository connection is tested
**And** if successful, the repository is available for:
  - Loading code context
  - Creating PRs
**And** I can edit repository configuration
**And** I can remove repositories
**And** repositories are scoped to the project
