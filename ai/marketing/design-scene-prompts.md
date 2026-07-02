# Claude Design scene prompts — Aixle Flow ad series

Paste into the claude.ai/design project chat. Style anchor: the existing "Browser AI triggers" scene (dark Aixle tokens #0A0908/#E0582E, browser chrome, camera World moves, cursor + click rings, endcard with ring + wordmark). Render to MP4 via `ai/marketing/dc-render/`.

## Message hierarchy

Lead (unique vs n8n/Dify/Flowise/Sim):
1. **Sandbox isolation** — every agent in its own Docker container, live terminal.
2. **Durable orchestration** — Temporal: parallel waves, survives restarts, waits for humans (23h gates).
3. **Own your stack** — self-hosted, AGPL, BYO API keys.

Support:
4. Use your favourite agent — one persona, any runtime (Claude Code / Codex / Cursor / Gemini).
5. Human in the loop + CI gates.
6. Transparent costs — per-session token/$ metering.
7. Trackable artifacts + compliance — prompts & session logs stored (audit trail).
8. Triggers — demo format, not a message: board / Slack / webhook / cron.

Never claim: AGPL as "MIT-style"; "fully self-hosted AI" (models are vendor APIs); integration parity with n8n/Zapier.

## Scene prompts

### 1. Sandbox isolation — "Watch your agent work" (9:16, 20 s)
Same visual system as the Browser AI triggers scene. Story: a kanban card "Fix flaky auth spec" gets an agent assigned → camera dives into a live terminal panel: docker container boots (mono log lines type in), agent runs tests, commits. Side strip shows 3 more containers running in parallel, each isolated. Endcard: "Every agent in its own sandbox. Watch it live."

### 2. Durable runs — "Runs that survive" (9:16, 20 s)
Vertical DAG like the Slack-triage scene. Mid-run a "deploy restart" banner sweeps the screen (dark flicker 0.5 s) — the run RESUMES exactly where it was, checkmarks intact. Then a gate node "Wait for human approval · 23h" pulses calmly; cursor clicks Approve; run completes. Endcard: "Temporal-backed. Crash-safe. Waits for humans."

### 3. Favourite agent — "Same persona, any runtime" (1:1, 12 s)
Settings card with persona "senior-implementer". Runtime dropdown cycles: Claude Code → Codex → Gemini CLI → Cursor CLI; on each switch a mini terminal below re-runs the same task, output identical. Endcard: "Bring your own agent."

### 4. Transparent costs — "The Bill" (16:9, 15 s)
Usage dashboard: big $ counter ticks up as tiny agent-session rows stream in; bar chart grows per day; "By runtime" list fills. Freeze on total. Endcard: "Every token accounted. Export the invoice."

### 5. Compliance / audit trail (16:9, 15 s)
Session log viewer: a run's full transcript scrolls — prompt, tool calls, diffs, approvals — each row stamped with time + author chip. Cursor clicks "Export audit log", a signed JSON file drops. Endcard: "Prompts and sessions, recorded. Compliance-ready."

### 6. Triggers anthology — "Start from anywhere" (9:16, 20 s)
Four rapid chapters, 3.5 s each, same layout rhythm: (a) card dragged into a column → run starts; (b) Slack message lands → run starts; (c) curl POST to webhook URL in a terminal → run starts; (d) cron clock flips 09:00 → run starts. Shared progress ribbon at the bottom collects 4 green checks. Endcard: "Board. Slack. Webhook. Schedule."

### 7. Human in the loop — "You hold the merge button" (16:9, 12 s)
PR card: agent opens PR, CI checks flip red→green one by one, card waits — pulsing calm amber "Waiting for you"; cursor clicks Approve; merge animation. Endcard: "Agents propose. You approve."

### 8. Self-hosted — "Your infra, your rules" (16:9, 15 s)
Terminal-only scene: `git clone && make setup && make up` types itself, compose services light up as rows (web, worker, temporal, db), browser opens localhost:4000 with the board. Endcard: "Two commands. Your hardware. AGPL."
