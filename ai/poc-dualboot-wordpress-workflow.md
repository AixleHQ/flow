# PoC: DualBoot Partners WordPress Workflow

**Date:** 2026-03-05
**Status:** Draft
**Author:** Artem Petrov + AI Analysis
**Goal:** Prove Palad's value by building a semi-automated WordPress site management workflow

---

## 1. Executive Summary

We create a "dualbootpartners.com" project in Palad, connect WordPress MCP + Playwright MCP, set up a board with 9 columns, and bind automated workflows to transitions between columns. Tasks like "Update the About Us block" go through the full cycle: discovery → tech design → implementation → QA → review → release.

**What this proves to the CEO:**
- Palad can orchestrate real work with a real production site
- Agents read the task context, traverse the WordPress API, write documents, make changes
- A human manages the process through the board (dragging cards), not through code
- Semi-automation: the agent does the rough work, the human approves/rejects

---

## 2. MCP Servers

### 2.1 WordPress MCP Server

**Chosen solution:** `@automattic/mcp-wordpress-remote` (npm)

**Rationale:**
- Official package from Automattic (the creators of WordPress)
- TypeScript, supports OAuth 2.1, JWT, Application Passwords
- Full MCP compatibility (tools, resources, prompts)
- Actively maintained (v0.2.19, Feb 2026)
- Can connect to self-hosted WordPress via Application Passwords

**What it can do:**
- Read/write posts and pages (CRUD)
- Manage media files
- Read/change theme settings
- Work with custom fields and meta
- Read site structure (menus, widgets, taxonomies)

**How to connect it in Palad:**
1. Create an MCP Server record (scope: Project "dualbootpartners.com")
2. URL: endpoint from mcp-wordpress-remote (HTTP transport)
3. Headers: WordPress Application Password or JWT token
4. Or: run mcp-wordpress-remote as a sidecar in the agent container

**Alternative option (simpler for PoC):**
Use `mcp-wp` (PHP plugin) — it installs directly on the WordPress site and exposes the endpoint `wp-json/mcp/v1/mcp`. No separate server needed.

| Option | Pros | Cons | Recommendation |
|---|---|---|---|
| `@automattic/mcp-wordpress-remote` (npm) | Official, rich API | Requires a separate process | For prod |
| `mcp-wp` (PHP plugin on WP) | Simplicity, endpoint directly on the site | Less mature | **For PoC** |
| WordPress REST API directly (via curl in the agent) | No MCP | No structure, prompts are harder | Fallback |

### 2.2 Browser / Playwright MCP Server

**Chosen solution:** `@playwright/mcp` (npm, by Microsoft)

**Rationale:**
- Official MCP from Microsoft (the creators of Playwright)
- 22 tools: navigate, click, type, screenshot, evaluate JS, etc.
- Headless mode for Docker containers
- Accessibility tree instead of vision — deterministic and cheap on tokens
- Docker image available on Docker Hub

**What it can do:**
- Navigation by URL
- Screenshots (full page, element, viewport)
- Interactive actions (click, type, scroll)
- Reading the DOM / accessibility tree
- Running JavaScript
- PDF generation

**How to connect it in Palad:**
1. Create an MCP Server record (scope: Project "dualbootpartners.com")
2. Run Playwright MCP in headless mode (Docker sidecar or standalone)
3. URL: `http://playwright-mcp:8931/mcp` (HTTP transport)

**Docker inside the agent container:**
Playwright MCP requires headless Chromium. Options:
- **Sidecar container**: a separate container with Playwright MCP, linked to the agent
- **Installed in agent image**: add `npx @playwright/mcp@latest --headless` to the base image
- **External service**: Playwright MCP as a separate service in docker-compose

For the PoC I recommend: **external service** (docker-compose), because Chromium is heavy.

---

## 3. Board Configuration

### 3.1 Preset: WordPress Workflow

Add a new preset to `BoardPresets`:

```
Key: wordpress_workflow
Display Name: "WordPress Site Workflow"
Columns:
  1. Backlog           — Tasks described by human, waiting to be picked up
  2. Discovery         — Agent explores WP site, produces site overview document
  3. Tech Design       — Agent writes technical design based on task + discovery
  4. Ready for Dev     — Human reviews tech design, approves for implementation
  5. In Dev            — Agent makes changes via WordPress MCP
  6. QA                — Agent takes screenshots via Playwright, produces QA report
  7. Review            — Human reviews changes + screenshots, approves or rejects
  8. Ready for Release — Approved, waiting for deploy
  9. Released          — Agent publishes changes to production
```

### 3.2 Column Purpose Descriptions

| Column | Purpose (for the agent) |
|---|---|
| Backlog | New task with requirements. Human writes what needs to change on the site. |
| Discovery | **AUTO workflow.** Read task description. Use WordPress MCP to explore current site state: pages, posts, themes, styles, plugins, menus. Produce a site discovery document as task asset. |
| Tech Design | **AUTO workflow.** Read task + discovery document. Plan specific changes: which pages/templates/CSS/plugins to modify. Produce tech design document as task asset. |
| Ready for Dev | Human reviews tech design. If approved, moves to In Dev. If rejected, adds comment and moves back. |
| In Dev | **AUTO workflow.** Read task + tech design. Execute changes via WordPress MCP: update pages, CSS, settings, media. Produce change log as task asset. |
| QA | **AUTO workflow.** Read task + change log. Navigate site with Playwright MCP, take before/after screenshots. Produce QA report with screenshots as task assets. |
| Review | Human reviews: change log + screenshots + QA report. Can move to Ready for Release or back to any column with a comment. |
| Ready for Release | **AUTO workflow.** Publish/activate changes if they were on staging. Mark task as released. Move to Released. |
| Released | Done. Task completed and changes live on production. |

### 3.3 Column Workflow Bindings

| Column | Trigger Mode | Workflow |
|---|---|---|
| Backlog | — | No workflow |
| Discovery | **auto** | WP: Site Discovery |
| Tech Design | **auto** | WP: Tech Design |
| Ready for Dev | — | No workflow (human gate) |
| In Dev | **auto** | WP: Implementation |
| QA | **auto** | WP: QA Check |
| Review | — | No workflow (human gate) |
| Ready for Release | **auto** | WP: Release |
| Released | — | No workflow |

---

## 4. Agents

### 4.1 WordPress Developer Agent

```yaml
name: wp_developer
title: WordPress Developer
scope: Project (dualbootpartners.com)
persona: |
  You are an experienced WordPress developer specializing in theme customization,
  plugin configuration, content management, and site optimization.
  
  You have deep knowledge of:
  - WordPress REST API and its capabilities
  - Theme structure (header, footer, templates, child themes)
  - CSS customization and responsive design
  - WordPress block editor (Gutenberg) and classic editor
  - Plugin ecosystem and configuration
  - WordPress best practices for performance and SEO
  
  You work methodically: first understand the current state, then plan changes,
  then implement carefully with rollback awareness.
  
communication_style: |
  Professional and methodical. Always document what you're doing and why.
  When making changes, explain what existed before and what you're changing.
  Use structured formats (markdown) for reports and documents.
  
principles: |
  - Never make destructive changes without documenting the original state first
  - Always produce clear documentation of what was changed
  - Test assumptions by reading current state before modifying
  - When in doubt, prefer non-breaking changes
  - Save all outputs as structured markdown files
```

### 4.2 QA Agent

```yaml
name: wp_qa_engineer
title: WordPress QA Engineer
scope: Project (dualbootpartners.com)
persona: |
  You are a QA engineer specializing in web application testing.
  You verify visual and functional changes on WordPress sites
  by navigating pages, taking screenshots, and comparing with requirements.
  
  You focus on:
  - Visual regression: does the change look correct?
  - Responsive design: check desktop, tablet, mobile viewports
  - Functional testing: do links, forms, and interactions work?
  - Cross-page impact: did the change break anything else?
  - Accessibility: basic WCAG compliance checks

communication_style: |
  Structured QA reports with clear pass/fail criteria.
  Screenshots with annotations. Severity classification for issues found.

principles: |
  - Always take screenshots of affected areas
  - Check at least 3 viewport sizes (desktop 1920px, tablet 768px, mobile 375px)
  - Compare with task requirements explicitly
  - Report issues with severity: Critical / Major / Minor / Cosmetic
  - Produce a clear QA report even if everything passes
```

---

## 5. Workflows

### 5.1 WP: Site Discovery

**Trigger:** Task enters "Discovery" column (auto)
**Agent:** wp_developer
**Mode:** non_interactive

#### Steps:

**Step 1: Explore Site Structure**

Sub-steps:
1. Read task description
2. List all pages and their structure
3. Identify current theme and customizations
4. List active plugins
5. Document menus and navigation
6. Note relevant CSS/style patterns

Instructions:
```markdown
You are performing site discovery for a WordPress modification task.

## Your Task
Read the board task description to understand what needs to change.
Then explore the WordPress site thoroughly using the WordPress MCP tools.

## Process
1. **Read the task** — Use `board_get_task` to get full task details and comments
2. **Explore pages** — Use WordPress MCP to list all pages, identify which ones are relevant to the task
3. **Check theme** — Identify active theme, any child theme customizations
4. **List plugins** — Document active plugins that might be relevant
5. **Document structure** — Menus, widgets, sidebars that relate to the task area
6. **CSS/Styles** — Note relevant style patterns and customization points

## Output
Create a structured markdown document:
- Site overview (pages, theme, key plugins)
- Current state of the area that needs to change
- Technical notes for implementation

Save as `discovery.md` in `/workspace/outputs/`.

Then add a summary comment to the task using `board_add_comment`.
Mark each sub-step as you complete it.
When done, call `finish_session`.
```

---

### 5.2 WP: Tech Design

**Trigger:** Task enters "Tech Design" column (auto)
**Agent:** wp_developer
**Mode:** non_interactive

#### Steps:

**Step 1: Create Technical Design**

Sub-steps:
1. Read task and discovery document
2. Analyze what needs to change
3. Identify specific WordPress objects to modify
4. Write implementation plan
5. Document rollback strategy

Instructions:
```markdown
You are creating a technical design for a WordPress modification task.

## Context
The previous step produced a site discovery document. It's available in `/workspace/assets/`.
Read it along with the task description.

## Process
1. **Read inputs** — Task description (`board_get_task`) + discovery document from assets
2. **Analyze scope** — What exactly needs to change? Which pages, templates, CSS rules, plugin settings?
3. **Plan changes** — For each change:
   - What WordPress API endpoint / method to use
   - What the current value is (verify via MCP)
   - What the new value should be
   - Potential side effects
4. **Rollback plan** — How to revert each change if needed
5. **Write design document**

## Output
Create `tech-design.md` in `/workspace/outputs/` with:
- Summary of changes
- Detailed change list (what → endpoint → current value → new value)
- Rollback plan
- Risk assessment (what could go wrong)

Add a comment to the task with a brief summary.
When done, call `finish_session`.
```

---

### 5.3 WP: Implementation

**Trigger:** Task enters "In Dev" column (auto)
**Agent:** wp_developer
**Mode:** non_interactive

#### Steps:

**Step 1: Implement Changes**

Sub-steps:
1. Read task and tech design
2. Verify current state matches expectations
3. Execute changes via WordPress MCP
4. Verify each change was applied
5. Document all changes made

Instructions:
```markdown
You are implementing WordPress changes based on the approved technical design.

## Context
The tech design document is in `/workspace/assets/`. Read it carefully.

## Process
1. **Read tech design** — From assets. Understand every planned change.
2. **Pre-check** — For each planned change, verify the current state via WordPress MCP.
   If current state doesn't match expectations from tech design, STOP and fail with explanation.
3. **Execute changes** — Apply each change via WordPress MCP tools:
   - Update pages/posts content
   - Modify theme settings/customizer options
   - Update CSS/styles
   - Configure plugin settings
   - Upload media if needed
4. **Post-check** — After each change, verify it was applied correctly by reading back.
5. **Document** — Record every change in a change log.

## Output
Create `change-log.md` in `/workspace/outputs/` with:
- Each change: what was changed, before value (truncated), after value, API used
- Timestamp of changes
- Any warnings or unexpected behaviors

Add a summary comment to the task.

## CRITICAL RULES
- If ANY pre-check fails (current state differs from expected), call `fail_session` with explanation
- Never skip the post-check verification
- If a change fails, document the error and continue with remaining changes
- At the end, if any changes failed, call `fail_session`; otherwise `finish_session`
```

---

### 5.4 WP: QA Check

**Trigger:** Task enters "QA" column (auto)
**Agent:** wp_qa_engineer
**Mode:** non_interactive

#### Steps:

**Step 1: Visual QA**

Sub-steps:
1. Read task and change log
2. Navigate to affected pages
3. Take desktop screenshots
4. Take tablet screenshots
5. Take mobile screenshots
6. Check for visual regressions

**Step 2: Produce QA Report**

Sub-steps:
1. Compare screenshots with requirements
2. Classify any issues found
3. Write QA report

Instructions (Step 1):
```markdown
You are performing QA on WordPress changes.

## Context
Read the task description and the change log from `/workspace/assets/`.
Understand what was changed and what the expected result should be.

## Process
1. **Read context** — Task (`board_get_task`) + change log from assets
2. **Identify pages to check** — Based on what was changed
3. **Desktop screenshots** (1920x1080) — Navigate to each affected page, take full-page screenshot
4. **Tablet screenshots** (768x1024) — Resize viewport, take screenshots
5. **Mobile screenshots** (375x812) — Resize viewport, take screenshots
6. **Functional checks** — Click key links, verify navigation works, check forms if relevant

Use Playwright MCP tools:
- `browser_navigate` to go to pages
- `browser_resize` to change viewport
- `browser_screenshot` to capture state
- `browser_click` to test interactions

Save all screenshots to `/workspace/outputs/screenshots/`.

Mark each sub-step as you complete it.
```

Instructions (Step 2):
```markdown
Review all screenshots taken in Step 1.

## Process
1. For each screenshot, compare with the task requirements
2. Classify findings:
   - PASS: Change looks correct at this viewport
   - FAIL (Critical): Something is broken
   - FAIL (Major): Significant visual issue
   - FAIL (Minor): Small cosmetic issue
3. Write QA report

## Output
Create `qa-report.md` in `/workspace/outputs/` with:
- Summary: PASS / FAIL (with count by severity)
- Per-page results with screenshot references
- Issues found with severity and description
- Recommendation: approve / needs fixes

Attach screenshots and report to the task using `board_attach_asset`.
Add a summary comment to the task.
Call `finish_session`.
```

---

### 5.5 WP: Release

**Trigger:** Task enters "Ready for Release" column (auto)
**Agent:** wp_developer
**Mode:** non_interactive

#### Steps:

**Step 1: Publish Changes**

Sub-steps:
1. Read task and verify all assets present
2. Activate/publish any draft changes
3. Clear caches if applicable
4. Verify live site
5. Move task to Released

Instructions:
```markdown
You are releasing approved WordPress changes to production.

## Context
This task has been reviewed and approved. Check task assets for the complete history:
discovery → tech design → change log → QA report.

## Process
1. **Verify readiness** — Read task and all its comments. Ensure there's an approval (no blocking comments).
2. **Publish changes** — If changes were saved as drafts or in staging:
   - Publish draft pages/posts
   - Activate theme changes
   - Enable any configuration that was staged
3. **Cache management** — If the site uses caching plugins, clear relevant caches via WordPress MCP.
4. **Verification** — Read back the published content to confirm changes are live.
5. **Move task** — Use `board_move_task` to move to "Released" column.

## Output
Create `release-notes.md` in `/workspace/outputs/` with:
- What was released
- When (timestamp)
- Verification status

Add a final comment to the task: "Released to production ✓"
Call `finish_session`.
```

---

## 6. MCP Server Configuration in Palad

### 6.1 WordPress MCP Server Record

```yaml
name: wordpress-dualboot
display_name: "WordPress — dualbootpartners.com"
description: "WordPress MCP server for dualbootpartners.com. Provides read/write access to pages, posts, themes, media, and settings."
kind: custom
scope: Project (dualbootpartners.com)
transport: http  # or sse depending on implementation
url: "https://dualbootpartners.com/wp-json/mcp/v1/mcp"  # if using mcp-wp plugin
# url: "http://wordpress-mcp:3000/mcp"                    # if using npm package
enabled: true
headers:
  Authorization: "Basic <base64(user:application_password)>"
```

### 6.2 Playwright MCP Server Record

```yaml
name: playwright-browser
display_name: "Playwright Browser"
description: "Browser automation for visual testing. Navigate pages, take screenshots, interact with elements."
kind: custom
scope: Project (dualbootpartners.com)
transport: http
url: "http://playwright-mcp:8931/mcp"
enabled: true
```

### 6.3 Workflow Base Resources

Each workflow should include these MCP servers in base resources:

| Workflow | WordPress MCP | Playwright MCP | Context7 |
|---|---|---|---|
| WP: Site Discovery | ✓ | — | — |
| WP: Tech Design | ✓ | — | — |
| WP: Implementation | ✓ | — | — |
| WP: QA Check | — | ✓ | — |
| WP: Release | ✓ | — | — |

---

## 7. Infrastructure Setup

### 7.1 WordPress MCP Server (PHP Plugin approach for PoC)

Install on dualbootpartners.com:
```bash
# Install MCP for WordPress plugin
wp plugin install mcp-wp --activate
# Or via WP admin: Plugins → Add New → search "MCP for WordPress"

# Create Application Password for API access
wp user application-password create admin "palad-mcp" --porcelain
# Save the generated password
```

### 7.2 Playwright MCP Server (Docker)

Add to Palad's docker-compose (or run standalone):
```yaml
services:
  playwright-mcp:
    image: mcr.microsoft.com/playwright:v1.50.0-noble
    command: npx @playwright/mcp@latest --headless --port 8931
    ports:
      - "8931:8931"
    environment:
      - NODE_ENV=production
    deploy:
      resources:
        limits:
          memory: 2G
```

### 7.3 Staging Environment

**CRITICAL:** For PoC, work on a staging copy of dualbootpartners.com.

Options:
- WP staging plugin (WP Staging, Jetstash)
- Separate subdomain: staging.dualbootpartners.com
- Local copy via wp-cli: `wp db export` + `wp search-replace`

---

## 8. Demo Scenarios

### 8.1 Scenario 1: "Update the About Us section" (Simple)

**Task description:**
> Update the About Us page. Change the company description to include our new AI capabilities.
> Current text starts with "Dualboot Partners is a software development company..."
> Add a paragraph about our AI-powered automation platform Palad.

**Expected flow:**
1. Human creates task in Backlog with description
2. Human moves to Discovery → Agent explores site, finds About page, documents structure
3. Auto-moves to Tech Design → Agent plans: update page content via REST API
4. Human reviews tech design, moves to In Dev
5. Agent updates page content via WordPress MCP
6. Auto-moves to QA → Agent screenshots About page at 3 viewports
7. Human reviews screenshots, moves to Ready for Release
8. Agent publishes (if draft) or confirms live

### 8.2 Scenario 2: "Add new team member to the Team page" (Medium)

**Task description:**
> Add new team member: John Smith, Senior AI Engineer.
> Photo will be uploaded as task asset.
> Follow the existing team member card format.

### 8.3 Scenario 3: "Update site-wide header CTA button" (Complex)

**Task description:**
> Change the header CTA button from "Contact Us" to "Get Started".
> Update the link to point to /get-started instead of /contact.
> Make the button color match our brand purple (#6B46C1).
> This affects all pages.

---

## 9. Success Metrics

| Metric | Target |
|---|---|
| End-to-end task completion (Backlog → Released) | Works for all 3 demo scenarios |
| Agent correctly reads WordPress content via MCP | 100% |
| Agent correctly modifies WordPress content via MCP | > 80% (some may need retry) |
| QA screenshots captured at 3 viewports | 100% |
| Human intervention points work (Review gates) | 100% |
| Total time per task (excl. human review) | < 15 min |
| Documents produced (discovery, tech design, change log, QA report) | All present and readable |

---

## 10. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| WordPress MCP server doesn't expose needed operations | Medium | High | Fallback: agent uses curl + WP REST API directly |
| Playwright MCP can't screenshot external site (CORS/auth) | Low | Medium | Playwright controls real browser, no CORS issues |
| Agent makes incorrect WordPress changes | Medium | High | Use staging environment; changes are reversible |
| WordPress Application Passwords not enabled | Low | Medium | Enable in wp-config.php or use JWT plugin |
| Playwright container too heavy for Palad infra | Low | Medium | Run as external service, not sidecar |
| Agent instructions too vague → poor output quality | High | Medium | Iterate on prompts after first runs |
| Board MCP tools incomplete (missing implementations) | Medium | High | Verify all board_* tools work before PoC |

---

## 11. Implementation Plan

### Phase 0: Verification & Prep (1 day)

- [ ] Verify board MCP tools (board_get_task, board_add_comment, board_move_task, board_attach_asset) are working
- [ ] Set up staging copy of dualbootpartners.com
- [ ] Test WordPress REST API access with Application Password
- [ ] Verify Palad workflow auto-trigger works end-to-end on existing board

### Phase 1: MCP Server Setup (1-2 days)

- [ ] Install WordPress MCP on staging site (mcp-wp plugin or npm server)
- [ ] Test WordPress MCP tools manually (list pages, read page, update page)
- [ ] Set up Playwright MCP server (Docker)
- [ ] Test Playwright MCP tools manually (navigate, screenshot)
- [ ] Register both MCP servers in Palad (DB records)
- [ ] Verify MCP servers are accessible from agent containers

### Phase 2: Board & Agents Setup (0.5 day)

- [ ] Add `wordpress_workflow` preset to BoardPresets (optional — can create custom)
- [ ] Create project "dualbootpartners.com" in Palad
- [ ] Create board with 9 columns (or use preset)
- [ ] Create Agent: wp_developer
- [ ] Create Agent: wp_qa_engineer

### Phase 3: Workflows (1-2 days)

- [ ] Create Workflow: "WP: Site Discovery" (1 step, 6 sub-steps)
- [ ] Create Workflow: "WP: Tech Design" (1 step, 5 sub-steps)
- [ ] Create Workflow: "WP: Implementation" (1 step, 5 sub-steps)
- [ ] Create Workflow: "WP: QA Check" (2 steps, 6+3 sub-steps)
- [ ] Create Workflow: "WP: Release" (1 step, 5 sub-steps)
- [ ] Bind workflows to columns (auto-trigger)
- [ ] Configure base_mcp_server_ids for each workflow

### Phase 4: First Run & Iteration (2-3 days)

- [ ] Create first test task (Scenario 1: Update About Us)
- [ ] Run through Discovery — observe, debug, fix prompts
- [ ] Run through Tech Design — observe, debug, fix prompts
- [ ] Run through Implementation — observe, debug, fix prompts
- [ ] Run through QA — observe, debug, fix prompts
- [ ] Run through Release — observe, debug, fix prompts
- [ ] Iterate on agent instructions based on results
- [ ] Run Scenario 2 and 3

### Phase 5: Demo Prep (1 day)

- [ ] Clean up board, prepare demo task
- [ ] Record or script demo flow
- [ ] Document what works and what needs improvement
- [ ] Prepare talking points for CEO presentation

**Total estimate: 6-9 days**

---

## 12. What Might Need Development in Palad

During PoC, we may discover gaps. Predicted issues:

| Issue | Likelihood | Workaround | Fix needed |
|---|---|---|---|
| Board MCP tools not fully implemented | High | Manual API calls or seed data | Implement missing InternalTools |
| MCP server auth not passed to agent container properly | Medium | Manual env vars | SessionConfigResolver update |
| Workflow can't reference project-scoped MCP servers | Low | Add to base_mcp_server_ids | Should work already |
| Agent can't access Playwright screenshots as files | Medium | Save to /workspace/outputs/ via agent code | May need Playwright output-dir config |
| Workflow step can't use 2 different agents (QA vs Dev) | Low | Separate workflows per agent | Step-level agent override works |
| board_attach_asset tool doesn't exist or doesn't work | High | Agent saves to outputs, human attaches | Implement InternalTools::BoardAttachAsset |

---

## 13. Files to Create/Modify

| File | Action | Description |
|---|---|---|
| `app/services/board_presets.rb` | Modify | Add `wordpress_workflow` preset |
| `db/seeds/dualboot_wordpress.rb` | Create | Seed: project, board, agents, workflows, MCP servers, bindings |
| `db/seeds.rb` | Modify | Require new seed file |
| Agent container base image | Possibly modify | Ensure npm/node available for MCP server access |
| `docker-compose.yml` | Modify | Add Playwright MCP service |

---

_Document generated 2026-03-05_
