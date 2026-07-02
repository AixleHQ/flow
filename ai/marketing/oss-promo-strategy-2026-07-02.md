# Aixle Flow — Open-Source Launch Marketing Strategy

**Owner:** solo founder · **Budget:** $0 · **Audience:** none yet · **Production:** Claude Code + installed skills · **Goals:** GitHub stars, self-host installs, developer mindshare

---

## 1. Executive summary

Aixle Flow launches into a crowded "AI agent platform" market with two claims no visual-builder competitor can make: **every agent runs in its own Docker sandbox by default** (n8n, Dify, Flowise, and Sim all execute tools in-process) and **runs are durable** (Temporal-backed, crash-safe, resumable, with human/CI gates). The launch strategy is built entirely around earned attention from zero: Hacker News is the only channel that pays unknown founders, so everything sequences toward one anchor moment — a Show HN with a license-led, incumbent-anchored title, a verified two-command quickstart, and a pre-written first comment that answers "how is this different from n8n?" before anyone asks.

Three big bets:

1. **The repo is the landing page.** Before anything drives traffic, the README gets the 8-second drag-to-agent hero GIF, capability loops, the honest comparison table, and the install block. This multiplies conversion of every other idea, forever.
2. **One anchor, many feeders.** A single Show HN launch week, fed by pre-drafted Reddit/X/LinkedIn content and two cheap warm-up engineering posts, followed 2–3 weeks later by Product Hunt as a second spike.
3. **Compound after the spike.** A weekly Friday release train, monthly open-metrics "The Bill" posts, and borrowed audiences (Ruby newsletters, self-host YouTubers, Temporal/Coder co-marketing) convert launch attention into durable mindshare.

90-day success: 3,000+ GitHub stars, 300+ verified self-host installs, one 150+ point HN post, one creator video, one partner feature.

---

## 2. Positioning & messaging

**One-liner:** Aixle Flow is an open-source, self-hosted Kanban board where moving a card launches AI coding agents in Docker containers — watch them live in a browser terminal, gate them on CI, and track every token they spend.

**Elevator pitch:** Agents are everywhere; orchestration is missing. Teams run Claude Code, Codex, Cursor, and Gemini agents by hand — handoffs in Slack, no isolation, no record, no cost visibility. Aixle Flow makes the Kanban board the control plane: bind a workflow to a column, drop a card in, and agents boot in isolated containers, execute a Temporal-backed DAG with parallel branches and human/CI approval gates, and report every token spent. AGPLv3, runs entirely in your Docker, your code never leaves your infrastructure.

**Three message pillars (each maps to a verified competitor gap):**

1. **"Every agent runs in its own Docker sandbox — and you can watch it."** The 2026 HN sandbox-anxiety wedge. n8n/Dify/Flowise/Sim execute tools in the app process. Aixle ships per-session container isolation, a live browser terminal (ttyd+tmux+xterm.js), and an embedded VS Code. Isolation is the default, not a roadmap item.
2. **"Runs that survive restarts and wait for humans."** Temporal-backed durable DAGs with parallel waves, retries, 23-hour human-approval signals, and CI gates (agent opens a PR, card waits until checks go green). No visual builder offers this; Windmill positions *against* Temporal and can't claim it.
3. **"Own your stack."** AGPLv3 against n8n's resented Sustainable Use License and Dify's multi-tenant clause. Self-hosted in two commands, BYO API keys, runtime-agnostic personas (swap Claude Code ↔ Codex ↔ Cursor ↔ Gemini in a dropdown), per-session token/cost metering. No telemetry, no gated SSO, multi-company roles in the free core.

**What NOT to claim:**

- Don't imply permissive licensing. AGPL is real open source — say so plainly and defend it — but never let copy blur into "MIT/Apache-style." The Sim comparison is license-honesty, not license-equivalence.
- Don't claim "fully self-hosted AI." Models are vendor APIs; "self-hosted" means your code, credentials, and orchestration stay home. Say this proactively (r/selfhosted will find it in minutes).
- Don't claim feature parity with n8n/Zapier on integrations or templates. Concede it plainly, in the landing page's existing voice.
- Don't claim zero-setup convenience vs Devin/Cursor/Copilot. The trade is explicit: control for convenience.
- Don't lead public positioning with Rails. It's a community wedge (r/rails, Ruby Weekly), not a headline.
- No enterprise/scale claims we can't evidence. No superlatives, no exclamation points — the brand voice is calm, concessive, engineer-to-engineer.

---

## 3. Audiences

**Primary — the self-hosting platform/tech-lead engineer.** Runs coding agents on real backlogs, won't ship code to a SaaS vendor, evaluates via README + `docker compose up` in under 10 minutes. Lives on: Hacker News, r/selfhosted, r/devops, Lobsters, self-host YouTube (Techno Tim, Christian Lempa, DB Tech), awesome-selfhosted. Buying trigger: sandbox anxiety + license resentment + agent cost opacity.

**Primary — the agentic-SDLC builder.** Tech lead wiring design→implement→review→QA pipelines with approval gates; already burned by chaining 15 nodes in n8n for a reasoning loop. Lives on: HN, r/LocalLLaMA, r/ClaudeAI, AI-agent YouTube (Matthew Berman, Cole Medin), X AI-tooling discourse, MCP registries.

**Secondary — the Ruby/Rails community.** Starved for a flagship AI project; disproportionate amplification and the likeliest first contributors. Lives on: r/rails, Ruby Weekly, Short Ruby, Remote Ruby/Ruby Rogues podcasts, Rails World. Message: "the majestic monolith can orchestrate AI agents."

**Secondary — agencies/consultancies** running agent work across clients (multi-company roles, viewer role, per-project cost tracking — the thing n8n's license forbids them from reselling). Reached through the same channels plus comparison/alternative pages; not a launch-week focus, but the wedge for later commercial motion.

---

## 4. Channel plan (ORB)

Focus beats coverage. Picks below; everything else is explicitly deprioritized.

**Owned:**
- **GitHub README** — the real landing page; 90% of launch traffic terminates here. Highest-priority owned asset.
- **Blog + docs site** — engineering posts (sandbox deep-dive, outbox, Go sidecar) live on the blog; the 18 in-app docs pages go public with llms.txt so AI assistants cite docs, not hallucinations.
- **Email** — the promised anti-newsletter only: a plain-text monthly numbers digest ("The Bill"). No sequences, matching the landing-page promise. Not a growth channel yet.

**Rented (in priority order):**
1. **Hacker News** — the anchor. The only zero-audience channel with a 1,000+ star ceiling. Three shots in 90 days: Go sidecar warm-up, Show HN, sandbox deep-dive.
2. **Reddit** — r/selfhosted (timed-install proof post), r/rails (community wedge), r/LocalLLaMA (BYO-keys variant). Norm-compliant, specifics-first, never marketing-voiced.
3. **X/Twitter** — clip distribution and newsjack replies (persona-swap clip when vendors change pricing), plus launch threads. Expect low reach at zero followers; treat as an asset archive that compounds.
4. **LinkedIn** — one founder-story post per launch moment. Low effort, occasionally outsized for the agency audience.
- *Deprioritized:* YouTube as an owned channel (creator seeding instead), Discord community (premature), paid anything.

**Borrowed (the only way to buy reach at $0):**
1. **Ruby newsletters/podcasts** — Ruby Weekly and Short Ruby reprint good technical work from unknowns; pitch at launch.
2. **Self-host + AI YouTubers** — 12-creator seeding kit with pre-provisioned instances; one mid-size video ≈ 500–2,000 stars.
3. **Temporal & Coder co-marketing** — Temporal wants Ruby-SDK AI case studies; Coder wants "agents provision their own workspaces." Pitch immediately, expect month 2–3 payoff; submit the Temporal Replay CFP.
4. **Directories/awesome-lists** — AlternativeTo, SaaSHub, awesome-selfhosted, MCP registries: mechanical, deterministic, feeds the LLM citation pool.

---

## 5. Phased launch plan

**Phase 0 — Pre-launch (now → repo public; runs alongside the OSS-prep history rewrite).**
Everything that must exist before any traffic arrives: README-as-landing-page with hero GIF and capability loops (#1); clean-machine-verified quickstart (test `make setup && make up` three times on fresh hardware — this is half the Show HN); llms.txt + public docs (#9); comparison hub, 3 pages not 9 (#18); 30 good-first-issues + CONTRIBUTING.md (#19); all launch-week copy pre-drafted (#2); the signature 60s video captured (#5); YouTuber dossier and partner pitches drafted (#7, #16). Send Temporal/Coder pitches now — their calendars run on quarters. Quiet teasers on X/LinkedIn: two build-in-public posts showing the terminal GIF, no ask.

**Phase 1 — Repo public + quiet week (Day 0–7).**
Flip the repo public *without* announcing. Ship the Go sidecar post (#4) as the warm-up shot — cheapest credible HN attempt, seeds the cost story. Start the directory wave (10 submissions), file awesome-list PRs, send YouTuber emails timed "repo just went public." Collect the first organic stars so the Show HN doesn't land on an empty repo.

**Phase 2 — Show HN launch week (Day 8–14).**
Tuesday 8–9am ET: "Show HN: Aixle Flow – open-source, self-hosted Kanban board that launches Claude Code/Codex agents in Docker sandboxes (AGPL)." Pre-written architecture first comment; founder clears the calendar for 12 hours of comment response. The scripted week follows: Day+1 r/selfhosted timed-install post (#3), Day+2 r/rails + Ruby Weekly pitch (#6), Day+3 outbox post to Lobsters (#8), Day+4 directory batch + 'repo is public' creator nudge, Day+5 X/LinkedIn recap thread with launch numbers.

**Phase 3 — Product Hunt (Day ~28).**
Deliberately 2–3 weeks after HN: reuse the signature video as the gallery hero, the Builder timelapse (#13) and persona-swap clip (#12) as gallery items, comparison pages as description links. PH is a backlink/credibility event, not the main spike — budget one day, not a week.

**Phase 4 — Sustained release train (Day 30+).**
Weekly Friday release with changelog + one GIF (GitHub Releases, X, Discussions). Monthly "The Bill" open-metrics post (#15). Ship the sandbox deep-dive (#10) as the next serious HN swing in week 5–6. Land partner posts (#16) as they mature. Quarterly: the four-CLI benchmark (#11) and cost calculator (#14) as evergreen citation assets. Reassess the always-on demo (#20) only after launch revenue-of-attention justifies the ops tax.

---

## 6. The idea backlog

| Rank | Idea | Format | Primary channel | Effort | Score |
|---|---|---|---|---|---|
| 1 | README-as-landing-page + hero GIF | README rewrite + GIF set | GitHub | M | 7.0 |
| 2 | Show HN launch-week operation | Show HN + 7-day calendar | HN | L | 6.8 |
| 3 | r/selfhosted timed-install proof | Uncut video + post | r/selfhosted | S | 6.7 |
| 4 | 100-line Go OTLP sidecar post | Blog post + source | HN/Lobsters | S | 6.4 |
| 5 | "Drag a Card. Ship a PR." video | 60s video + cuts | X/YT/PH/README | L | 6.4 |
| 6 | Rails flagship wedge | Blog + newsletter pitch | r/rails/Ruby Weekly | M | 6.1 |
| 7 | YouTuber seeding kit (12 creators) | Cold email + demo instance | YouTube | M | 6.0 |
| 8 | Outbox-without-relay-daemon post | Blog post + diagrams | Lobsters/HN | M | 5.9 |
| 9 | llms.txt + public docs retrofit | Docs restructure | AI assistants/SEO | S | 5.9 |
| 10 | Docker-sandbox deep-dive | Blog post (+GIF, cut the video) | HN/SEO | L | 5.8 |
| 11 | Four-CLI benchmark w/ token bills | Benchmark + charts | HN/r/LocalLLaMA | M | 5.8 |
| 12 | Persona-swap 15s clip | GIF + thread | X (newsjacking) | S | 5.7 |
| 13 | Aixle Builder timelapse | 90s timelapse | X/PH gallery | M | 5.7 |
| 14 | Agent cost calculator | Free tool page | Google/AI SEO | M | 5.6 |
| 15 | "The Bill" monthly open metrics | Thread + digest | X/LinkedIn/email | S | 5.6 |
| 16 | Temporal/Coder co-marketing | Guest posts + CFP | Partner blogs | M | 5.6 |
| 17 | 60-directory submission wave | Submission campaign | Directories | M | 5.5 |
| 18 | Honest Alternative comparison hub | 3 SEO pages (trimmed from 9) | Google/HN replies | M | 5.4 |
| 19 | GitHub trending engineering | 30 issues + release train | GitHub | M | 5.4 |
| 20 | Always-on public demo | Hosted instance | README/PH | L | 5.4 |

### Top-8 execution briefs

**#1 README-as-landing-page.** *Hook:* screenshots that move — board launches an agent before you read a word. *Assets → skills:* hero GIF + capability loops (Playwright MCP capture + `ffmpeg` speed-ramp; **video** skill), architecture SVG in brand tokens (**image**), comparison table + copy (**copywriting**, **competitors**), og:image card (**image**, Satori), badges row. *DoD:* hero GIF <10MB autoplays on GitHub; install block above the fold; all loops <3MB; og:image renders on X/Slack; a stranger can explain the product in 15 seconds from the README alone.

**#2 Show HN launch week.** *Hook:* "Show HN: Aixle Flow – open-source, self-hosted Kanban board that launches Claude Code/Codex agents in Docker sandboxes (AGPL)." *Assets → skills:* title shortlist + first comment + FAQ/objection kit (**launch**, **copywriting**, **competitors**, **marketing-psychology**), 7-day calendar with all Reddit/X/LinkedIn copy (**social**, **community-marketing**), quickstart verification log (manual, 3 clean-machine runs), contingency scripts (**public-relations**). *DoD:* every post for 7 days exists in a folder before Day 1; quickstart passes 3/3 on fresh hardware; first comment answers the n8n/Dify question in <150 words; founder calendar blocked for launch day.

**#3 r/selfhosted timed install.** *Hook:* "I timed it: clone to a sandboxed AI agent on my own hardware in 4:12. No telemetry, no gated SSO, AGPL." *Assets → skills:* uncut screen recording with timer (`screencapture`/ffmpeg avfoundation; **video**), RAM/disk footprint table (**dataviz**), checklist-answering post copy (**community-marketing**, **copywriting**), 60s social cut (**video**), r/LocalLLaMA variant (**social**). *DoD:* video is genuinely uncut; footprint numbers measured, not estimated; post pre-answers telemetry/open-core/"models aren't self-hosted" objections; posted Day+1 of launch week.

**#4 Go sidecar post.** *Hook:* "When the only consumer of your telemetry is your own app, OTLP is just another API call. 100 lines of Go." *Assets → skills:* annotated walkthrough of `docker/otlp-ingest/main.go` (**copywriting**, **copy-editing**), data-flow diagram (**image**), live-filling dashboard GIF (Playwright + ffmpeg; **video**). *DoD:* full source in the post; dashboard GIF real; submitted to HN + Lobsters + r/golang in quiet week; <2 days total effort.

**#5 Signature video.** *Hook:* "I dragged a card into 'Implementation.' A container booted, Claude Code opened the repo, and the first commit landed 40 seconds later." *Assets → skills:* seeded demo project + scripted capture (Playwright MCP), Remotion composition with brand captions (**video**, **motion-framer**), 16:9/9:16/GIF exports (ffmpeg), 6-tweet thread (**social**, **copywriting**). *DoD:* 60s master + 25s pinned cut + vertical; real-time markers so it reads as unstaged; embedded in README, Show HN comment, and PH gallery; end card = the two-command install.

**#6 Rails wedge.** *Hook:* "A full agent-orchestration platform in Rails: no REST layer, Typelizer-generated types, Temporal in Ruby." *Assets → skills:* blog post (**copywriting**), serializer→TS→React code walkthrough (**copy-editing**), pitch emails to Ruby Weekly/Short Ruby/podcasts (**public-relations**), r/rails-native summary (**social**). *DoD:* post live before pitching; three pitches sent launch week; framed as "the majestic monolith orchestrates agents," Rails never in the HN headline.

**#7 YouTuber seeding.** *Hook:* a live pre-seeded instance where they drag one card and an agent starts working — the demo pitches itself in 40 seconds. *Assets → skills:* 12-creator dossier (**prospecting**), 3 lane-specific email templates + 2-touch follow-ups (**cold-email**), demo-script one-pager (**copywriting**), b-roll pack from #5 (**video**), hosted throwaway instances (manual ops, capped keys). *DoD:* 12 personalized emails sent in quiet week; launch-day nudge queued; instances survive an unattended 20-minute session; expectation set internally at 0–1 videos in month one — any hit is upside.

**#8 Outbox post.** *Hook:* "We deleted the outbox relay process. A one-minute Temporal cron with FOR UPDATE SKIP LOCKED does crash recovery." *Assets → skills:* post drafted from the existing in-repo research doc (**copywriting**, **copy-editing**), sequence diagram + build-vs-buy table (**dataviz**, **image**). *DoD:* honest tradeoffs section survives a hostile senior-engineer read; posted to Lobsters first, HN second; internally links the sandbox deep-dive and README.

---

## 7. Production pipeline

**Ready today (no keys needed) — the plan deliberately depends only on these:**

| Skill(s) | Asset | Channel |
|---|---|---|
| copywriting, copy-editing, launch | README copy, Show HN kit, blog posts, FAQ | GitHub, HN, blog |
| competitors, competitor-profiling | Comparison table + 3 alternative pages | README, SEO, HN replies |
| video + Playwright MCP + ffmpeg + Remotion (Node) | Hero GIF, capability loops, signature video, install recording | README, X, YT, PH |
| image (screenshot path) + screencapture | Product shots, diagrams, og:image (Satori) | All |
| social, community-marketing | X threads, Reddit posts, launch calendar | X, Reddit, LinkedIn |
| cold-email, prospecting, public-relations, co-marketing | Creator + newsletter + partner outreach | Email, borrowed channels |
| ai-seo, schema, site-architecture | llms.txt, public docs, structured data | AI assistants, Google |
| directory-submissions | 60-target tracker + listing copy pack | Directories |
| dataviz | Footprint tables, cost charts, benchmark charts | Posts |

**Blocked / degraded until keys or installs land:**

- **All generative image/video** (stylized social art, AI b-roll): blocked on `GEMINI_API_KEY` + `REPLICATE_API_TOKEN`/`FAL_KEY`. *Mitigation:* the entire launch asset set is screen-capture-based by design — real product footage outperforms generated art for this audience anyway. Set keys before Product Hunt for gallery polish; do not block Phase 0–2 on them.
- **Batch image optimization:** `brew install imagemagick webp jpegoptim` — do this in Phase 0 (five minutes; the README GIF/WebP size budget depends on it).
- **Social scheduling:** no Buffer/Typefully — posts ship copy-paste from the pre-drafted calendar folder. Acceptable at this volume.
- **Canva/Figma MCP:** unauthenticated; not needed — brand templates are HTML/Satori.

Standing pipeline rule: every capture is scripted (Playwright + seeded demo data) so each release-train GIF and future re-record costs minutes, not hours.

---

## 8. Cadence & 4-week calendar (Day 0 = repo goes public)

*Assumes Phase 0 exit criteria met: README done, quickstart 3/3 verified, launch kit drafted, video cut, pitches written.*

**Week 1 — quiet seeding (Day 0–6)**
- Mon: repo public, README + llms.txt/docs live, first 10 directory submissions, awesome-list PRs.
- Tue: Go sidecar post → HN/Lobsters/r/golang.
- Wed: 12 YouTuber emails + Temporal/Coder pitches sent (if not already in Phase 0).
- Thu: 2 build-in-public X/LinkedIn posts (terminal GIF, no ask); directory batch 2.
- Fri: dry-run full launch day; re-verify quickstart on a clean machine; freeze main.

**Week 2 — launch (Day 7–13)**
- Tue 8–9am ET: **Show HN** + first comment; X launch thread; LinkedIn founder story; 12-hour comment watch.
- Wed: r/selfhosted timed-install post; creator "repo is public + HN thread" nudge.
- Thu: r/rails post + Ruby Weekly/Short Ruby/podcast pitches.
- Fri: outbox post → Lobsters; first release-train release (v0.x + changelog GIF); directory batch 3.

**Week 3 — follow-through (Day 14–20)**
- Mon: launch retro thread with real numbers (stars, installs, HN rank) — the transparency post is itself content.
- Tue–Wed: answer every open Reddit/HN thread; merge first external PRs loudly; persona-swap clip shipped as reply ammo.
- Thu: sandbox deep-dive final draft; PH assets assembled (gallery = signature video + Builder timelapse).
- Fri: release train #2; directory batch 4 (target: 40+ live).

**Week 4 — second spike (Day 21–27)**
- Tue: **Product Hunt** launch (one day, not a week).
- Wed: sandbox deep-dive → HN (second serious swing).
- Thu: "The Bill" #1 — June's real agent invoice from the dashboard.
- Fri: release train #3; month-1 metrics review against §9.

**Standing cadence after week 4:** Friday release + GIF weekly; one engineering post bi-weekly; "The Bill" monthly; benchmark + calculator quarterly; partner posts as they land.

---

## 9. Metrics & kill criteria

**North star: verified self-host installs** (proxied by GitHub unique cloners + quickstart-issue volume + demo-instance requests — no telemetry, by promise). Stars are the visible scoreboard; installs are the truth.

**Dashboard (weekly):** stars + star velocity; unique cloners/visitors (GitHub Insights); referral sources; HN/Lobsters points; Reddit upvotes/comment sentiment; directory listings live; creator/partner reply rate; external contributors; docs citations spotted in AI answers.

**Targets and decision rules:**

- **Show HN:** ≥150 pts = double down (sandbox deep-dive within 3 weeks, quote the thread everywhere). 30–150 = fine; proceed as planned. <30 by hour 3 = don't delete, don't repost for 6 weeks; diagnose title vs quickstart friction from comments; the r/selfhosted post becomes the primary week-2 push. One relaunch attempt allowed with a materially different angle (the sandbox post *is* that relaunch).
- **README conversion:** visitors→stars <2% after launch week = rework hero GIF/first screen before spending on any new channel. This is the first thing to fix, always.
- **r/selfhosted:** <100 upvotes = fix the post format, not the channel (it's too well-matched to abandon). Removed by mods = read the rules, wait 30 days, return norm-compliant.
- **Engineering posts:** any post <20 pts on both HN and Lobsters twice in a row = stop publishing on-schedule; publish only when a post has a genuinely contrarian core.
- **YouTuber seeding:** 0 replies after 12 emails + follow-ups by Day 45 = stop cold outreach; switch to warm-only (engage their content for 60 days first) and re-weight to partner channel.
- **Directories:** run to completion regardless (deterministic); stop only expanding past 60 targets — the marginal listing isn't worth an hour after that.
- **X/LinkedIn:** do not judge by follower growth for 6 months; judge by whether clips get quoted in other people's threads. Never let X consume more than 2 hrs/week.
- **Kill (indefinite hold):** always-on public demo until there's either revenue or a partner subsidizing hosting; paid anything; Discord community until 20+ organic "is there a community?" asks.

**When to double down, generally:** any single asset that outperforms its channel median by 3× gets a sequel within two weeks while the algorithmic and social memory is warm. The plan above is the default; a breakout result overrides the calendar.
