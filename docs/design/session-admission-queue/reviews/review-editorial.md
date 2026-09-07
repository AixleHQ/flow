# Editorial review

Reviewed TECH-DESIGN.md for human readers: developers and infrastructure maintainers. The document exists to help them agree on session admission behavior and implement a migration without losing queued work or exceeding capacity. Main structure: recommendation → evidence → rules → implementation → operations → rollout → validation.

## Structure

Input valid: substantial Markdown, human audience. Initial section map: recommendation 210 words; current system 561; policy 510; architecture/data 888; state/UI 466; workflows 349; runtime capacity 307; recovery 362; infrastructure 216; rollout 329; implementation/tests 313; alternatives 221. Counts preceded technical-review corrections.

- PRESERVE recommendation and A1 first: the installation/company distinction determines the design's scope.
- PRESERVE three diagrams and configuration/quota examples: they connect queue behavior to concrete code and deployment.
- PRESERVE separate recovery, rollout and test tables: they address steady state, transition and verification respectively.
- CLARIFY terminology at first architecture use: admission, permit, relay and reconciler are distinct responsibilities. Added a short definition paragraph.
- CUT final repeated result paragraph: already conveyed by the opening. Removed approximately 40 words.

No substantive reordering needed. No length target; comprehension retained.

## Prose

Frontmatter, identifiers and code blocks are excluded from copy editing. Technical prose retains existing code and domain identifiers.

| Original | Revision | Reason |
|---|---|---|
| Admission/permit/relay used without a compact definition | Definitions at start of §4 | Distinguishes queue membership, reserved capacity and delivery |
| Ownership filter on runtime-origin ambiguous about resource | Explicit runtime-origin on namespace; quotas have no ownership labels | Correct interpretation and safer migration procedure; technical review correction |
| Initial Pod create-attempt wording | Runtime operation ledger for every resource create/start | Removes misleading scope restriction; technical review correction |

Final wording keeps unapproved choices labelled as proposals. A finalized writing run is not architecture approval: spine has `decision_status: proposed`.
