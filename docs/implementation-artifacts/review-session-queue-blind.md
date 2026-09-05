# Independent adversarial review prompt

Invoke `.agents/skills/bmad-review-adversarial-general/SKILL.md` on the complete session-admission implementation diff. Start without the implementation conversation. Work read-only; do not edit source or run tests against the shared database.

App baseline: `32efafaa`. Infra baseline: `c4bff01` in sibling `../aixle-infra`. Read `git diff <baseline>` and every untracked file reported by `git ls-files --others --exclude-standard` in each repository. Do not omit new models/services/migrations/tests because they are untracked. A captured combined diff is available at `/private/tmp/session-admission-review.diff`; prefer current source if it differs.

Focus on actual correctness and failure scenarios: atomic concurrency limits, FIFO admission, late runtime publishers, restart/retry delivery, cancellation, cleanup proof, legacy cutover, parent timers and scope/privacy. Report concrete findings with file:line references and reproduction scenarios. Do not assume passing unit tests prove external API contracts.

Return findings only; do not push, deploy, delete quotas or modify running services.

The automatic reviewer failed before producing findings because the agent service reported its usage limit. This prompt is the external-review fallback required by bmad-quick-dev step 04.
