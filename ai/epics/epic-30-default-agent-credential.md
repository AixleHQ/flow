# Epic 30: Default Agent Credential & Profile UI

> User can set a default agent credential on the Profile page. It's auto-set to the latest added credential. Standalone session UI prefills agent_runtime from user's default.

**Phase:** 17 (Depends on: Epic 2 Agent Onboarding)

**Design Document:** [Session Config Cascade](../session-config-cascade.md)

**User Outcome:** Users no longer need to manually select agent runtime every time they start a session. The default is automatically set to the last configured agent and can be changed on the Profile page. All session types (standalone, workflow, board-trigger) use this default as the baseline runtime.

**FRs Covered:** FR-CC4, FR-CC7

---

## Problem

Currently, agent runtime is either hardcoded or selected per-session with no remembered preference. Users who always work with the same agent (e.g., Claude Code) must reselect it every time. When workflows auto-trigger from the board, there's no user preference to fall back to — the system defaults to a hardcoded "claude_code".

This epic adds a `default_agent_credential_id` to User, auto-sets it on credential creation, and surfaces it in the Profile UI and standalone session launch.

---

## Stories

### Story 30.1: User `default_agent_credential_id` Field & Auto-Set

**As a** user,
**I want** my most recently added agent credential to automatically become my default,
**So that** I don't have to manually configure a default after onboarding.

**Acceptance Criteria:**

**Given** a User with no agent credentials
**When** the user creates their first `AgentCredential`
**Then** `user.default_agent_credential_id` is set to the new credential's ID

**Given** a User with an existing default credential
**When** the user creates another `AgentCredential`
**Then** `user.default_agent_credential_id` is updated to the new credential's ID

**Given** a User whose default credential is deleted
**When** the credential is destroyed
**Then** `user.default_agent_credential_id` falls back to the most recent remaining credential (or nil if none left)

**Given** `User#default_agent_credential`
**When** called
**Then** returns the associated `AgentCredential` record (or nil)

**Technical notes:**
- Migration: `add_reference :users, :default_agent_credential, foreign_key: { to_table: :agent_credentials }, null: true`
- `AgentCredential` callback: `after_create :set_as_user_default`
- `AgentCredential` callback: `after_destroy :reassign_user_default`
- Convenience: `User#default_agent_runtime` → `default_agent_credential&.runtime`

---

### Story 30.2: Profile Page — Default Agent Selector

**As a** user,
**I want** to see and change my default agent on the Profile page,
**So that** I can control which agent is used by default across all session types.

**Acceptance Criteria:**

**Given** the Profile page
**When** user navigates to it
**Then** a "Default Agent" section shows the currently selected default credential (name + runtime type)

**Given** the user has 3 agent credentials configured
**When** user clicks to change the default
**Then** a dropdown/selector shows all credentials with their runtime type and name
**And** selecting a different one immediately updates `user.default_agent_credential_id`

**Given** the user has only 1 credential
**When** viewing the default agent section
**Then** it shows the single credential as default with no ability to change (or disabled selector)

**Technical notes:**
- API: `PATCH /api/v1/profile` with `{ default_agent_credential_id: <id> }`
- Frontend: add section to existing ProfilePage component
- Validate that the credential belongs to the user

---

### Story 30.3: Standalone Session Launch — Prefill Default Runtime

**As a** user,
**I want** the standalone session launch form to prefill agent runtime from my default credential,
**So that** I can start sessions faster without reselecting the same agent every time.

**Acceptance Criteria:**

**Given** a user with `default_agent_credential.runtime = "gemini_cli"`
**When** user opens the session launch form (SessionLaunchWidget)
**Then** the agent runtime selector is prefilled with "gemini_cli"

**Given** the user changes the runtime in the form to "claude_code"
**When** the session is created
**Then** the session uses "claude_code" (user override respected)

**Given** a user with no agent credentials
**When** user opens session launch form
**Then** runtime selector shows "claude_code" as default (hardcoded fallback)

**Technical notes:**
- Frontend: `SessionLaunchWidget` reads `user.default_agent_credential_id` (or runtime) from user profile API
- The actual session creation already stores `agent_runtime` on the session — this story only prefills the form
- API: include `default_agent_runtime` in user serializer (or profile endpoint)

---

## Dependency Graph

```
Story 30.1 (Model + auto-set)
    │
    ├──→ Story 30.2 (Profile UI)
    │
    └──→ Story 30.3 (Session launch prefill)
```

---

## Implementation Notes

- `default_agent_credential_id` is a reference, not a string — we store the credential ID, and derive runtime from it
- This allows future flexibility: if credential has metadata beyond runtime type (e.g., API key name, region), the default selection carries all of it
- Auto-set on creation is a simple `after_create` callback — no complex logic
- Profile page already exists — this adds a new section, not a new page
- Standalone session prefill is a frontend-only change (API already exposes user data)
