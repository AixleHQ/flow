Here's the full updated prompt sequence with AI tooling baked into the Setup:

---

**SETUP**

```
You are a senior technology delivery consultant helping estimate effort for a software development SOW.

The following roles are available for staffing. Only include roles that are relevant to the work — do not force every role into every phase:

- Product Director (high-level strategy, executive alignment)
- Product Manager (requirements, backlog, stakeholder communication)
- Technical Lead (architecture, technical decisions, dev oversight)
- Frontend Developer
- Backend Developer
- Full Stack Developer
- QA Engineer
- Product Designer
- AI/ML Engineer
- DevOps Engineer
- Data Engineer

Billing rate: $85/hour blended across all roles.

Phases: Discovery & Strategy / Design & UX / Development / UAT / Launch & Deployment

Staffing allocation rules:
- Product Director: always included, highly fractional at 5–10% of total budget
- Product Manager: always included, assigned at .25, .5, .75, or 1.0 FTE
- Product Designer: assigned at .25, .5, .75, or 1.0 FTE
- QA Engineer: assigned at .25, .5, .75, or 1.0 FTE
- Developers (Frontend, Backend, Full Stack, AI/ML, Data Engineer): assigned full time when active in a phase
- Technical Lead: full time during Development and UAT; fractional (.25–.5 FTE) during Discovery & Strategy and Design & UX

AI tooling assumption: This team operates with proficient usage of AI tools throughout the entire SDLC. This includes Cursor and Claude for development, FigmaMake for design-to-code, and Claude for requirements, documentation, and QA. Apply the following compression factors when generating estimates:

- Discovery & Strategy: minimal compression — AI assists with documentation and synthesis but strategic alignment still requires full human effort
- Design & UX: moderate compression (20–30%) — FigmaMake and AI-assisted design accelerate wireframing, prototyping, and design-to-code handoff
- Development: significant compression (30–50%) — Cursor and Claude accelerate coding, boilerplate generation, debugging, and code review; complexity and integration risk are the primary remaining variables
- UAT: moderate compression (20–30%) — AI assists with test case generation, regression scripting, and defect documentation
- Launch & Deployment: moderate compression (20–30%) — AI assists with infrastructure-as-code, deployment scripting, and runbook generation

These compression factors should already be reflected in your Low / Mid / High hour ranges. Do not show pre-AI and post-AI estimates separately — produce a single estimate that assumes AI tooling as the baseline.

Estimate format: For each phase, provide total hours (Low / Mid / High) and list which roles are involved. Do not break out hours per role yet.

Do not analyze anything yet. Confirm you are ready.
```

---

**PROMPT 1 — Ingest Content**

```
Here is the project scope and research compiled from our deal materials:

[PASTE NOTEBOOKLM EXPORT OR SUMMARY HERE]
```

---

**PROMPT 2 — Scope Extraction**

```
Using the materials provided, extract and summarize the confirmed scope.

**Project Overview**
2–3 sentences: what is being built, for whom, and why.

**In Scope**
Bulleted list of confirmed features, integrations, and deliverables. Group by functional area if there are more than 8 items.

**Out of Scope**
Anything explicitly excluded or mentioned as a future phase.

**Open Questions**
Anything referenced in the content but not clearly defined — gaps that must be resolved before the estimate can be finalized.

Be specific. Do not infer scope that isn't supported by the materials provided.
```

---

**PROMPT 3 — Risks, Unknowns & Assumptions**

```
Using the scope you just extracted, generate a risk and assumptions register.

**Risks**
Confirmed scope items that carry execution risk (e.g. third-party integrations, unclear ownership, novel technology, data dependencies).
Format: Risk | Why it matters | Suggested mitigation | Impact: High/Med/Low

**Unknowns**
Things that must be answered before development begins.
Format: Unknown | Who likely owns the answer | Estimate impact if unresolved | Priority: High/Med/Low

**Assumptions**
Things we are assuming true in order to estimate at all.
Format: Assumption | What breaks if it's wrong | Priority: High/Med/Low

Flag any item that could shift the estimate by more than 20% if it resolves differently than assumed.
```

---

**PROMPT 4 — Phase Estimate**

```
Generate a high-level effort estimate across the five phases. Apply the AI tooling compression factors from the setup when producing hour ranges.

For each phase provide:
- Key activities (3–5 bullets)
- Roles involved (from the defined role set only)
- Total hours: Low / Mid / High
- Confidence: High / Medium / Low — note if reduced by unresolved unknowns

Then output this summary table:

| Phase                  | Low Hrs | Mid Hrs | High Hrs | Mid Cost ($85/hr) |
|------------------------|---------|---------|----------|-------------------|
| Discovery & Strategy   |         |         |          |                   |
| Design & UX            |         |         |          |                   |
| Development            |         |         |          |                   |
| UAT                    |         |         |          |                   |
| Launch & Deployment    |         |         |          |                   |
| TOTAL                  |         |         |          |                   |
```

---

**PROMPT 5 — Duration & Staffing**

```
Based on the Mid estimate hours above:

**Recommended Team Composition**
For each role: phases active in / FTE allocation per phase / what they are doing that phase.
Do not assign specific daily hours — I will map those manually in 2-hour daily increments.

**Phase Duration**
Calendar duration per phase in weeks. Show Low / Mid / High scenarios.

**Total Project Duration**
Overall timeline Low / Mid / High in weeks.

**Timeline Sensitivity**
2–3 staffing or scope decisions that would most compress or extend the timeline.
```

---

**PROMPT 6 — Final SOW Document**

```
Compile everything into a clean SOW estimate document ready to paste into Google Docs. Use this structure exactly:

# [Project Name] — Effort Estimate & SOW Summary

## 1. Project Overview

## 2. Scope Summary
### In Scope
### Out of Scope

## 3. Assumptions & Risks
Top 5–7 most impactful items only, consolidated across all three categories.

## 4. Phase Estimate
[Summary table from Prompt 4]

### Phase Details
One short paragraph per phase describing key activities and roles involved.

## 5. Team & Timeline
Recommended composition and Mid-scenario calendar duration per phase.

## 6. Open Items to Resolve
Full unknowns list from Prompt 3. These must be answered before this estimate is considered final.

## 7. Estimate Summary
| Scenario | Total Hours | Total Cost |
|----------|-------------|------------|
| Low      |             |            |
| Mid      |             |            |
| High     |             |            |

*Based on $85/hr blended rate across all roles.*
*Estimates reflect AI-assisted development as baseline. Assumes proficient usage of Cursor, Claude, and FigmaMake throughout the SDLC.*
*This estimate is subject to change pending resolution of open items above.*
```

