# Unsaved changes

Task #222. One rule set and one component for the "unsaved changes?" question,
and the inventory of every form in the frontend it was checked against.

## The component

`app/frontend/shared/lib/unsaved-changes/`:

- `useUnsavedChanges({ dirty, opened?, onClose?, onSave? })` registers a form
  and returns its close handler. A dialog or drawer passes that handler as its
  `onClose` and to its Cancel button; a page-level form ignores it.
- `guards.ts` keeps the registry of mounted forms and the one set of listeners
  for every way out: an Inertia visit (`router.on('before')`), browser
  back/forward (`popstate`), reload and tab close (`beforeunload`).
  `allowUnload()` lets one redirect through without asking; `confirmLeave()`
  asks before a leave that is not a GET visit (sign-out).
- `askUnsavedChanges.tsx` is the one question: **Discard unsaved changes?**
  (Keep editing / Discard), or **Save your changes?** (Keep editing / Discard /
  Save) when the form can be saved from it. A reload and a tab close get the
  browser's own prompt, which a page cannot style or word.

The two hooks it replaces — `useConfirmClose` (dialogs, close only) and
`useUnsavedChangesGuard` (the builder, with `window.confirm`) — are gone.

## Rules

**Ask** when a dirty form is left by any way out:

| Way out | How it is caught |
| --- | --- |
| Cancel, ✕, Escape, overlay click | the handler `useUnsavedChanges` returns |
| a link or `router.visit` to another page | Inertia `before` event, visit held and replayed on Discard |
| browser back / forward | `popstate`, caught ahead of Inertia's listener: the page stays, its entry is pushed back on top, and Discard is one `history.back()` to where the user was going |
| reload, typed URL, tab close | `beforeunload` (the browser's own prompt) |
| sign out | `confirmLeave()` around the sign-out `DELETE` |

**Dirty** means the current values differ from the ones the form opened with,
so an edit typed and then undone is not dirty. Compare values, not a "touched"
flag: Mantine's `form.isDirty()`, Inertia's `isDirty` (after `setDefaults()` on
success), or a snapshot taken at mount.

**Don't ask** when:

- the form is not dirty, or is closed — a dialog that stays mounted keeps its
  state, so `opened` must be passed;
- a save is in flight or has just succeeded — pass `dirty: false` while saving,
  and reset the baseline on success;
- the user chose Cancel and then Discard — the question is the confirmation;
- the visit stays on the same page: a reload, a partial reload, a filter or tab
  in the query string, a prefetch, or any non-GET visit (a save — sign-out is
  the one non-GET leave, and asks through `confirmLeave()`);
- the form saves on its own (on blur, on change, on a debounce) or keeps its
  draft across a close on purpose (New Workflow);
- the input is a search, filter, or picker, the screen is read-only, or the
  dialog is a confirmation (delete, archive, cancel subscription, transfer) or a
  single choice that costs one click to redo;
- the page is leaving for a redirect the user cannot stay through: an OAuth
  hand-off, a connect URL, a step-up sign-in (`allowUnload()` first).

**Save in the question** is offered only by a page whose form has one Save
action (the builder, project and company settings, profile, MCP tools), and only
while the form is valid. A dialog offers Discard and Keep editing: its own Save
button is in view.

**Edge cases:**

- *Validation errors on leave* — Save is not offered; Discard and Keep editing
  are.
- *A save that fails* — the question closes, the user stays on the form, and
  the form shows why; the next leave asks again.
- *A dialog over a dirty page* — each registers on its own. Its own close asks
  about the dialog alone; leaving the page asks once for both.
- *Several dirty forms* — one question; no Save, because one Save would keep
  only part of the changes.
- *Session expiry* — not asked: an Inertia visit that hits an expired session is
  already a leave the user started, and a step-up redirect goes through
  `allowUnload()`.
- *A second ask while the question is open* is dropped, and the Escape that
  answers the question does not re-open it.

**Known gap.** Switching to another task on the board (`?n=`) stays on the
page, so it does not ask; the task sidebar clears its comment draft when the
task changes. A form whose content is swapped in place has to route that swap
through its close handler itself.

## Inventory

How each form saves, what it did before #222, and what it does now. "Close"
means Cancel, ✕, Escape and the overlay; "leave" means a visit to another page,
back/forward, reload and tab close.

### Pages

| Form | Saves | Before | Now |
| --- | --- | --- | --- |
| Workflow builder (`Projects/Workflows/BuilderPage`) | Save button | leave: `window.confirm` + `beforeunload`; no back/forward | leave asked, with Save |
| Builder session/step panels (`SessionEditorPanel`, `StepEditorPanel`) | into the builder draft; session name on blur | covered by the builder | covered by the builder |
| Project settings (`Projects/Settings/SettingsPage`) | Save button | nothing | leave asked, with Save |
| Company settings (`Company/Settings/SettingsPage`) | Save button | nothing | leave asked, with Save |
| Company access — new SSO connection (`Company/Settings/AccessPage`) | Add connection | nothing | leave asked |
| Company access — switches | on change | — | not asked (saves itself) |
| Profile (`Profile/Show`) — name, language, sharing | Save button | nothing | leave asked, with Save |
| Profile — default runtime, model | on change | — | not asked (saves itself) |
| Profile password (`Profile/PasswordSection`) | Save password | nothing | close and leave asked |
| Profile MCP tools (`Profile/Mcp`) | Save tools | nothing | leave asked, with Save |
| Profile security — TOTP code (`Profile/Security`) | Confirm | nothing | not asked (one-time code) |
| Template install (`Templates/InstallPage`) | Install | nothing | leave asked |
| New workspace (`Workspaces/NewPage`) | Create | nothing | leave asked |
| Onboarding (`Onboarding/OnboardingPage`) | autosave on change | — | not asked (saves itself) |
| Sign-in, password reset, SSO choice, step-up, invitation, legal accept (`Auth/*`, `Invitations/Show`, `Legal/AcceptPage`) | submit | nothing | not asked (one-shot auth forms) |
| YouTrack / Bitbucket connect pages (`Integrations/*`) | submit, then redirect | nothing | not asked (one field, redirects) |
| Marketplace proposal (`Marketplace/ProposalPage`) | buttons | — | not asked (no input) |
| Board, sessions, catalog, templates, docs search and filters | — | — | not asked (search / filter) |

### Board

| Form | Saves | Before | Now |
| --- | --- | --- | --- |
| New task drawer (`BoardPage`) | Create | close asked | close and leave asked |
| Board settings (`BoardSettingsDialog`) | Save | close asked | close and leave asked |
| Task sidebar — new comment, edited comment (`TaskDetailSidebar`) | Comment / Save | close asked for a new comment only | close and leave asked for both |
| Task sidebar — title, description, fields, tags (`InlineTagsEditor`) | on blur / on change | — | not asked (saves itself) |
| Bulk tag (`SelectionBar`) | Add | close asked | close and leave asked |
| View presets (`ViewPresetMenu`) | Save preset | nothing | not asked (one name in a menu) |
| Delete task / comment | — | — | not asked (confirmation) |

### Project resources

| Form | Before | Now |
| --- | --- | --- |
| Agent (`AgentFormModal`), Wrapper (`ToolFormModal`), Skill (`ManualSkillModal`), Connector (`McpServerFormModal`), Secret (`ConfigItemFormModal`), Runner (`RunnerFormModal`) | close asked | close and leave asked |
| Connector install (`ConnectorInstallModal`), AWS Bedrock (`AwsConnectionModal`) | close asked | close and leave asked |
| Repository add / edit (`AddRepositoryModal`, `EditRepositoryModal`) | close asked | close and leave asked |
| Tracker add / handle / column (`AddTrackerDrawer`, `EditHandleDrawer`, `ConnectColumnDrawer`) | close asked | close and leave asked |
| Integrations: GitHub, GitLab, Bitbucket, Jira, Linear, YouTrack, Azure DevOps connect; Coder; token replace; GitHub/GitLab/Jira/Linear project pickers (`integrations/*`) | close asked | close and leave asked; OAuth hand-offs through `allowUnload()` |
| Trigger panel (`TriggerFormPanel`) | nothing | close and leave asked |
| Chat channel connect (`ConnectChannelModal`) | nothing | close and leave asked until a code is issued |
| Invite member (`InviteMemberDrawer`), Add member (`Projects/Members/MembersPage`) | close asked | close and leave asked |
| Asset upload, folder (`AssetsContent`, `FolderFormModal`) | close asked | close and leave asked |
| Run workflow (`RunWorkflowDrawer`), New session (`NewSessionDrawer`) | close asked | close and leave asked |
| Edit workflow (`WorkflowsPage`) | close asked | close and leave asked |
| New workflow (`WorkflowsPage`) | keeps its draft across a close | unchanged (keeps the draft) |
| GitLab group, Atlassian, Teams approval, connector update, tool drift, move to folder, transfer ownership, project handover | nothing | not asked (a single choice or a confirmation) |
| Delete folder, archive, cancel subscription | nothing | not asked (confirmation) |

### App-wide

| Form | Before | Now |
| --- | --- | --- |
| Create project (`CreateProjectModal`) | close asked | close and leave asked |
| Send feedback (`FeedbackModal`) | close asked | close and leave asked |
