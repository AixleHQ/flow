# frozen_string_literal: true

require "open3"

module Coder
  # SshRunner — runs a shell command on a Coder workspace via `coder ssh`,
  # inside the Rails process (N1 / DD-1). The Coder URL + session token are
  # passed via the `env` argument to `Open3.capture3` so they never appear
  # in `argv`.
  #
  # Output is bounded by a single total-response budget (DD-15) — the
  # encoded JSON response is what the MCP transport actually checks. Output
  # over the budget is structurally truncated with a `truncated: true`
  # marker; the full output is still available to callers that persist it
  # to `ToolResult` (out of scope for this module).
  class SshRunner
    class CommandError < StandardError; end

    DEFAULT_TIMEOUT        = 60
    MAX_TIMEOUT            = 600
    DEFAULT_RESPONSE_BYTES = (Settings.coder&.ssh_exec_inline_bytes || 256 * 1024).to_i
    READ_CHUNK_BYTES       = 16 * 1024

    # `coder ssh <ws> -- <cmd>` runs a non-interactive shell that inherits
    # almost nothing. Without HOME every git call dies with `fatal: $HOME not
    # set`, which each session then works around by hand. Fixed here rather
    # than only in the workspace template so it also holds for boxes created
    # before that template exists. Falls back through the passwd entry to /tmp
    # because an agent running as a non-root user cannot write to /root.
    HOME_PREFIX = 'export HOME="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"; ' \
                  'export HOME="${HOME:-/tmp}"; '

    # Where detached jobs keep their command, log, pid, metadata, heartbeat and
    # exit code. The remote side falls back to $TMPDIR when this is not
    # writable, so a workspace whose template never created it still works.
    DEFAULT_JOB_DIR    = "/var/lib/aixle-jobs"
    JOB_MARKER         = "aixle_job"
    JOB_META_SEPARATOR = "---aixle_job_meta---"
    JOB_CMD_SEPARATOR  = "---aixle_job_cmd---"
    JOB_LOG_SEPARATOR  = "---aixle_job_log---"

    # How often the job wrapper stamps `<job_id>.hb` with the current time. The
    # last heartbeat is the only timestamp left when the wrapper is SIGKILLed,
    # so it is what dates a `died` job — small enough to be useful, large enough
    # to be free.
    HEARTBEAT_SECONDS = 10

    # How much of the launch command `job_status` echoes back. A gate command is
    # a line; a bootstrap script is a page — enough to identify the job, not
    # enough to crowd out the log tail.
    COMMAND_ECHO_BYTES = 2_000

    # Reason codes reported for a terminal job. They are what separates "the
    # command failed" from "something killed the command", which is the whole
    # point of recording them (task #581).
    REASON_COMPLETED      = "completed"
    REASON_COMMAND_FAILED = "command_failed"
    REASON_TIMEOUT        = "timeout"
    REASON_SIGNALED       = "signaled"
    REASON_VANISHED       = "runner_vanished"

    # A runner that vanished leaves identical evidence — no exit file, a dead
    # pid, a stale heartbeat — whether it was hard-killed on purpose
    # (`kill -9` on the job's process group, which no trap can survive) or lost
    # with the box. Nothing in the application hard-kills a detached job, so
    # there is no cancellation intent for the poll to read back; until some
    # caller records one, the poll reports both candidate causes instead of
    # asserting the one it cannot tell apart.
    VANISHED_CAUSES = %w[hard_cancellation infrastructure_failure].freeze

    # Conventional status of a command killed by `timeout(1)` — and the status
    # the foreground path returns for its own timeout.
    TIMEOUT_EXIT_CODE = 124

    # A detached job can hand structured facts back to whoever polls it by
    # printing this marker followed by `key=value` lines; `job_status` returns
    # them as `result`. That is how `RepoBootstrap` reports the commit it checked
    # out — the poll is where a detached job's outcome is available at all, so a
    # caller reads the resolved sha there rather than scraping the log tail.
    JOB_RESULT_MARKER = "---aixle_job_result---"

    # Launching a detached job is a handful of file writes; it must not inherit
    # the caller's (possibly long) timeout.
    DETACH_TIMEOUT = 30
    STATUS_TIMEOUT = 30

    # Grace window between SIGTERM and SIGKILL when killing the orphaned
    # `coder ssh` process group on timeout. Overridable so test stubs don't
    # have to wait a full grace cycle.
    class << self
      attr_accessor :kill_grace_seconds
    end
    self.kill_grace_seconds = 0.5

    # How long the job wrapper waits for the command to actually exit after
    # forwarding the signal it was sent, before escalating to SIGKILL. The
    # wrapper publishes nothing terminal until the command has been reaped, so
    # this is also the longest a cancellation can take to show up in the poll —
    # generous enough for a real test suite to finish its cleanup, short enough
    # that a command ignoring the signal cannot hold the job open. Whole
    # seconds: it becomes `sleep` in a POSIX shell. Overridable so a test does
    # not have to wait a full grace cycle.
    class << self
      attr_accessor :job_kill_grace_seconds
    end
    self.job_kill_grace_seconds = 20

    # Extra seconds the wrapper spends draining the command's process group
    # after the SIGKILL escalation has already been sent to it. A process that
    # is still there five seconds after a SIGKILL is stuck in the kernel
    # (uninterruptible I/O) and no amount of further waiting will reap it, so
    # this is the cap that stops a wrapper hanging on one — the surviving group
    # is recorded instead.
    KILL_SETTLE_SECONDS = 5

    def initialize(integration)
      @integration = integration
    end

    def exec(workspace_name:, command:, timeout: DEFAULT_TIMEOUT, max_bytes: DEFAULT_RESPONSE_BYTES)
      timeout = clamp_timeout(timeout)
      raise CommandError, "command must be a non-empty string" if command.to_s.strip.empty?
      raise CommandError, "workspace_name must be present" if workspace_name.to_s.strip.empty?

      stdout = "".dup
      stderr = "".dup
      status = nil

      env = {
        "CODER_URL"           => @integration.coder_url.to_s,
        "CODER_SESSION_TOKEN" => session_token
      }

      # The remote command is passed as a SINGLE token after the `--`
      # separator: `coder ssh <workspace> -- <command>` (the canonical shape in
      # coder-instructions.md §8, e.g. `coder ssh alex -- ps aux`). `coder ssh`
      # forwards everything after `--` to the workspace's login shell, so the
      # command string is interpreted as a shell command there (pipes, `;`,
      # quoting and redirection all work). We must NOT wrap it in our own
      # `sh -c <command>`: `coder ssh` space-joins its post-`--` argv tokens
      # before forwarding, which collapses the `sh`/`-c`/`<command>` boundaries
      # and destroys any quoting inside the command (e.g. `echo "a b"` would run
      # as the empty `echo` plus stray tokens). Keeping the command as one argv
      # element preserves it verbatim. See task #284 / issue-coder-ssh-exec.md.
      # Built outside the argv literal: interpolating it inline reads to
      # Brakeman's Execute check as a command assembled from user input, and the
      # warning is noise here — the whole point of this service is to run a
      # caller-supplied shell command, and it is passed as one argv element that
      # never reaches a local shell.
      remote_command = HOME_PREFIX + command.to_s
      argv = [ "coder", "ssh", workspace_name.to_s, "--", remote_command ]

      begin
        Open3.popen3(env, *argv, pgroup: true) do |stdin, sout, serr, wait_thr|
          stdin.close

          # Bounded chunked reads: stop once `max_bytes + 1` has been seen so
          # a runaway remote command (e.g. `cat /dev/urandom`) cannot buffer
          # gigabytes into memory before truncation runs (DD-15).
          stdout, stderr = read_streams_bounded(
            sout: sout, serr: serr, wait_thr: wait_thr,
            timeout: timeout, max_bytes: max_bytes
          )
          status = wait_thr.value
        end
      rescue Timeout::Error
        return {
          exit_code: 124,
          stdout:    "",
          stderr:    timeout_message(timeout),
          truncated: false
        }
      rescue Errno::ENOENT
        return {
          exit_code: 127,
          stdout:    "",
          stderr:    "coder ssh: command not found (the coder CLI is missing from the Rails image)",
          truncated: false
        }
      end

      truncate_response(
        exit_code: status&.exitstatus.to_i,
        stdout:    redact(stdout),
        stderr:    redact(stderr),
        max_bytes: max_bytes
      )
    end

    # Start `command` on the workspace detached from this SSH call and return
    # immediately. `docker compose run` is a client of the Docker daemon, so the
    # work it starts is NOT a child of the SSH session: killing the call on
    # timeout leaves the work running, and a caller who reads the timeout as
    # "it died" and re-issues ends up with two gates on one box. Detaching
    # removes the ambiguity — nothing to re-issue, poll `job_status` instead.
    #
    # The remote script provisions what it needs (job directory, `setsid`
    # fallback), so a workspace from an older template works unchanged.
    #
    # `env` is exported by the launcher, which travels over SSH and is never
    # written anywhere, so a secret passed this way reaches the job's process
    # environment without landing in the `<job_id>.cmd` file — the workspace is
    # long-lived and shared between sessions, and a credential left on its disk
    # outlives the session that minted it.
    def exec_detached(workspace_name:, command:, job_id: nil, env: {})
      raise CommandError, "command must be a non-empty string" if command.to_s.strip.empty?

      job_id = (job_id.presence || SecureRandom.hex(6)).to_s
      raise CommandError, "job_id must be alphanumeric" unless job_id.match?(/\A[A-Za-z0-9_-]{1,64}\z/)

      result = exec(
        workspace_name: workspace_name,
        command:        detach_script(
          job_id:         job_id,
          command:        command.to_s,
          workspace_name: workspace_name,
          env:            env
        ),
        timeout:        DETACH_TIMEOUT
      )

      unless result[:exit_code].to_i.zero?
        raise CommandError, "could not start detached job: #{result[:stderr].presence || result[:stdout]}"
      end

      job_dir = result[:stdout].to_s[/job_dir=(\S+)/, 1] || DEFAULT_JOB_DIR

      {
        job_id:     job_id,
        job_dir:    job_dir,
        log_path:   "#{job_dir}/#{job_id}.log",
        meta_path:  "#{job_dir}/#{job_id}.meta",
        started_at: result[:stdout].to_s[/started_at=(\S+)/, 1],
        detached:   true
      }.compact
    end

    # Poll a job started by `exec_detached`. States:
    #
    #   running — the runner process is alive (or has just been launched)
    #   exited  — finished; `exit_code` is the command's own status
    #   died    — the runner is gone without writing an exit code (workspace
    #             rebooted, spot interruption, OOM kill, SIGKILLed group)
    #   unknown — no trace of this job id on this workspace
    #
    # Alongside the state it returns the lifecycle metadata the wrapper recorded
    # (`command`, `workspace`, `pid`, `pgid`, `command_pid`, `command_pgid`,
    # `started_at`, `signaled_at`, `finished_at`, `elapsed_seconds`, `signal`,
    # `child_signal`, `child_exit_code`, `escalated_to`, `reason`) and a one-line
    # `diagnosis`. A terminal state is only ever published once the command AND
    # its process group have been reaped, so `exited` means the work is really
    # gone — a cancellation in progress still reads as `running`, with
    # `signaled_at` already recorded. A `died` job whose command group outlived
    # its wrapper says so in `command_group_alive`. That is
    # what makes a job that was killed before it could write its exit code
    # diagnosable: `reason` separates a command failure from a timeout, a
    # trapped cancellation and a runner that vanished, and `finished_at` falls
    # back to the last heartbeat instead of being lost (task #581). A vanished
    # runner is reported as ambiguous — see `VANISHED_CAUSES`.
    #
    # A job started by the previous wrapper has no metadata file; it still
    # reports state, exit code and log tail, and `reason` is then derived from
    # the exit code alone.
    def job_status(workspace_name:, job_id:, tail_lines: nil)
      raise CommandError, "job_id must be alphanumeric" unless job_id.to_s.match?(/\A[A-Za-z0-9_-]{1,64}\z/)

      lines  = tail_lines.to_i
      lines  = (Settings.coder&.job_status_tail_lines || 40).to_i unless lines.positive?
      result = exec(
        workspace_name: workspace_name,
        command:        status_script(job_id: job_id.to_s, tail_lines: lines),
        timeout:        STATUS_TIMEOUT
      )

      raise CommandError, "job status failed: #{result[:stderr].presence || result[:stdout]}" unless result[:exit_code].to_i.zero?

      parse_status(result[:stdout].to_s, job_id: job_id.to_s)
    end

    private

    def timeout_message(timeout)
      base = "coder ssh: timed out after #{timeout}s"
      "#{base}. The remote command may still be RUNNING — the SSH channel was killed, not the work. " \
        "Do not re-issue it; re-run with detach: true and poll coder_job_status."
    end

    # Written as a script rather than an inline one-liner so the caller's
    # command lands in a file verbatim through a quoted heredoc — no escaping,
    # no quoting damage, multi-line commands intact.
    #
    # The launcher writes `<job_id>.meta` BEFORE it starts anything: a job that
    # is killed a second later still has its identity, command and start time on
    # disk. Everything the wrapper learns afterwards is appended to the same
    # file, so reading it never needs a second source.
    def detach_script(job_id:, command:, workspace_name: nil, env: {})
      delimiter = "AIXLE_JOB_EOF_#{SecureRandom.hex(4)}"

      <<~SH
        #{env_exports(env)}JOB_DIR="${AIXLE_JOB_DIR:-#{DEFAULT_JOB_DIR}}"
        mkdir -p "$JOB_DIR" 2>/dev/null || JOB_DIR="${TMPDIR:-/tmp}/aixle-jobs"
        mkdir -p "$JOB_DIR" || { echo "cannot create a job directory" >&2; exit 1; }
        BASE="$JOB_DIR/#{job_id}"
        cat > "$BASE.cmd" <<'#{delimiter}'
        #{command}
        #{delimiter}
        : > "$BASE.log"
        rm -f "$BASE.exit" "$BASE.pid" "$BASE.hb" "$BASE.escalated"
        AIXLE_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        AIXLE_STARTED_EPOCH=$(date +%s)
        {
          echo "job_id=#{job_id}"
          echo "workspace=#{sanitized_workspace(workspace_name)}"
          echo "job_dir=$JOB_DIR"
          echo "log_path=$BASE.log"
          echo "started_at=$AIXLE_STARTED_AT"
          echo "started_at_epoch=$AIXLE_STARTED_EPOCH"
          echo "heartbeat_interval_seconds=#{HEARTBEAT_SECONDS}"
        } > "$BASE.meta"
        cat > "$BASE.run" <<'#{delimiter}_RUN'
        #{runner_script}
        #{delimiter}_RUN
        chmod +x "$BASE.run"
        if command -v setsid >/dev/null 2>&1; then
          setsid "$BASE.run" "$BASE" >/dev/null 2>&1 &
        else
          nohup "$BASE.run" "$BASE" >/dev/null 2>&1 &
        fi
        echo "#{JOB_MARKER} job_id=#{job_id} job_dir=$JOB_DIR started_at=$AIXLE_STARTED_AT"
      SH
    end

    # The wrapper that actually runs the command, written to `<job_id>.run`.
    #
    # Four things beyond running the command, all so that a job which does not
    # end normally is still explainable:
    #
    #   * a process group for the command — the command is started under
    #     `setsid`, so it leads a group of its own and the wrapper can signal the
    #     whole tree it builds rather than only the `sh <job>.cmd` shell at the
    #     top of it. `wait` reaps that shell and nothing else: a script blocked
    #     on a foreground descendant (`sleep 60; echo done`) returns the moment
    #     the shell is signalled while the descendant runs on, and a job reported
    #     terminal there is still burning the box. Signalling the group is also
    #     why the command may not share the WRAPPER's group: a group-wide kill
    #     would take the wrapper down with it and lose the metadata this whole
    #     path exists to write. Where `setsid` is missing the wrapper falls back
    #     to the command's pid, which is the old behaviour;
    #   * traps — a TERM/INT/HUP/QUIT that lands on the wrapper (an explicit
    #     cancellation, a `docker stop`, a session teardown) forwards THE SAME
    #     signal to the command's group, waits for the command to actually exit,
    #     and only THEN records the outcome and writes the exit file — instead of
    #     leaving the job looking like it evaporated. Forwarding what it actually
    #     received matters twice over: a command with signal-specific cleanup
    #     (HUP vs TERM) behaves as it would outside the wrapper, and the recorded
    #     `signal` then describes what the command was really sent rather than
    #     what the wrapper substituted for it.
    #
    #     Waiting is what makes the published state true. A `kill` that succeeds
    #     confirms delivery and nothing else: a command that traps the signal and
    #     keeps working would otherwise still be running — writing to the log,
    #     holding the box — while the poll already reported the job terminal. So
    #     the wrapper reaps the command first, then drains what is left of its
    #     group, and publishes what the reap returned (`child_exit_code`). A
    #     command that outlives the grace window (`job_kill_grace_seconds`) has
    #     its whole group escalated to SIGKILL, which is what bounds the wait and
    #     is recorded as `escalated_to`; the heartbeat keeps running throughout,
    #     so the job stays legibly `running` until it has really ended.
    #
    #     Two POSIX facts bound this, both about a *background* command in a
    #     non-interactive shell — the shell sets INT and QUIT to ignore in it,
    #     and a shell cannot re-trap a signal it inherited as ignored:
    #
    #       - the wrapper is itself launched in the background, so its INT and
    #         QUIT traps cannot fire in the detached launch path at all (TERM
    #         and HUP, the ones a teardown actually sends, are unaffected).
    #         They are kept for a wrapper run any other way, where they can;
    #       - the command is likewise started in the background, so an INT or
    #         QUIT the wrapper does manage to receive cannot be forwarded to it.
    #         TERM follows so the command is not orphaned, and `child_signal`
    #         records the substitution instead of letting the metadata imply the
    #         command handled a signal it never got;
    #   * heartbeat — a timestamp rewritten every HEARTBEAT_SECONDS, which dates
    #     the death of a job whose wrapper was SIGKILLed and therefore could not
    #     run a trap;
    #   * the command runs in the background and is `wait`ed on, because a
    #     POSIX shell only runs a trap once the foreground command returns — a
    #     wrapper blocked in the foreground would swallow the signal it is
    #     supposed to record.
    #
    # `$$` is the wrapper's pid in the subshell too (POSIX), so the heartbeat
    # loop can use it to notice the wrapper is gone and stop.
    def runner_script
      template = <<~'SH'
        #!/bin/sh
        BASE="$1"
        AIXLE_HB_INTERVAL=__HEARTBEAT_SECONDS__
        AIXLE_GRACE=__KILL_GRACE_SECONDS__
        AIXLE_SETTLE=__KILL_SETTLE_SECONDS__

        aixle_meta() { printf '%s\n' "$1" >> "$BASE.meta" 2>/dev/null; }

        # The process group of $1 — empty when it is already gone, or when the
        # workspace can answer neither way. `/proc` first: the `ps` a minimal
        # image ships (busybox) often has no `-p`, and this is the one fact the
        # signalling below depends on. Field 5 of `/proc/<pid>/stat` is the
        # pgid; the command in field 2 can contain spaces and parentheses, so
        # everything up to the LAST `)` goes first and the pgid is then the
        # third field of what is left.
        aixle_pgid_of() {
          AIXLE_PG=""
          if [ -r "/proc/$1/stat" ]; then
            AIXLE_PG=$(sed 's/^.*) *//' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f3)
          fi
          if [ -z "$AIXLE_PG" ]; then
            AIXLE_PG=$(ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ')
          fi
          printf '%s' "$AIXLE_PG"
        }

        # What a signal aimed at the command is sent to: its whole process group
        # when `setsid` gave it one of its own, the bare pid otherwise. The
        # group is only trusted when it is led by the command itself AND differs
        # from the wrapper's own group — signalling the wrapper's group would
        # kill the wrapper along with the command and lose the metadata.
        aixle_resolve_target() {
          AIXLE_TARGET="$AIXLE_CHILD"
          AIXLE_GROUP=""
          AIXLE_CGID=$(aixle_pgid_of "$AIXLE_CHILD")
          if [ -z "$AIXLE_CGID" ]; then AIXLE_CGID="$AIXLE_CHILD_PGID"; fi
          if [ -n "$AIXLE_CGID" ] && [ "$AIXLE_CGID" = "$AIXLE_CHILD" ] && [ "$AIXLE_CGID" != "$AIXLE_PGID" ]; then
            AIXLE_GROUP="$AIXLE_CGID"
            AIXLE_TARGET="-$AIXLE_CGID"
          fi
        }

        aixle_finish() {
          aixle_meta "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          aixle_meta "finished_at_epoch=$(date +%s)"
          aixle_meta "reason=$2"
          if [ -n "$3" ]; then aixle_meta "signal=$3"; fi
          aixle_meta "exit_code=$1"
          printf '%s\n' "$1" > "$BASE.exit"
        }

        aixle_on_signal() {
          AIXLE_TRAP_SIG="$1"
          AIXLE_TRAP_CODE="$2"

          # Ignored from here on: the reap below must not be re-entered by a
          # repeat signal, and the escalation window bounds how long that lasts.
          trap '' TERM INT HUP QUIT

          if [ -z "$AIXLE_CHILD" ]; then
            if [ -n "$AIXLE_HB" ]; then kill "$AIXLE_HB" 2>/dev/null; fi
            aixle_finish "$AIXLE_TRAP_CODE" signaled "$AIXLE_TRAP_SIG"
            exit "$AIXLE_TRAP_CODE"
          fi

          aixle_resolve_target

          AIXLE_CHILD_SIG="$AIXLE_TRAP_SIG"
          case "$AIXLE_TRAP_SIG" in
            INT|QUIT) AIXLE_CHILD_SIG=TERM ;;
          esac
          # `kill -NAME <target>`, not `kill -s NAME <target>`: a process GROUP is
          # a negative pid, and dash's `kill` parses the argument after `-s NAME`
          # as another option bundle, so `kill -s TERM -1234` dies with "Illegal
          # option -1". The obsolescent-but-universal `-NAME` form takes the
          # signal first and everything after it as pids, negative ones included.
          if ! kill "-$AIXLE_CHILD_SIG" "$AIXLE_TARGET" 2>/dev/null; then
            # Two different failures look the same here: the target is already
            # gone, or this shell does not know the signal name. Retrying the
            # bare pid separates them — only a rejected NAME is worth
            # substituting TERM for, and only then is the substitution recorded.
            if ! kill "-$AIXLE_CHILD_SIG" "$AIXLE_CHILD" 2>/dev/null && kill -0 "$AIXLE_CHILD" 2>/dev/null; then
              AIXLE_CHILD_SIG=TERM
              kill -TERM "$AIXLE_TARGET" 2>/dev/null || kill -TERM "$AIXLE_CHILD" 2>/dev/null
            fi
          fi
          aixle_meta "signaled_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          if [ "$AIXLE_CHILD_SIG" != "$AIXLE_TRAP_SIG" ]; then aixle_meta "child_signal=$AIXLE_CHILD_SIG"; fi

          # Delivery is not termination. A command may trap the signal and keep
          # running, so the wrapper stays alive and reaps it before publishing
          # anything terminal — a watchdog escalates to SIGKILL once the grace
          # window is up, which is what bounds the wait. The watchdog only drops
          # a marker file: the wrapper remains the single writer of the metadata,
          # whose last-line-wins ordering two writers would scramble.
          #
          # Both the signal above and this escalation go to `$AIXLE_TARGET` —
          # the command's own process group when it has one, so a descendant the
          # command shell was merely blocked on is not left behind by either.
          (
            sleep "$AIXLE_GRACE"
            if kill -0 "$AIXLE_TARGET" 2>/dev/null; then
              : > "$BASE.escalated"
              kill -KILL "$AIXLE_TARGET" 2>/dev/null
            fi
          ) &
          AIXLE_WD=$!
          wait "$AIXLE_CHILD"
          AIXLE_CHILD_CODE=$?

          # The reap covers the command shell and nothing below it. Whatever is
          # still in the command's group is still the job's work, so the wrapper
          # keeps the heartbeat and the watchdog running and waits the group out
          # before it publishes anything terminal. Bounded twice over: the
          # watchdog SIGKILLs the group at the grace boundary, and the settle
          # window caps what not even SIGKILL can reap (uninterruptible I/O) so
          # a stuck descendant cannot hold the job open for ever.
          AIXLE_SURVIVORS=""
          if [ -n "$AIXLE_GROUP" ]; then
            AIXLE_WAITED=0
            while kill -0 "$AIXLE_TARGET" 2>/dev/null; do
              AIXLE_SURVIVORS=1
              if [ "$AIXLE_WAITED" -ge $((AIXLE_GRACE + AIXLE_SETTLE)) ]; then
                aixle_meta "group_survivors=true"
                break
              fi
              sleep 1
              AIXLE_WAITED=$((AIXLE_WAITED + 1))
            done
          fi

          kill "$AIXLE_WD" 2>/dev/null
          if [ -n "$AIXLE_HB" ]; then kill "$AIXLE_HB" 2>/dev/null; fi

          aixle_meta "child_exit_code=$AIXLE_CHILD_CODE"
          # `kill -0` also succeeds on a child that has exited but is not yet
          # reaped, so the marker alone could be a hair's-breadth false positive
          # at the grace boundary. A SIGKILL that really landed shows up either
          # as the 137 the reap returns or as a group that was still populated
          # after the reap; the marker plus one of those is what gets recorded.
          if [ -f "$BASE.escalated" ]; then
            rm -f "$BASE.escalated"
            if [ "$AIXLE_CHILD_CODE" -eq 137 ] || [ -n "$AIXLE_SURVIVORS" ]; then aixle_meta "escalated_to=KILL"; fi
          fi

          # A cancelled job must never report success: a command that trapped
          # the signal and exited 0 still ended because something killed it, so
          # the conventional 128+signo status stands in and `child_exit_code`
          # keeps what the command itself returned.
          AIXLE_PUB_CODE="$AIXLE_CHILD_CODE"
          if [ "$AIXLE_CHILD_CODE" -eq 0 ]; then AIXLE_PUB_CODE="$AIXLE_TRAP_CODE"; fi
          aixle_finish "$AIXLE_PUB_CODE" signaled "$AIXLE_TRAP_SIG"
          exit "$AIXLE_PUB_CODE"
        }

        trap 'aixle_on_signal TERM 143' TERM
        trap 'aixle_on_signal INT 130' INT
        trap 'aixle_on_signal HUP 129' HUP
        trap 'aixle_on_signal QUIT 131' QUIT

        printf '%s\n' "$$" > "$BASE.pid"
        aixle_meta "pid=$$"
        AIXLE_PGID=$(aixle_pgid_of $$)
        aixle_meta "pgid=${AIXLE_PGID}"

        (
          while kill -0 $$ 2>/dev/null; do
            if printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" > "$BASE.hb.tmp" 2>/dev/null; then
              mv "$BASE.hb.tmp" "$BASE.hb" 2>/dev/null
            fi
            sleep "$AIXLE_HB_INTERVAL"
          done
        ) &
        AIXLE_HB=$!

        # `setsid` puts the command in a session — and so a process group — of
        # its own, which is what lets a cancellation reach the whole tree it
        # builds instead of only the shell at the top. It execs (the wrapper is
        # not a group leader in this child, so nothing forks in between), so the
        # command stays a direct child and `wait` below still reaps it.
        if command -v setsid >/dev/null 2>&1; then
          setsid sh "$BASE.cmd" >> "$BASE.log" 2>&1 &
          AIXLE_CHILD=$!
          AIXLE_ISOLATED=1
        else
          sh "$BASE.cmd" >> "$BASE.log" 2>&1 &
          AIXLE_CHILD=$!
          AIXLE_ISOLATED=""
        fi

        # setsid(2) runs in the child, a moment after `$!` is known here. A
        # handful of `ps` calls is enough for the new group to show up and costs
        # milliseconds — no dependency on a `sleep` that can take fractions.
        #
        # On the `setsid` path the answer is known without asking: setsid(2)
        # makes the child the leader of a session, and so of a group, of its own
        # — its group id IS its pid. The probe below can only ever confirm that,
        # and it loses the race against a command that exits before the first
        # read of `/proc/<pid>/stat` lands, which used to drop the field
        # entirely for whole classes of short job (task #581, BUG-6.1). So the
        # pid is recorded up front and the probe may only refine it, never
        # unset it. `setsid` cannot fork here — it forks only when its caller
        # already leads a group, and a freshly forked child never does — so the
        # pid really is the group the command runs in.
        AIXLE_CHILD_PGID=""
        if [ -n "$AIXLE_ISOLATED" ]; then
          AIXLE_CHILD_PGID="$AIXLE_CHILD"
          AIXLE_TRY=0
          while [ "$AIXLE_TRY" -lt 20 ]; do
            AIXLE_PROBED=$(aixle_pgid_of "$AIXLE_CHILD")
            # Gone already: nothing left to read, and the pid above still names
            # the group its survivors were left in.
            if [ -z "$AIXLE_PROBED" ]; then break; fi
            if [ "$AIXLE_PROBED" != "$AIXLE_PGID" ]; then AIXLE_CHILD_PGID="$AIXLE_PROBED"; break; fi
            AIXLE_TRY=$((AIXLE_TRY + 1))
          done
        else
          AIXLE_CHILD_PGID=$(aixle_pgid_of "$AIXLE_CHILD")
        fi

        aixle_meta "command_pid=$AIXLE_CHILD"
        if [ -n "$AIXLE_CHILD_PGID" ]; then aixle_meta "command_pgid=$AIXLE_CHILD_PGID"; fi

        wait "$AIXLE_CHILD"
        AIXLE_CODE=$?
        kill "$AIXLE_HB" 2>/dev/null

        # No group drain on this path on purpose: the command was not cancelled,
        # it decided to exit, and a process it deliberately left running in the
        # background is its own business — waiting for one here would hold a job
        # open that has genuinely finished.
        if [ "$AIXLE_CODE" -gt 128 ]; then
          AIXLE_SIGNO=$((AIXLE_CODE - 128))
          AIXLE_SIG=$(kill -l "$AIXLE_SIGNO" 2>/dev/null | tr -d ' ')
          aixle_finish "$AIXLE_CODE" signaled "${AIXLE_SIG:-$AIXLE_SIGNO}"
        elif [ "$AIXLE_CODE" -eq 0 ]; then
          aixle_finish 0 completed ""
        elif [ "$AIXLE_CODE" -eq 124 ]; then
          aixle_finish "$AIXLE_CODE" timeout ""
        else
          aixle_finish "$AIXLE_CODE" command_failed ""
        fi
      SH

      template
        .sub("__HEARTBEAT_SECONDS__", HEARTBEAT_SECONDS.to_s)
        .sub("__KILL_GRACE_SECONDS__", self.class.job_kill_grace_seconds.to_i.to_s)
        .sub("__KILL_SETTLE_SECONDS__", KILL_SETTLE_SECONDS.to_s)
    end

    # The workspace name is recorded inside a double-quoted shell string, so a
    # name carrying shell metacharacters would be a command-substitution hole.
    # Sanitised rather than rejected: a name Coder itself accepts always
    # survives this unchanged, and a launch must not start failing over a field
    # that exists only for diagnostics.
    def sanitized_workspace(workspace_name)
      workspace_name.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
    end

    # Single-quoted with the standard `'\''` escape, so a value cannot break out
    # of its quoting and become shell.
    def env_exports(env)
      return "" if env.blank?

      env.map do |key, value|
        name = key.to_s
        raise CommandError, "invalid env name: #{name}" unless name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

        "#{name}='#{value.to_s.gsub("'", "'\\\\''")}'; export #{name}\n"
      end.join
    end

    # Emits four sections: the state header, the metadata the wrapper recorded
    # (plus what only the poll can know — now, heartbeat age, log size), the
    # launch command, and the log tail. The log stays last because it is the
    # only unbounded one; the sections before it survive truncation.
    def status_script(job_id:, tail_lines:)
      <<~SH
        BASE=""
        for dir in "${AIXLE_JOB_DIR:-#{DEFAULT_JOB_DIR}}" "${TMPDIR:-/tmp}/aixle-jobs"; do
          if [ -e "$dir/#{job_id}.log" ] || [ -e "$dir/#{job_id}.exit" ] || [ -e "$dir/#{job_id}.meta" ]; then BASE="$dir/#{job_id}"; break; fi
        done
        if [ -z "$BASE" ]; then echo "#{JOB_MARKER} state=unknown exit_code="; exit 0; fi
        STATE=running
        CODE=""
        if [ -f "$BASE.exit" ]; then
          STATE=exited
          CODE=$(cat "$BASE.exit" 2>/dev/null)
        elif [ -f "$BASE.pid" ]; then
          PID=$(cat "$BASE.pid" 2>/dev/null)
          if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then STATE=running; else STATE=died; fi
        fi
        echo "#{JOB_MARKER} state=$STATE exit_code=$CODE"
        echo "#{JOB_META_SEPARATOR}"
        cat "$BASE.meta" 2>/dev/null || true
        # The command runs in a process group of its own, so a wrapper that was
        # hard-killed does not necessarily take the work with it. Whether that
        # group still has members is the difference between "gone" and "still
        # burning the box, and here is what to kill".
        if [ "$STATE" = "died" ]; then
          CGID=$(sed -n 's/^command_pgid=//p' "$BASE.meta" 2>/dev/null | tail -n 1)
          if [ -n "$CGID" ] && kill -0 "-$CGID" 2>/dev/null; then echo "command_group_alive=true"; fi
        fi
        echo "checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "checked_at_epoch=$(date +%s)"
        if [ -s "$BASE.hb" ]; then
          read HB_AT HB_EPOCH < "$BASE.hb"
          echo "heartbeat_at=$HB_AT"
          echo "heartbeat_at_epoch=$HB_EPOCH"
        fi
        if [ -f "$BASE.log" ]; then
          echo "log_bytes=$(wc -c < "$BASE.log" 2>/dev/null | tr -d ' ')"
          echo "log_modified_at_epoch=$(stat -c %Y "$BASE.log" 2>/dev/null || date -r "$BASE.log" +%s 2>/dev/null)"
        fi
        echo "#{JOB_CMD_SEPARATOR}"
        head -c #{COMMAND_ECHO_BYTES} "$BASE.cmd" 2>/dev/null || true
        echo ""
        echo "#{JOB_LOG_SEPARATOR}"
        tail -n #{tail_lines} "$BASE.log" 2>/dev/null || true
      SH
    end

    # Tolerant by construction: a job launched by the previous wrapper produces
    # only the header and the log section, and every metadata-derived field is
    # then simply absent.
    def parse_status(stdout, job_id:)
      front, _, log      = stdout.partition("#{JOB_LOG_SEPARATOR}\n")
      header, _, details = front.partition("#{JOB_META_SEPARATOR}\n")
      meta_raw, _, cmd   = details.partition("#{JOB_CMD_SEPARATOR}\n")

      report = job_report(
        job_id:    job_id,
        state:     header[/state=(\w+)/, 1] || "unknown",
        exit_code: header[/exit_code=(-?\d+)/, 1]&.to_i,
        meta:      parse_meta(meta_raw),
        command:   cmd.to_s.strip.presence,
        tail:      log.to_s
      )

      result = parse_result_block(log.to_s)
      result ? report.merge(result: result) : report
    end

    # Reads the LAST result block in the tail: a job that ran the marker twice
    # (a retried bootstrap) reports what is true now, not what was true first.
    def parse_result_block(log)
      _, marker, block = log.rpartition("#{JOB_RESULT_MARKER}\n")
      return nil if marker.empty?

      parse_meta(block).presence
    end

    # `key=value` lines, last one wins — the wrapper appends as it learns, so a
    # later line is a later fact.
    def parse_meta(raw)
      raw.to_s.each_line.each_with_object({}) do |line, meta|
        key, separator, value = line.strip.partition("=")
        next if separator.empty? || key.empty?
        meta[key] = value
      end
    end

    # `job_id`, `state`, `exit_code` and `tail` are always present — they are the
    # payload callers already depend on. Everything the wrapper could not record
    # (an old job, a job killed before it wrote anything) is dropped rather than
    # returned as a null.
    def job_report(job_id:, state:, exit_code:, meta:, command:, tail:)
      timing = job_timing(state: state, meta: meta)
      reason = job_reason(state: state, exit_code: exit_code, meta: meta)
      signal = meta["signal"].presence || signal_from_exit_code(exit_code)

      details = {
        reason:                reason,
        possible_causes:       (VANISHED_CAUSES if reason == REASON_VANISHED),
        signal:                signal,
        child_signal:          meta["child_signal"].presence,
        child_exit_code:       integer_or_nil(meta["child_exit_code"]),
        escalated_to:          meta["escalated_to"].presence,
        signaled_at:           meta["signaled_at"].presence,
        diagnosis:             job_diagnosis(
          state: state, exit_code: exit_code, reason: reason, signal: signal, timing: timing, meta: meta
        ),
        command:               command,
        workspace:             meta["workspace"].presence,
        pid:                   integer_or_nil(meta["pid"]),
        pgid:                  integer_or_nil(meta["pgid"]),
        command_pid:           integer_or_nil(meta["command_pid"]),
        command_pgid:          integer_or_nil(meta["command_pgid"]),
        command_group_alive:   (true if meta["command_group_alive"] == "true"),
        started_at:            meta["started_at"].presence,
        finished_at:           timing[:finished_at],
        finished_at_estimated: timing[:estimated],
        elapsed_seconds:       timing[:elapsed_seconds],
        last_heartbeat_at:     meta["heartbeat_at"].presence,
        heartbeat_age_seconds: timing[:heartbeat_age_seconds],
        log_path:              meta["log_path"].presence,
        log_bytes:             integer_or_nil(meta["log_bytes"])
      }

      { job_id: job_id, state: state, exit_code: exit_code }
        .merge(details.compact)
        .merge(tail: tail)
    end

    # A job the wrapper finished dates itself. A job that was killed before it
    # could does not, so the last heartbeat stands in — and says so, because an
    # estimate that reads as a measurement is worse than no estimate.
    def job_timing(state:, meta:)
      started  = integer_or_nil(meta["started_at_epoch"])
      finished = integer_or_nil(meta["finished_at_epoch"])
      checked  = integer_or_nil(meta["checked_at_epoch"])
      beat     = integer_or_nil(meta["heartbeat_at_epoch"])
      log_seen = integer_or_nil(meta["log_modified_at_epoch"])

      last_sign = beat || log_seen
      timing    = { heartbeat_age_seconds: (checked - beat if checked && beat) }

      if finished
        timing.merge!(finished_at: meta["finished_at"].presence, at: finished)
      elsif state == "died" && last_sign
        stamped = beat ? meta["heartbeat_at"].presence : nil
        timing.merge!(finished_at: stamped || epoch_to_iso8601(last_sign), at: last_sign, estimated: true)
      elsif state == "running"
        timing[:at] = checked
      end

      timing[:elapsed_seconds] = timing[:at] - started if started && timing[:at]
      timing
    end

    def job_reason(state:, exit_code:, meta:)
      case state
      when "exited" then meta["reason"].presence || reason_from_exit_code(exit_code)
      when "died"   then REASON_VANISHED
      end
    end

    # Fallback for a job started by the previous wrapper, which recorded no
    # reason: the exit code alone still separates the common cases. `> 128` as
    # "killed by signal n - 128" is a convention, not a guarantee — the same one
    # the wrapper applies to its own child.
    def reason_from_exit_code(exit_code)
      return nil if exit_code.nil?
      return REASON_COMPLETED if exit_code.zero?
      return REASON_TIMEOUT if exit_code == TIMEOUT_EXIT_CODE
      return REASON_SIGNALED if exit_code > 128
      REASON_COMMAND_FAILED
    end

    def signal_from_exit_code(exit_code)
      return nil unless exit_code.to_i > 128
      (exit_code - 128).to_s
    end

    # One line an agent can act on. The outcomes the task cares about read
    # differently on purpose: a non-zero exit is the command's own verdict, a
    # trapped signal is something outside it, and a vanished runner is one of
    # two outside causes the evidence cannot separate.
    def job_diagnosis(state:, exit_code:, reason:, signal:, timing:, meta:)
      elapsed = timing[:elapsed_seconds]
      after   = elapsed ? " after #{elapsed}s" : ""

      case reason
      when REASON_COMPLETED
        "the command completed successfully#{after}"
      when REASON_COMMAND_FAILED
        "the command itself exited #{exit_code}#{after} — its own failure (a failing test, lint or build), " \
          "not an infrastructure problem; read the log tail"
      when REASON_TIMEOUT
        "the command exited #{TIMEOUT_EXIT_CODE}#{after}, the conventional timeout status — it ran out of time " \
          "rather than failing on its own terms"
      when REASON_SIGNALED
        "the job was terminated by SIG#{signal || "?"}#{forwarded_as(signal: signal, meta: meta)}#{after} — " \
          "an explicit cancellation or an outside kill (session teardown, `docker stop`, an operator), " \
          "not a command failure#{escalated_as(meta: meta)}#{outlived_by(exit_code: exit_code, meta: meta)}" \
          "#{survivors_note(meta: meta)}"
      when REASON_VANISHED
        vanished_diagnosis(timing: timing, meta: meta)
      else
        case state
        when "running" then "the job is still running#{after}"
        when "unknown" then "no trace of this job id on this workspace"
        else "the job is #{state} and the workspace recorded no reason for it"
        end
      end
    end

    # The wrapper forwards the signal it received, so the two are normally the
    # same and this says nothing. It speaks up for the INT/QUIT case, where the
    # command cannot receive what the wrapper got and was sent TERM instead —
    # the divergence belongs in the diagnosis rather than only in a field.
    def forwarded_as(signal:, meta:)
      delivered = meta["child_signal"].presence
      return "" if delivered.nil? || delivered == signal

      " (delivered to the command as SIG#{delivered}, which cannot receive SIG#{signal} in the background)"
    end

    # The wrapper does not publish a terminal state until the command has been
    # reaped, so a job that took the escalation was one the first signal did not
    # end. Worth saying: "terminated by SIGTERM" alone would leave an operator
    # thinking the command shut itself down cleanly when it had to be killed —
    # which is also where to look for a command whose cleanup does not finish in
    # the grace window.
    def escalated_as(meta:)
      target = meta["escalated_to"].presence
      return "" if target.nil?

      ". The command did not exit within the #{self.class.job_kill_grace_seconds.to_i}s grace window, so the " \
        "wrapper escalated to SIG#{target} — that, not the signal above, is what ended it"
    end

    # The other way a reap can surprise: the command trapped the cancellation and
    # exited 0 on its own terms. The job is still reported as cancelled — it did
    # not run to completion — so the command's own status is stated rather than
    # silently replaced by the conventional 128+signo one.
    def outlived_by(exit_code:, meta:)
      child = integer_or_nil(meta["child_exit_code"])
      return "" if child.nil? || child == exit_code

      ". The command handled the signal and exited #{child} itself; the job is still reported as " \
        "#{exit_code} because it was cancelled rather than finished"
    end

    # Deliberately does NOT pick a cause. A hard cancellation (`kill -9` on the
    # job's process group) and an infrastructure failure (workspace reboot, spot
    # interruption, OOM kill) are observationally identical here — both leave a
    # dead runner, no exit file and a stale heartbeat — so naming one would send
    # an operator down a path the evidence does not support. What the poll can
    # say for certain is that this is not the command's own verdict.
    def vanished_diagnosis(timing:, meta:)
      pid = meta["pid"].presence

      "the runner process#{pid ? " (pid #{pid})" : ""} is gone and never wrote an exit code; " \
        "#{last_sign_of_life(timing)}. The cause is indeterminate: a hard cancellation (SIGKILL on the " \
        "job's process group, which leaves the wrapper no chance to record it) and an infrastructure " \
        "failure (workspace reboot, spot interruption, OOM kill) produce exactly this evidence. Not the " \
        "command's own failure either way — check the log tail and the workspace before concluding which" \
        "#{command_group_note(meta: meta)}"
    end

    # The command has its own process group, so losing the wrapper does not
    # necessarily stop the work: the poll says so rather than letting `died`
    # imply an idle workspace, and names the group to kill.
    def command_group_note(meta:)
      return "" unless meta["command_group_alive"] == "true"

      pgid = meta["command_pgid"].presence
      ". The command's own process group#{pgid ? " (pgid #{pgid})" : ""} is STILL RUNNING — the wrapper " \
        "died, the work did not#{pgid ? "; `kill -TERM -#{pgid}` on the workspace stops it" : ""}"
    end

    # A descendant that outlived even the SIGKILL of its group: the job is over
    # as far as the wrapper is concerned, but the workspace is not clean.
    def survivors_note(meta:)
      return "" unless meta["group_survivors"] == "true"

      pgid = meta["command_pgid"].presence
      ". Something in the command's process group#{pgid ? " (pgid #{pgid})" : ""} survived the SIGKILL and " \
        "was still there when the job was published — most likely stuck in uninterruptible I/O; check the " \
        "workspace before reusing it"
    end

    def last_sign_of_life(timing)
      unless timing[:estimated] && timing[:finished_at]
        return "no heartbeat was ever recorded — it died within the first #{HEARTBEAT_SECONDS}s, " \
               "or it predates lifecycle metadata"
      end

      age = timing[:heartbeat_age_seconds]
      "last sign of life #{timing[:finished_at]}#{age ? " (#{age}s before this check)" : ""}"
    end

    def integer_or_nil(value)
      value.to_s.match?(/\A-?\d+\z/) ? value.to_i : nil
    end

    def epoch_to_iso8601(epoch)
      return nil if epoch.nil?
      Time.at(epoch).utc.iso8601
    end

    # Bounded chunked reader for the child's stdout/stderr. Reader threads
    # stop pulling from each pipe once they have accumulated `max_bytes + 1`,
    # which is all `truncate_response` needs to detect truncation. On deadline
    # expiry the child *process group* is signalled (SIGTERM → SIGKILL) — the
    # process was spawned with `pgroup: true` so the negative pid targets the
    # whole group and reaps orphaned `coder ssh` subprocesses (well-known Ruby
    # `Timeout.timeout` + popen3 gotcha that the previous implementation hit).
    def read_streams_bounded(sout:, serr:, wait_thr:, timeout:, max_bytes:)
      cap         = max_bytes.to_i + 1
      out_thread  = read_bounded_async(sout, cap)
      err_thread  = read_bounded_async(serr, cap)
      deadline_at = monotonic_now + timeout

      while out_thread.alive? || err_thread.alive?
        remaining = deadline_at - monotonic_now
        if remaining <= 0
          kill_process_group(wait_thr)
          [ out_thread, err_thread ].each { |t| t.kill if t.alive? }
          raise Timeout::Error
        end

        sleep [ remaining, 0.05 ].min
      end

      [ out_thread.value.to_s, err_thread.value.to_s ]
    end

    def read_bounded_async(io, cap)
      Thread.new do
        buffer = "".dup
        while buffer.bytesize <= cap
          chunk = io.read(READ_CHUNK_BYTES)
          break if chunk.nil? || chunk.empty?
          buffer << chunk
        end
        buffer
      rescue IOError, Errno::EBADF
        buffer
      end
    end

    def kill_process_group(wait_thr)
      pid = wait_thr&.pid
      return unless pid

      begin
        Process.kill("-TERM", pid)
      rescue Errno::ESRCH, Errno::EPERM
        return
      end

      # Best-effort SIGKILL escalation after a short grace period if the child
      # hasn't exited. We don't `Process.wait` here — the outer popen3 block
      # owns reaping via `wait_thr.value`.
      sleep self.class.kill_grace_seconds
      begin
        Process.kill("-KILL", pid) if wait_thr.respond_to?(:alive?) && wait_thr.alive?
      rescue Errno::ESRCH, Errno::EPERM
        # Process already exited between the two kills.
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # `timeout_seconds` used to advertise 600 while the MCP transport gave up
    # on the call long before that, so a caller asking for 330 saw a timeout at
    # ~150 and had no way to know which layer produced it. Clamp to the ceiling
    # we can actually reach; anything longer belongs in a detached job.
    def clamp_timeout(timeout)
      t = timeout.to_i
      return [ DEFAULT_TIMEOUT, ceiling_seconds ].min if t <= 0
      [ t, MAX_TIMEOUT, ceiling_seconds ].min
    end

    def ceiling_seconds
      value = (Settings.coder&.ssh_exec_ceiling_seconds || MAX_TIMEOUT).to_i
      value.positive? ? value : MAX_TIMEOUT
    end

    def session_token
      @integration.credentials_data["session_token"].to_s
    end

    def redact(message)
      token = session_token
      return message.to_s if token.empty?
      message.to_s.gsub(token, "[REDACTED]")
    end

    def truncate_response(exit_code:, stdout:, stderr:, max_bytes:)
      total = stdout.bytesize + stderr.bytesize
      return { exit_code: exit_code, stdout: stdout, stderr: stderr, truncated: false } if total <= max_bytes

      # Reserve some budget for stderr (we cap it at 16 KiB or its full size).
      stderr_budget = [ stderr.bytesize, [ max_bytes / 8, 16 * 1024 ].min ].min
      stdout_budget = [ max_bytes - stderr_budget, 0 ].max

      {
        exit_code:         exit_code,
        stdout:            stdout.byteslice(0, stdout_budget),
        stderr:            stderr.byteslice(0, stderr_budget),
        truncated:         true,
        stdout_bytes_total: stdout.bytesize,
        stderr_bytes_total: stderr.bytesize
      }
    end
  end
end
