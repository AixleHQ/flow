# Independent edge-case review prompt

Invoke `.agents/skills/bmad-review-edge-case-hunter/SKILL.md` on the complete session-admission implementation diff. Start without the implementation conversation. Work read-only; do not edit source or run tests against the shared database.

App baseline: `32efafaa`. Infra baseline: `c4bff01` in sibling `../aixle-infra`. Include `git diff <baseline>` and every untracked file reported by `git ls-files --others --exclude-standard` in each repository. A captured combined diff is at `/private/tmp/session-admission-review.diff`; prefer current source if newer.

Walk boundary paths for zero/invalid/absent limits, concurrent grants, capacity reductions, pool-mode changes, cancellation before/after relay claims, lease expiry and stale dispatchers, lost Temporal responses, unknown create/start/exec, asynchronous Kubernetes deletion, scope revocation, long queues and workflow-step completion. Check user-visible queued/cancelled states and privacy on each API/UI/MCP surface.

For each real issue, provide its trigger, resulting incorrect behavior and file:line. No deployment, quota deletion or source changes.

The automatic reviewer failed before producing findings because the agent service reported its usage limit. This prompt is the external-review fallback required by bmad-quick-dev step 04.
