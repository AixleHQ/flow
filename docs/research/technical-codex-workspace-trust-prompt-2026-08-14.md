# Codex workspace-trust prompt wedging non-interactive workflow sessions

**Date:** 2026-08-14 · **Board task:** 605 · **Incident:** project 1, task 583, run 3190,
step run 3476, terminal session 3834 · **Codex CLI verified against:** 0.147.0 (`@openai/codex`)

## The wedge

A board-triggered Codex workflow step started and then stopped, at `ready`, with zero tokens,
no error message, and ~52 minutes of idle time. `get_session_log(3834)` showed the CLI had done
no task work at all:

```text
root@terminal-85e5e5e154c24953c45f4c3cfa323594:/workspace# codex --yolo "$AGENT_PROMPT"
> You are in /workspace

  Do you trust the contents of this directory? Working with untrusted contents
  comes with higher risk of prompt injection. Trusting the directory allows
  project-local config, hooks, and exec policies to load.

› 1. Yes, continue
  2. No, quit

  Press enter to continue
```

The session is `non_interactive`: nobody is attached to press Enter. The step stays `running`,
the session stays `ready`, and the run holds its pod until a human intervenes.

## Reproduction harness

Everything below was measured against the real CLI binary, not read off documentation. The
harness runs Codex inside `tmux` — the same shape production uses (`docker/base/entrypoint.sh`
starts `tmux new -d -s agent bash`, and `AgentBaseStrategy#send_tmux_sequence` types the launch
command into that pane). A plain `script -qec` pty is **not** sufficient: the onboarding TUI
never renders under it, so the prompt looks absent when it is merely invisible.

Each run gets a fresh `CODEX_HOME` and a fresh working directory, so nothing can pass by
inheriting an already-trusted local cache.

```bash
#!/bin/bash
# probe.sh <label> <config.toml|-> <cmd template; __WS__ = the workspace path>
CODEX=${CODEX:-codex}
LABEL="$1"; CFG="$2"; TPL="$3"
BASE="$PWD/$LABEL"; rm -rf "$BASE"; mkdir -p "$BASE/home" "$BASE/ws"
# Any credential that reads as "logged in" — the trust screen comes after auth in
# onboarding, so an unauthenticated CODEX_HOME stops at the login screen instead.
printf '{"OPENAI_API_KEY":"sk-test-not-real"}' > "$BASE/home/auth.json"
[ "$CFG" != "-" ] && sed "s|__WS__|$BASE/ws|g" "$CFG" > "$BASE/home/config.toml"
printf 'export CODEX_HOME=%s\ncd %s\n%s\n' "$BASE/home" "$BASE/ws" \
  "$(printf '%s' "$TPL" | sed "s|__WS__|$BASE/ws|g; s|\$CODEX|$CODEX|g")" > "$BASE/run.sh"
tmux kill-session -t "p_$LABEL" 2>/dev/null
tmux -u new -d -s "p_$LABEL" -x 130 -y 40 -c "$BASE/ws" bash
sleep 1; tmux send-keys -t "p_$LABEL" "bash $BASE/run.sh" Enter; sleep 14
tmux capture-pane -t "p_$LABEL" -p > "$BASE/pane.txt"
tmux kill-session -t "p_$LABEL" 2>/dev/null
grep -qa "Do you trust the contents" "$BASE/pane.txt" \
  && echo "[$LABEL] TRUST_PROMPT" || echo "[$LABEL] no-trust-prompt"
```

## Findings

| # | `~/.codex/config.toml` | Launch | Result |
|---|---|---|---|
| 1 | absent | `codex --yolo` | **trust prompt** |
| 2 | as `CodexAdapter#generate_config_toml` writes it | `codex --yolo` | clean start |
| 3 | MCP block only (trust entry lost) | `codex --yolo` | **trust prompt** |
| 4 | valid config + a duplicated `[mcp_servers.x]` table | `codex --yolo` | exits: `Error loading config.toml: … duplicate key` |
| 5 | absent | `codex --yolo -c projects."<ws>".trust_level="trusted"` | clean start |
| 6 | absent | `codex --yolo -c projects.<ws>.trust_level=trusted` (unquoted) | clean start |
| 7 | MCP block only | `codex --yolo -c projects.<ws>.trust_level=trusted` | clean start |
| 8 | absent | `codex exec --dangerously-bypass-approvals-and-sandbox` | clean start |
| 9 | absent | the full `tmux send-keys -t agent '<cmd>' Enter` path with the row-6 flag | clean start |

### Answers to the questions on the task

**Why was `/workspace` not already trusted?** Not because the adapter forgot to trust it — row 2
proves the generated `config.toml` suppresses the dialog. The trust entry was *lost after* being
written. `~/.codex/config.toml` is produced once by the credential step
(`AgentCredential#write_to_container` → `CodexAdapter#config_files`) and then **read-modify-written**
by `SessionContextService#write_mcp_file` under the `:append_toml` strategy. That read went through
`read_file`, which answers `nil` both for "the file is not there" and for "the read failed" — so a
single container/exec hiccup made the append write the MCP block *on its own*, discarding the
`[projects."/workspace"]` entry and the `[notice]` acknowledgements. The result is row 3: a file
that parses cleanly and trusts nothing. Note the asymmetry with row 4 — corruption that breaks TOML
*fails loudly and exits*; corruption that merely drops keys is what wedges a session.

**Does trust persist between sessions/containers/images?** No, and it must not be relied on.
Trust lives in `$CODEX_HOME/config.toml` (`$HOME/.codex`, `HOME=/home/codex` per
`docker/codex/Dockerfile`). Every session gets a fresh container from the image, and the image
ships no `config.toml` — so every session starts untrusted and is trusted only by what the
platform writes into it. There is no host-level or image-level cache to inherit.

**What is the supported non-interactive path?** Two, and we use both:
- `-c projects.<path>.trust_level=trusted` — a `--config` override, applied from argv, so no
  file-write path can lose it (rows 5–7).
- `codex exec` — the dedicated non-interactive subcommand, which has no onboarding TUI at all
  (row 8). Not adopted here: it would trade the attachable TUI (ttyd/`capture-pane`, which the
  whole live-log, quota-scan and terminal-replay stack reads) for a one-shot stdout stream. Worth
  revisiting on its own merits, not as a trust-prompt fix.

`--yolo` does **not** cover this dialog. It is the one startup prompt keyed on the cwd rather than
on a `[notice]` flag, which is why the notice-acknowledgement work (task #534) did not reach it.

**Pre-seed, flag, `CODEX_HOME`, or no TTY?** The flag, *plus* the existing config entry. A
`CODEX_HOME` change buys nothing — the current home is already stable and writable, and the
failure was a lost write, not a wrong path. Removing the TTY would break the attachable terminal
the platform is built around. Belt and braces is the point: two independent grants, so losing
either one still starts clean.

**How should the platform detect this class of wedge?** By reading the pane, not by waiting for
silence. `Sessions::NoOutputWatchdog` already terminates a silent `workflow_step` session, but
only after 30 minutes, and its message blames a spend-limit dialog. The prompt itself is visible
in `capture-pane` output within seconds of launch.

## The fix

1. **`Agents::CodexAdapter#cli_trust_flag`** — the launch command carries
   `-c projects./workspace.trust_level=trusted`. The unquoted dotted form (row 6) is used
   deliberately: the command is typed in via `tmux send-keys -t agent '<cmd>' Enter`, so a flag
   that needs quotes of its own has to survive two layers of shell (row 9 verifies the whole
   path). Codex splits a `-c` key on `.`, so a workspace path containing a dot — or anything
   needing shell quoting — cannot be expressed this way; those fall back to the `config.toml`
   entry alone, which is why both grants exist.
2. **`SessionContextService#append_toml`** — an existing file that could not be read is left
   alone and the append is skipped with an `error` log, instead of being overwritten with just
   the new block. Losing MCP servers surfaces as an agent reporting a missing tool; losing the
   trust entry surfaces as a step that never speaks again.
3. **`InteractivePromptDetector`** — fails the session fast, with a diagnostic that names the
   prompt. It runs inside the existing per-minute `ScanQuotaErrorsActivity` sweep and shares that
   sweep's single `capture-pane` per session, so detection costs no extra pod-exec. It fires only
   for `non_interactive` sessions (an interactive session's owner can answer the dialog) and only
   when **every** marker of the dialog is present — the prompt text also appears in bug reports,
   task descriptions and this document, and a single-phrase match would kill the session
   investigating it.

## Regression checks

Automated (`docker compose exec -T web bin/rails test <file>`):

- `test/services/agents/codex_adapter_test.rb` — the launch command grants trust; the flag
  contains nothing shell-special (the `tmux send-keys` constraint); unaddressable workspaces drop
  the flag; the flag and `config.toml` trust the same path.
- `test/services/session_context_service_test.rb` — an unreadable `config.toml` is preserved
  rather than replaced by the MCP block; a genuinely absent one is still written fresh.
- `test/services/interactive_prompt_detector_test.rb` — the wedged pane is detected; quoted prose
  containing the prompt sentence is not.
- `test/temporal/activities/scan_quota_errors_activity_test.rb` — a `non_interactive` session on
  the prompt is failed with the diagnostic; an `interactive` one is left for its owner.

Manual, for a CLI upgrade (the automated tests pin *our* behaviour, not OpenAI's): re-run the
harness above with rows 1, 2, 3 and 6. Row 1 must still show the prompt — if it stops doing so,
the guard is no longer being exercised and the harness, not the platform, is what has drifted.
