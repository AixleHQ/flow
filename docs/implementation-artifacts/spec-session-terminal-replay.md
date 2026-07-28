---
title: 'Session terminal replay (static colored log in xterm.js)'
type: 'feature'
created: '2026-07-20'
status: 'done'
baseline_commit: 'e1f984805a0c52a2838efcfad314bef3dbef174b'
review_loop_iteration: 0
context:
  - '{project-root}/docs/planning-artifacts/research/technical-session-log-terminal-replay-research-2026-07-20.md'
  - '{project-root}/docs/testing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A finished `TerminalSession` shows only a stats card — the user cannot see how the agent
session actually went. The one captured log is plain, colorless text (`capture-pane` without `-e`),
so colors/markup are already lost at capture time.

**Approach:** Replace the current colorless capture in place: continuously capture the raw PTY byte
stream (with ANSI) via `tmux pipe-pane` from agent launch into the single existing
`terminal_output.log` `SessionLog` (no second log). Expose an owner-scoped endpoint that serves those
bytes and render them read-only in a browser terminal (xterm.js — already a dependency, currently
unused) inside the finished-session view. Static dump with full color + scrollback; no playback.

## Boundaries & Constraints

**Always:** Produce exactly ONE `SessionLog` named `terminal_output.log` — change the existing
capture in place so it holds the raw ANSI stream; do not add a second log. Keep the existing
quota-scan consumer of that log working (strip ANSI before matching, or confirm patterns still hit).
Reuse the existing collect/`SessionLog` pipeline and the existing session-owner auth scope for the
new endpoint. Serve bytes as `text/plain; charset=utf-8`. Feed raw bytes only into `term.write()` —
never render escape sequences into the DOM as HTML. Terminal is read-only (`disableStdin`).
Lazy-import xterm so it stays out of the main bundle. Map terminal colors to the app light/dark
theme via `--app-*` tokens.

**Ask First:** Changing the capture from `pipe-pane` (raw stream) to any other mechanism; adding a
time-based/asciinema player; touching the live ttyd iframe path; raising the 1 GB uploader cap.

**Never:** Do not create a second/parallel terminal log. Do not modify Typelizer-generated
`types/generated/*`. No new npm/gem deps. No per-chunk timing capture.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Finished session, log present | GET terminal_log, owner | 200, `terminal_output.log` bytes; xterm renders scrollback (colored if captured after change) | N/A |
| Legacy finished session (colorless log) | pre-change plain log | 200, renders as plain text (no colors); viewer still shown | N/A |
| Finished session, no log at all | log absent | URL present (state-gated); fetch returns 404 → frontend shows "No terminal output" empty state | Empty state, not an error |
| Non-owner requests log | scoped find misses | 404 (scope = authorization, mirror existing) | N/A |
| Session still running | state not in finished/failed | `terminal_log_url` is nil → replay not rendered (live ttyd iframe path unchanged) | N/A |
| Very large log (> 2 MB) | large file | Render last 2 MB with a "log truncated" banner; never silently drop | N/A |
| Empty/whitespace file | blank content | No SessionLog created at collect; endpoint 404 | N/A |

</frozen-after-approval>

## Code Map

- `app/services/container_strategies/agent_session_strategy.rb` -- `launch_agent_in_tmux` (:114) start pipe-pane; `before_cleanup` (:74, collect calls :81-83) add raw collect; `collect_terminal_output` (:129) is the pattern to copy.
- `app/services/container_strategies/agent_base_strategy.rb` -- `send_tmux_command`/`send_tmux_sequence` (:119/:126) show `runtime.exec(container, ["sh","-c",...])` idiom for tmux ops.
- `app/services/container_strategies/base_strategy.rb` -- `read_file_from_container` (:181).
- `app/models/session_log.rb` / `app/uploaders/session_log_uploader.rb` -- Shrine attachment; `log.file.read` returns bytes.
- `app/controllers/api/v1/terminal_sessions_controller.rb` -- has member `finish`; add `terminal_log` beside it, reuse its session resolution/auth.
- `config/routes.rb` -- api/v1 `terminal_sessions` member block (~:59-63); add `get :terminal_log`.
- `app/resources/terminal_session_resource.rb` -- expose `terminal_log_url` following `websocket_url` (:29) pattern; nil unless a `terminal_output.log` SessionLog exists.
- `app/temporal/activities/workflow/complete_step_activity.rb` -- quota scan reads `terminal_output.log`; must tolerate ANSI now present in it.
- `app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx` -- inject `<SessionTerminalReplay/>` inside `renderCompletionCard` Stack (child of :216, after prompt block ~:327).
- `app/frontend/shared/lib/apiFetch.ts` / `shared/routes.ts` -- fetch idiom + generated route helper.
- `app/frontend/shared/ui/ColorSchemeToggle.tsx` -- `useComputedColorScheme` theme-read idiom.
- `app/frontend/test/renderPage.tsx`, `SessionShowContent.test.tsx` -- render + `vi.spyOn(globalThis,'fetch')` seam.

## Tasks & Acceptance

**Execution:**
- [x] `docker/base/entrypoint.sh` -- capture belongs here, not app-side: the `agent` pane already has ONE tmux pipe (`cat >> /proc/1/fd/1`); change it to `tee -a /tmp/terminal_output.log > /proc/1/fd/1` so the same pipe both streams to the container log and captures the raw ANSI stream from container start. (`pipe-pane` allows only one pipe per pane — a second `-o` pipe would be a silent no-op.)
- [x] `app/services/container_strategies/agent_session_strategy.rb` -- in `collect_terminal_output`, drop the `tmux capture-pane` exec (the file is populated by the entrypoint pipe) and change the stored `content_type` to `"text/plain; charset=utf-8"`. Keep name `terminal_output.log` and the blank-guard/rescue. Still ONE SessionLog.
- [x] `app/temporal/activities/workflow/complete_step_activity.rb` -- the quota scan reads `terminal_output.log`, which now contains the raw stream; strip the full escape family (CSI + OSC + charset/other) and collapse `\r` before matching, so redraw/OSC noise does not break quota detection.
- [x] `config/routes.rb` -- add `get :terminal_log, on: :member` to the api/v1 `terminal_sessions` resource.
- [x] `app/controllers/api/v1/terminal_sessions_controller.rb` -- add `terminal_log` action: owner-scoped `find_session`; 404 unless state is finished/failed; find the `terminal_output.log` SessionLog (404 if absent); serve only the last `MAX_LOG_BYTES` tail via a seek-based `read_log_tail` (fallback read+byteslice), set `X-Log-Truncated` header when the file is larger, `send_data ... text/plain; charset=utf-8`.
- [x] `app/resources/terminal_session_resource.rb` -- add `terminal_log_url` attribute (`typelize :string?`) returning the `terminal_log` path when a `terminal_output.log` SessionLog exists, else nil; regenerate `types/generated` via the Typelizer command (do not hand-edit).
- [x] `app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.tsx` -- new read-only xterm component: props `{ logUrl: string }`; on mount `apiFetch(logUrl)`→`.text()`; lazy `import('@xterm/xterm')`, `import('@xterm/addon-fit')`, `import('@xterm/xterm/css/xterm.css')`; `new Terminal({ disableStdin: true, scrollback: 100000, fontFamily: '--app-font-mono', theme: mapped from useComputedColorScheme + --app-* tokens })`; `loadAddon(FitAddon)`, `open`, `fit`, cap at last 2 MB with banner, `write(bytes)`; `dispose()` on unmount; loading + error states.
- [x] `app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx` -- render `<SessionTerminalReplay logUrl={s.terminalLogUrl}/>` inside `renderCompletionCard` when `s.terminalLogUrl` is present.
- [x] `app/services/container_strategies/agent_session_strategy_test.rb` (or existing strategy test) -- assert exactly one `terminal_output.log` `SessionLog` is created on cleanup (content_type `text/plain; charset=utf-8`) when the file is non-empty, and none when blank; assert pipe-pane is started at launch.
- [x] `app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.test.tsx` -- `vi.mock('@xterm/xterm')` + `vi.mock('@xterm/addon-fit')`; `vi.spyOn(globalThis,'fetch')` returns ANSI bytes; assert the stubbed `terminal.write` receives the fetched bytes; assert truncation banner appears for an over-cap body.

**Acceptance Criteria:**
- Given a session captured after this change, when the user opens its finished page, then a read-only colored terminal shows the full session scrollback and the live ttyd path is untouched.
- Given a legacy finished session (colorless `terminal_output.log`), when the page loads, then the replay renders it as plain text (no colors).
- Given a finished session with no captured log, when the page loads, then the replay fetches `terminal_log`, receives 404, and shows the "No terminal output" empty state (no error).
- Given a running (non-terminal) session, when the page loads, then `terminal_log_url` is nil and no replay renders.
- Given a user who does not own the session, when they request `terminal_log`, then the response is 404.
- Given a session log now carrying ANSI, when quota scanning runs, then quota errors are still detected (ANSI does not break matching).

## Verification

**Commands:**
- `docker compose exec -T web make check_all` -- expected: green (rails test, rubocop, brakeman, eslint, tsc, vitest).
- `docker compose exec -T web ./node_modules/.bin/vitest run app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.test.tsx` -- expected: pass.

**Manual checks:**
- Run a real agent session end-to-end; confirm the finished view renders colors/scrollback matching the live terminal, and confirm no alt-screen loss for each agent type (claude_code, cursor_cli, codex, gemini_cli).

## Spec Change Log

- **Finding:** gating `terminal_log_url` on the existence of a `terminal_output.log`
  SessionLog (`session_logs.exists?`) added a per-session query that broke the N+1
  query-budget test `AixleBuilderControllerTest#test_show_does_not_issue_N+1_queries…`
  (21 > 15) when a list of sessions is serialized.
  **Amendment (approved by human):** gate `terminal_log_url` on terminal `state`
  (`finished`/`failed`) — a column read, O(1), no per-session query. Matrix + AC updated:
  a finished session without a log now yields a 404 the frontend renders as the "No terminal
  output" empty state, instead of hiding the replay with no request.
  **Avoids:** reintroducing N+1 on session-list pages.
  **KEEP:** single `terminal_output.log`, owner-scoped `send_data` streaming, and the read-only
  xterm write path are unaffected — do not re-derive those.

- **Review round 1 (2026-07-20) — patches applied (no spec loopback):**
  - **Capture was dead on arrival (headline):** the `agent` pane already has one tmux pipe from
    `docker/base/entrypoint.sh` (`cat >> /proc/1/fd/1`); tmux allows one pipe per pane, so the
    app-side `pipe-pane -o` was a silent no-op. Fixed by folding capture into the entrypoint pipe
    via `tee -a /tmp/terminal_output.log > /proc/1/fd/1` and deleting `start_terminal_capture`. This
    also removes the pane-readiness race and the pre-attach output-loss window.
  - **Missing Pundit policy method** `terminal_log?` → the endpoint 500'd (`NoMethodError`), which the
    frontend showed as "Could not load…". Added `terminal_log? = true`; added controller tests
    (200 / 404-no-log / 404-non-terminal) that exercise the real Pundit path.
  - **Unbounded serve + client cap in chars:** server now serves only the last `MAX_LOG_BYTES` tail
    (seek-based, fallback byteslice) and sets `X-Log-Truncated`; client resyncs to the first newline
    and shows the banner from the header (no whole-file download, no mid-codepoint garble).
  - **Endpoint not state-gated:** added a finished/failed guard in the action (not only the resource URL).
  - **Quota strip too narrow:** broadened `strip_ansi` to CSI + OSC + charset/other escapes and CR-collapse.
  - **Theme toggle re-fetched the log:** `colorScheme` removed from the load effect; a separate effect
    recolors in place via `term.options.theme`.
  - **KEEP:** single `terminal_output.log`; owner-scoped serve; read-only lazy xterm write path.

## Design Notes

- **A2, not A1:** raw `pipe-pane` stream (not a `capture-pane -e` snapshot) — full fidelity, immune to
  scrollback truncation, and a forward-compatible stepping stone to an asciinema time-based player later.
- **One log:** pipe-pane writes into `/tmp/terminal_output.log`, the same file the collector already
  stores — the old plain capture is replaced in place, so there is a single `SessionLog`, and the
  quota-scan consumer keeps reading the same file (now ANSI-stripped before matching).
- **convertEol:** leave default/false — the raw PTY stream already contains `\r\n`. (A snapshot would have needed `convertEol: true`.)
- **Alt-screen risk:** if an agent runs full-screen (alternate buffer), the rendered end state may collapse; the manual check per agent type is the gate. Claude Code renders in the normal buffer, favoring this approach.
- **Security:** bytes are auth-fetched, served `text/plain`, and only ever passed to `term.write()`; escape sequences never reach the DOM as HTML.

## Suggested Review Order

**Capture (where the log comes from)**

- Entry point — one tmux pipe now tees to both the container log and the capture file.
  [`entrypoint.sh:123`](../../docker/base/entrypoint.sh#L123)
- Collector just reads that file into a single `terminal_output.log` SessionLog.
  [`agent_session_strategy.rb:129`](../../app/services/container_strategies/agent_session_strategy.rb#L129)

**Serve (owner-scoped, bounded, state-gated)**

- Endpoint: state guard, 404-if-absent, tail-capped `send_data` + truncation header.
  [`terminal_sessions_controller.rb:65`](../../app/controllers/api/v1/terminal_sessions_controller.rb#L65)
- Seek-based tail read so a huge log is never fully buffered.
  [`terminal_sessions_controller.rb:81`](../../app/controllers/api/v1/terminal_sessions_controller.rb#L81)
- Pundit gate (its absence 500'd the endpoint).
  [`terminal_sessions_policy.rb:7`](../../app/policies/api/v1/terminal_sessions_policy.rb#L7)
- URL exposed only for finished/failed — a column read, no N+1.
  [`terminal_session_resource.rb:41`](../../app/resources/terminal_session_resource.rb#L41)
- Route.
  [`routes.rb:62`](../../config/routes.rb#L62)

**Quota-scan compatibility**

- Broadened ANSI stripping so the now-raw log still yields quota matches.
  [`complete_step_activity.rb:78`](../../app/temporal/activities/workflow/complete_step_activity.rb#L78)

**Frontend replay**

- Read-only xterm: fetch → truncation resync → lazy xterm write; theme recolors in place.
  [`SessionTerminalReplay.tsx:46`](../../app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.tsx#L46)
- Recolor-in-place effect (no refetch on theme toggle).
  [`SessionTerminalReplay.tsx:117`](../../app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.tsx#L117)
- Injected into the finished-session card, gated on `terminalLogUrl`.
  [`SessionShowContent.tsx:330`](../../app/frontend/shared/components/SessionShowContent/SessionShowContent.tsx#L330)

**Sessions list — open affordance (secondary goal)**

- Company sessions rows now clickable to the show page (mirrors project list).
  [`Index.tsx:287`](../../app/frontend/pages/Company/Sessions/Index.tsx#L287)

**Tests (peripheral)**

- Endpoint: 200 / 404-no-log / 404-non-terminal through the real Pundit path.
  [`terminal_sessions_controller_test.rb:94`](../../test/controllers/api/v1/terminal_sessions_controller_test.rb#L94)
- Strategy: single `terminal_output.log`, no capture-pane.
  [`agent_session_strategy_test.rb:361`](../../test/services/container_strategies/agent_session_strategy_test.rb#L361)
- Quota detection survives ANSI-wrapped log.
  [`complete_step_activity_test.rb:93`](../../test/temporal/activities/complete_step_activity_test.rb#L93)
- Component: writes bytes, empty on 404, truncation resync.
  [`SessionTerminalReplay.test.tsx:38`](../../app/frontend/shared/components/SessionShowContent/SessionTerminalReplay.test.tsx#L38)
