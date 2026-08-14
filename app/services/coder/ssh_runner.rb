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

    # Conventional status of a command killed by `timeout(1)` — and the status
    # the foreground path returns for its own timeout.
    TIMEOUT_EXIT_CODE = 124

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
    # (`command`, `workspace`, `pid`, `pgid`, `started_at`, `finished_at`,
    # `elapsed_seconds`, `signal`, `reason`) and a one-line `diagnosis`. That is
    # what makes a job that was killed before it could write its exit code
    # diagnosable: `reason` separates a command failure from a timeout, an
    # explicit cancellation and an infrastructure failure, and `finished_at`
    # falls back to the last heartbeat instead of being lost (task #581).
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
        rm -f "$BASE.exit" "$BASE.pid" "$BASE.hb"
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
    # Three things beyond running the command, all so that a job which does not
    # end normally is still explainable:
    #
    #   * traps — a TERM/INT/HUP/QUIT that lands on the wrapper (an explicit
    #     cancellation, a `docker stop`, a session teardown) forwards to the
    #     command and THEN records the signal and writes the exit file, instead
    #     of leaving the job looking like it evaporated;
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
      <<~'SH'.sub("__HEARTBEAT_SECONDS__", HEARTBEAT_SECONDS.to_s)
        #!/bin/sh
        BASE="$1"
        AIXLE_HB_INTERVAL=__HEARTBEAT_SECONDS__

        aixle_meta() { printf '%s\n' "$1" >> "$BASE.meta" 2>/dev/null; }

        aixle_finish() {
          aixle_meta "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          aixle_meta "finished_at_epoch=$(date +%s)"
          aixle_meta "reason=$2"
          if [ -n "$3" ]; then aixle_meta "signal=$3"; fi
          aixle_meta "exit_code=$1"
          printf '%s\n' "$1" > "$BASE.exit"
        }

        aixle_on_signal() {
          if [ -n "$AIXLE_CHILD" ]; then kill -TERM "$AIXLE_CHILD" 2>/dev/null; fi
          if [ -n "$AIXLE_HB" ]; then kill "$AIXLE_HB" 2>/dev/null; fi
          aixle_finish "$2" signaled "$1"
          exit "$2"
        }

        trap 'aixle_on_signal TERM 143' TERM
        trap 'aixle_on_signal INT 130' INT
        trap 'aixle_on_signal HUP 129' HUP
        trap 'aixle_on_signal QUIT 131' QUIT

        printf '%s\n' "$$" > "$BASE.pid"
        aixle_meta "pid=$$"
        AIXLE_PGID=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
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

        sh "$BASE.cmd" >> "$BASE.log" 2>&1 &
        AIXLE_CHILD=$!
        wait "$AIXLE_CHILD"
        AIXLE_CODE=$?
        kill "$AIXLE_HB" 2>/dev/null

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

      job_report(
        job_id:    job_id,
        state:     header[/state=(\w+)/, 1] || "unknown",
        exit_code: header[/exit_code=(-?\d+)/, 1]&.to_i,
        meta:      parse_meta(meta_raw),
        command:   cmd.to_s.strip.presence,
        tail:      log.to_s
      )
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
        signal:                signal,
        diagnosis:             job_diagnosis(
          state: state, exit_code: exit_code, reason: reason, signal: signal, timing: timing, meta: meta
        ),
        command:               command,
        workspace:             meta["workspace"].presence,
        pid:                   integer_or_nil(meta["pid"]),
        pgid:                  integer_or_nil(meta["pgid"]),
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
        timing.merge!(finished_at: epoch_to_iso8601(last_sign), at: last_sign, estimated: true)
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

    # One line an agent can act on. The four outcomes the task cares about read
    # differently on purpose: a non-zero exit is the command's own verdict, a
    # signal is something outside it, a vanished runner is the box.
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
        "the job was terminated by SIG#{signal || "?"}#{after} — an explicit cancellation or an outside kill " \
          "(session teardown, `docker stop`, an operator), not a command failure"
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

    def vanished_diagnosis(timing:, meta:)
      pid  = meta["pid"].presence
      age  = timing[:heartbeat_age_seconds]
      seen = if timing[:estimated] && timing[:finished_at]
               "last sign of life #{timing[:finished_at]}#{age ? " (#{age}s before this check)" : ""}"
             else
               "no heartbeat was ever recorded — it died within the first #{HEARTBEAT_SECONDS}s, " \
                 "or it predates lifecycle metadata"
             end

      "the runner process#{pid ? " (pid #{pid})" : ""} is gone and never wrote an exit code; #{seen}. " \
        "An infrastructure failure — workspace reboot, OOM kill or a SIGKILLed process group — " \
        "rather than anything the command did"
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
