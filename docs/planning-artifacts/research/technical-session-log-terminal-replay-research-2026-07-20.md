---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: []
workflowType: 'research'
lastStep: 4
research_type: 'technical'
research_topic: 'Replaying a finished session log in a browser terminal with colors/markup preserved'
research_goals: 'Choose the cheapest capture + render path so a finished TerminalSession can be reopened in-browser as a colored, scrollable terminal that shows how the session went'
user_name: 'Artem_petrov'
date: '2026-07-20'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-20
**Author:** Artem_petrov
**Research Type:** technical

---

## Research Overview

**Question.** A `TerminalSession` is a spun-up container running a coding agent inside `tmux`,
served live over the web by `ttyd` in an `<iframe>`. When the session ends we snapshot the
terminal to a file. We want to reopen a *finished* session in the browser as if it were a
terminal (JS), preserving color/markup, so a user can see "how the session went".

**Chosen direction (per stakeholder decision).** The **cheap variant**: a *static* colored
dump (full scrollback with ANSI attributes), rendered read-only in the browser — **not** a
time-based asciinema-style replay. No per-frame timing is captured or played back.

**Method.** Mapped the existing capture/storage/render pipeline in this repo, then verified the
two enabling primitives against current sources: `tmux capture-pane -e` (ANSI preservation) and
`xterm.js` static/read-only rendering. Both are confirmed viable; `@xterm/xterm` is already a
dependency.

---

## Current State (as-is)

| Concern | Today | File |
|---|---|---|
| Session model | `TerminalSession` (tmux `agent` session, ttyd on 7681) | `app/models/terminal_session.rb` |
| Capture at finish | `tmux capture-pane -t agent -p -S -` → `/tmp/terminal_output.log` | `app/services/container_strategies/agent_session_strategy.rb:129` |
| Storage | one `SessionLog` blob via Shrine, `content_type: "text/plain"` | `agent_session_strategy.rb:141`, `app/uploaders/session_log_uploader.rb` |
| Timing | none — single end-of-session snapshot | — |
| Finished-session UI | stats/cost card only; log is **not** rendered for users | `app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx:213` |
| Live terminal | `ttyd` inside an `<iframe>` (not xterm.js) | `SessionShowContent.tsx:380` |
| Libs present | `@xterm/xterm ^6.0.0`, `@xterm/addon-fit`, `@xterm/addon-web-links` — **installed, unused** | `package.json` |
| Libs absent | `asciinema-player`, `ansi-to-html`, any ANSI parser / gem | — |

**The blocking defect for our goal:** `capture-pane` is invoked **without `-e`**, so ANSI SGR
(color/bold/underline) sequences are stripped before the file is ever written. The stored log is
plain, colorless text. **The goal is unreachable without changing the capture side.** That is the
one mandatory change.

---

## Recommended Approach (cheap, static, colored)

Two sub-options exist within the "cheap" bucket. They differ only in the capture command; the
storage and frontend work is identical.

### Capture — two options

**Option A1 — minimal: add `-e` to the end-of-session snapshot.**
```sh
tmux capture-pane -t agent -e -p -S - > /tmp/terminal_output.log
```
`-e` preserves escape sequences for color and attributes; `-S -` grabs the full retained
scrollback. One-line diff at `agent_session_strategy.rb:132`. Cheapest possible change.
*Limitation:* it is still a **snapshot of the final pane state**. Anything a full-screen
(alternate-screen) TUI drew and then cleared is gone; only what remains in scrollback survives.

**Option A2 — recommended: continuous raw capture via `tmux pipe-pane` (still cheap, still
static).** At agent launch, start piping the raw PTY byte stream to a file:
```sh
tmux pipe-pane -t agent -o 'cat >> /tmp/session.raw'
```
This appends the **raw output stream including all escape sequences** for the whole session, not
a final snapshot. At finish we already have file-collection infra (`read_file_from_container` +
`SessionLog.create!`) — just collect `/tmp/session.raw` instead of (or alongside) the capture.
No timing is recorded, so it stays in the "static" bucket, but fidelity is complete: feeding the
full byte stream into xterm.js reconstructs exactly what the real terminal rendered, including
color and intermediate redraws. Cost over A1: one extra `tmux pipe-pane` command at launch
(`launch_agent_in_tmux`, ~`agent_session_strategy.rb:114`) and collecting one file at finish.

> **Recommendation: A2.** It is only marginally more work than A1, avoids the "final-frame-only"
> failure mode of a snapshot, and produces a stream xterm.js consumes natively. Keep A1 as the
> fallback if `pipe-pane` proves awkward under the k8s runtime.

### Storage — near-zero change

- Keep the `SessionLog` blob model. Store the colored bytes as-is.
- Set `content_type: "text/plain; charset=utf-8"` (bytes contain ESC `\x1b` — do **not** try to
  sanitize or HTML-escape them at rest; xterm.js is the parser).
- Optionally name it distinctly (e.g. `terminal_output.ansi` / `session.raw`) so the renderer
  can tell colored logs from legacy colorless ones and pick a code path.
- Legacy sessions (pre-change) stay colorless — that is acceptable; the renderer degrades to
  plain text for them.

### Frontend — xterm.js, read-only, lazy

`@xterm/xterm` is already installed and unused — this is the intended consumer.

- New React component (e.g. `SessionTerminalReplay`) rendered from `SessionShowContent` when the
  session `isTerminal` (finished/failed), replacing/augmenting the summary card.
- Fetch the `SessionLog` bytes (new authenticated endpoint returning the raw file for the owning
  user — mirror `admin/session_logs_controller.rb#send_log_file` but scoped to the session owner,
  not admin-only).
- Instantiate a read-only terminal and write the whole buffer once:
  ```ts
  const term = new Terminal({
    disableStdin: true,      // read-only, no input
    convertEol: true,        // capture-pane lines are \n-terminated, not \r\n
    scrollback: 100000,      // whole session must be scrollable
    fontFamily: '<match app terminal font>',
    theme: { /* map to --app-* tokens, light/dark */ },
  });
  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(el);
  fit.fit();
  term.write(bytes);         // async write buffer; fine for large logs
  ```
- Lifecycle: `term.dispose()` on unmount (dispose is a trapdoor — the instance is unusable after,
  so create fresh per mount). Lazy-import xterm so it is not in the main bundle.
- `convertEol: true` matters for **A1** (snapshot lines are `\n`-only → without it xterm
  stair-steps). For **A2** the raw stream already contains `\r\n`, so `convertEol` is harmless but
  unnecessary — safe to leave on.
- Sizing: `FitAddon` fits columns to the container; wrap in an `overflow-y:auto` panel for
  scrollback. Re-fit on resize.

---

## Gotchas & Risks (validate during a spike)

1. **Alternate-screen TUIs (the biggest risk).** If an agent CLI runs full-screen (enters the
   alternate screen buffer), A1's snapshot captures only the final frame; scrollback of the
   "conversation" is empty. A2 captures the full byte stream but xterm still ends on the
   alt-screen's final state after replay. **Action:** confirm whether `claude_code` / `cursor_cli`
   / `codex` / `gemini_cli` use the alternate screen in this setup. Claude Code generally renders
   in the normal buffer (scrolls), which favors A2 heavily. Test one session per agent type.
2. **Scrollback truncation.** `capture-pane -S -` only returns what tmux still holds
   (`history-limit`). Long sessions may lose the head. A2 (pipe-pane from launch) is immune —
   another reason to prefer it. If staying on A1, raise tmux `history-limit` for the agent session.
3. **File size / performance.** Logs can be large (uploader cap is 1 GB). xterm.js handles large
   logs, but writing hundreds of MB blocks. Cap render size (e.g. tail last N MB with a "log
   truncated" banner) and/or stream `term.write` in chunks. Never silently truncate without a UI note.
4. **Escape-sequence safety.** The bytes contain control sequences by design. Do **not** render
   them into the DOM as HTML — only `term.write()` into xterm, which is a hardened VT parser. Avoid
   `ansi-to-html`-style approaches that build HTML strings (injection surface, weaker fidelity).
5. **Encoding.** Ensure UTF-8 end to end (agents emit box-drawing/emoji). Store and serve as
   `charset=utf-8`; xterm decodes UTF-8 natively.
6. **`-J` line-join.** Do **not** add `-J` to capture-pane — it joins wrapped lines and mangles
   layout. Plain `-e -p -S -` only.

---

## Alternatives Considered (and why not now)

- **B — asciinema recording (time-based replay).** Record raw PTY + timing from launch
  (`asciinema rec` in-container, or `tmux pipe-pane` with timestamps → asciicast v2), render with
  `asciinema-player`. Gives true play/pause/seek "watch it happen". Rejected for now: requires
  reworking the container launch/lifecycle and a new player dependency — the expensive path. **A2
  is a forward-compatible stepping stone:** the same `pipe-pane` capture, plus per-chunk
  timestamps, upgrades to asciicast later without discarding work.
- **`ansi-to-html` → static HTML.** Simpler-sounding, but lower fidelity, an HTML-injection
  surface, and no terminal semantics (cursor moves, clears). xterm.js is already installed and
  strictly better. Rejected.
- **Reuse ttyd iframe for finished sessions.** ttyd needs a live PTY; the container is gone after
  finish. Not applicable to replay.

---

## Implementation Plan (thin slice)

1. **Spike (½ day):** for each agent type, run a session, `tmux pipe-pane` to a file, download it,
   `cat` into a local xterm.js page. Confirm colors + scrollback look right and alt-screen is not
   eating the conversation. Decide A2 vs A1 from the result.
2. **Backend capture:** start `pipe-pane` in `launch_agent_in_tmux`; collect `/tmp/session.raw`
   at finish (reuse `read_file_from_container` + `SessionLog.create!`, `content_type:
   "text/plain; charset=utf-8"`). Tests: strategy test asserting a colored `SessionLog` is created.
3. **Serve endpoint:** owner-scoped controller action returning the raw log bytes for a finished
   session (auth = session owner; not admin-only).
4. **Frontend:** `SessionTerminalReplay` (lazy xterm.js, read-only, fit, dispose-on-unmount,
   theme mapped to `--app-*` tokens). Wire into `SessionShowContent` terminal-state branch.
   Vitest: component fetches log and calls `term.write` with the bytes (mock the terminal per
   `docs/testing.md` seams).
5. **Degrade:** legacy colorless logs still render (plain text) — no migration needed.
6. **Guardrails:** size cap + "truncated" banner; `docker compose exec -T web make check_all`
   green before PR.

---

## Sources

- [tmux capture-pane — Complete Guide (tmux.info)](https://tmux.info/docs/commands/capture-pane) — `-e` preserves escape sequences; `-S -` = full scrollback.
- [Preserve ANSI colors in tmux capture (brendanlong commit)](https://github.com/brendanlong/claude-code-plays-text-games/commit/efd30b474ec07310ad5af7e22649d5d3f01cf7f4) — real-world `capture-pane -e` for color capture.
- [tmux issue #3401 — interpret ANSI in show-buffer](https://github.com/tmux/tmux/issues/3401) — confirms `-e` behavior + limitations.
- [xterm.js repo](https://github.com/xtermjs/xterm.js/) and [dispose() trapdoor discussion #3939](https://github.com/xtermjs/xterm.js/issues/3939) — `write()`/`dispose()` semantics, large-log handling, read-only usage.
- [Zuul: xterm.js for log streaming](https://opendev.org/zuul/zuul/commit/bb352a3559d75e816d1f9fd9a645fb41dee8ce10) — precedent for xterm.js as a static/streamed log viewer.
- [@xterm/addon-fit (npm)](https://www.npmjs.com/package/@xterm/addon-fit) — FitAddon sizing.
- Repo evidence: `app/services/container_strategies/agent_session_strategy.rb:129`, `app/models/terminal_session.rb`, `app/uploaders/session_log_uploader.rb`, `app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx`, `package.json`.
