# Roadmap

> What's planned, what's in flight, and what we've shipped recently.
> This file is the source of truth. The
> [GitHub Projects board][board] mirrors it for live status tracking.

[board]: https://github.com/orgs/palad-ai/projects/1

**Legend:** ✅ shipped · 🟡 in progress · ⬜ planned · 💡 exploring

Items roll up to two named milestones: **v0.1 — Open** (this milestone)
and **v0.2 — Team-ready** (the next).

---

## v0.1 — Open

Goal: the project is publicly releasable. Anyone can clone, run, and
contribute. Documentation, license, and contributor infrastructure are
in place.

| Status | Item                                              | Issue |
| :----: | ------------------------------------------------- | ----- |
| ✅     | Apache 2.0 LICENSE + NOTICE + CLA/DCO contributor model | [#167](https://github.com/palad-ai/palad-app/issues/167) |
| ✅     | Public README with 30-second hook                 | [#167](https://github.com/palad-ai/palad-app/issues/167) |
| ✅     | Tiered docs (Quickstart / User Guide / Reference) | [#167](https://github.com/palad-ai/palad-app/issues/167) |
| ✅     | Public roadmap (this file)                        | [#167](https://github.com/palad-ai/palad-app/issues/167) |
| ✅     | Demo GIF / screenshot in README                   | [#177](https://github.com/palad-ai/palad-app/issues/177) |
| ⬜     | FAQ — drafted from first 2–4 weeks of user questions | [#178](https://github.com/palad-ai/palad-app/issues/178) |
| ⬜     | `SECURITY.md` with private vulnerability reporting | — |
| ⬜     | `CODE_OF_CONDUCT.md` (Contributor Covenant)        | — |
| ⬜     | Issue & PR templates + `CODEOWNERS`                | — |
| ⬜     | 5–10 prepared "good first issue" tickets at launch | — |
| ⬜     | Public CI green (tests, lint, type check)          | — |
| ⬜     | Dependabot + CodeQL turned on                      | — |

---

## v0.2 — Team-ready

Goal: a new team can go from clone to running their first workflow in
under 5 minutes, using a template — no manual configuration of agents
or workflows required.

| Status | Item                                                                                  |
| :----: | ------------------------------------------------------------------------------------- |
| ⬜     | **One-command setup** — `docker compose up` boots web + worker + Temporal in one shot |
| ⬜     | **5 built-in workflow templates** — Code Review, Feature Spec → PR, Bug Triage, Test Generation, Security Scan |
| ⬜     | **Redesigned onboarding** — 5 steps to a first agent run, no docs needed              |
| ⬜     | **Workflow Marketplace v0** — browse and fork community-contributed templates         |
| ⬜     | **Slack notifications** — workflow run status → channel                               |
| ⬜     | **Team Analytics dashboard** — cost, success rate, bottlenecks per workflow           |
| 💡     | **Parallel-agent DAG visual editor**                                                  |
| 💡     | **Deeper GitHub PR integration** — auto-PR from workflow run, CI check status        |

---

## Beyond v0.2

Direction-setting items. Specifics will firm up as v0.2 ships.

- 💡 **Enterprise tier** — SSO (SAML), audit logs, custom data retention.
- 💡 **Aixle Builder v2** — generate a workflow from a freeform task description.
- 💡 **Skills marketplace** — reusable agent skills as a registry.
- 💡 **Public REST API + Headless mode** — trigger runs from GitHub Actions / GitLab CI.
- 💡 **Kubernetes runtime** parity with Docker runtime (already scaffolded behind `CONTAINER_RUNTIME=kubernetes`).
- 💡 **Hosted / cloud offering** — a managed edition with pricing tiers, alongside the self-hosted Apache 2.0 build.

---

## Recently shipped

| Item                                                |
| --------------------------------------------------- |
| Cursor CLI fixes and usage tracking                 |
| MCP Claude timeout configuration                    |
| GitHub App integration                              |

---

## How to influence the roadmap

- **Open a Discussion** for ideas, questions, or proposals.
- **Open an Issue** for bugs or specific feature requests. Use
  `enhancement` for features and `bug` for regressions.
- **Comment on existing issues** if you'd like to see one prioritized.
- Look for [`good first issue`][gfi] if you want to contribute code.

[gfi]: https://github.com/palad-ai/palad-app/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22

The roadmap is **directional, not contractual** — we change it as we
learn. Significant scope changes are announced in repository releases.
