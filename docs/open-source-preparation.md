# Open Source Preparation Checklist

A conceptual plan for getting the repository ready for open-source release. Items are grouped by area, with criticality noted where it matters.

## Starting Point

The initial scope considered:

- Write documentation for everything
- Audit the entire git history for credentials
- Prepare a marketing strategy and decide where to post (Reddit? BMad? awesome-ai lists?)
- Update the landing page
- Set up a place where the community can submit requests and feedback
- Make sure the project deploys with a single command

The sections below expand on what else needs to be in place.

## Legal & Licensing (Critical)

- **LICENSE** — pick one and put it in the repo root. MIT / Apache 2.0 are the most contributor-friendly. AGPL protects against SaaS clones. BSL / Elastic License if commercialization is planned. **This is the single most important missing item.**
- **Dependency license audit** — check for GPL contamination or incompatible licenses across your dependency tree.
- **CLA or DCO** — needed if you want to accept contributions while retaining the ability to relicense later. DCO is lighter weight; CLA gives you stronger control.
- **Copyright headers in source files** — decide whether you need them and apply consistently.

## Security (Beyond Credential Cleanup)

- **SECURITY.md** — defines how to report vulnerabilities (private channel, not a public issue).
- **Audit full git history**, not just current state. Use `gitleaks`, `trufflehog`, or `detect-secrets` against `git log -p`. If anything turns up, you'll need to either rewrite history or do a clean "squash release" with a fresh initial commit.
- **Dependabot / CodeQL** — turn on from day one.
- **Secret scanning on pre-commit** — so secrets don't sneak in after the public release.
- **Strip internal references** — internal URLs, infrastructure names, personal details in code and comments.

## Contributor Infrastructure

- **CONTRIBUTING.md** — dev setup, how to run tests, code style, PR process.
- **CODE_OF_CONDUCT.md** — Contributor Covenant is the de facto standard.
- **Issue templates** (bug, feature, question) and a **PR template**.
- **CODEOWNERS** — who reviews what.
- **"Good first issue" / "help wanted" labels**, plus 5–10 actually prepared issues with those labels ready to go at launch.
- **ARCHITECTURE.md or ADRs** — so a newcomer can ramp up without your help.

## CI/CD & Quality

- Public CI (GitHub Actions): tests, lint, type checking.
- Badges in the README: build status, version, license, stars.
- **Tests must pass publicly** at the moment of release — broken CI on day one is a credibility killer.

## Releases & Distribution

- **Versioning** — semver, git tags.
- **CHANGELOG.md** or GitHub Releases with release notes.
- **Docker image or package** if applicable. A single `docker run ...` or `bundle add ...` command for trying it.
- A documented release process.

## Documentation (Expanding the Original Item)

- **README that hooks in 30 seconds**: what it is, who it's for, why, a gif/screenshot, a 3-command quickstart.
- Tiered docs: Quickstart → User Guide → Reference.
- **Public roadmap** — signals that the project is alive.
- FAQ — best built after the first wave of questions, not before.

## Sustainability & Governance

- **Business model decided upfront**: open core / hosted / dual license / donation-funded. This drives your license choice.
- **GitHub Sponsors / Open Collective** if non-commercial.
- **Governance** — who makes decisions, how new maintainers are added. Set this even when you're the only maintainer; it shapes expectations.
- **Trademark policy** if the name matters.

## Community Channels

- **GitHub Discussions** — better than a separate forum. Native to the repo, better than issues for Q&A and feedback.
- **Discord / Slack / Matrix** — only if you expect active community. Otherwise it just fragments attention.
- **Project Twitter/X or Bluesky account** — for updates.

## Marketing — Where to Post

Channel selection depends on the project type, but here's the general landscape:

### High ROI
- **Show HN (Hacker News)** — the single best channel for dev tooling if you land it well.
- **Lobste.rs** — invite-gated but the audience quality is exceptional.
- **r/programming, r/opensource, r/SideProject** plus **topic-specific subreddits** (r/rails, r/selfhosted, r/LocalLLaMA, etc.).
- **dev.to / Hashnode** — a long-form "how I built this" post pairs well with the launch.

### Medium ROI
- **Product Hunt** — more useful for UX-driven products than dev tools, but star momentum helps.
- **Indie Hackers**.
- **Twitter/X dev community** — works best with warm intros from people already in the network.
- **Awesome-\* lists** (awesome-ai, awesome-selfhosted, etc.) — open PRs to add the project to the relevant ones.

### Low ROI (usually)
- LinkedIn (unless you have a very specific B2B angle).
- Medium.

**Rule of thumb**: one big launch (HN or PH) outperforms ten small posts. Prepare a launch day with the post pre-written, screenshots and a demo video ready, "good first issue" tickets staged, and someone (you) actively replying for the first 4 hours.

## What Not to Do

- **Don't launch** while "first clone → running locally" takes longer than 5 minutes. A user dropped in the first hour is a potential contributor lost.
- **Don't release without a feature that beats the alternatives.** "We open-sourced it" is not a story by itself.
- **Don't open the repo until git history is scrubbed of secrets.** Once it's public, it's too late — assume anything published has been archived somewhere.

## Recommended Sequence

A reasonable order of operations:

1. Legal foundation — pick a license, decide on CLA/DCO, audit dependency licenses.
2. Security pass — scrub git history, set up secret scanning, write SECURITY.md.
3. Repository hygiene — strip internal references, finalize .gitignore.
4. Contributor docs — CONTRIBUTING, CODE_OF_CONDUCT, templates, ARCHITECTURE.
5. One-command setup — verify clone-to-running takes under 5 minutes.
6. Public CI green, badges in place.
7. README polished, demo gif/video produced.
8. Roadmap and "good first issue" tickets staged.
9. Launch day: HN / Reddit / Lobste.rs / dev.to / awesome-list PRs.
10. Be present in the first 24 hours to answer everything.
