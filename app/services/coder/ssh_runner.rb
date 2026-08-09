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

    # Where detached jobs keep their command, log, pid and exit code. The
    # remote side falls back to $TMPDIR when this is not writable, so a
    # workspace whose template never created it still works.
    DEFAULT_JOB_DIR   = "/var/lib/aixle-jobs"
    JOB_MARKER        = "aixle_job"
    JOB_LOG_SEPARATOR = "---aixle_job_log---"

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
      argv = [ "coder", "ssh", workspace_name.to_s, "--", "#{HOME_PREFIX}#{command}" ]

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
    def exec_detached(workspace_name:, command:, job_id: nil)
      raise CommandError, "command must be a non-empty string" if command.to_s.strip.empty?

      job_id = (job_id.presence || SecureRandom.hex(6)).to_s
      raise CommandError, "job_id must be alphanumeric" unless job_id.match?(/\A[A-Za-z0-9_-]{1,64}\z/)

      result = exec(
        workspace_name: workspace_name,
        command:        detach_script(job_id: job_id, command: command.to_s),
        timeout:        DETACH_TIMEOUT
      )

      unless result[:exit_code].to_i.zero?
        raise CommandError, "could not start detached job: #{result[:stderr].presence || result[:stdout]}"
      end

      job_dir = result[:stdout].to_s[/job_dir=(\S+)/, 1] || DEFAULT_JOB_DIR

      {
        job_id:   job_id,
        job_dir:  job_dir,
        log_path: "#{job_dir}/#{job_id}.log",
        detached: true
      }
    end

    # Poll a job started by `exec_detached`. States:
    #
    #   running — the runner process is alive (or has just been launched)
    #   exited  — finished; `exit_code` is the command's own status
    #   died    — the runner is gone without writing an exit code (workspace
    #             rebooted, spot interruption, OOM kill)
    #   unknown — no trace of this job id on this workspace
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
    def detach_script(job_id:, command:)
      delimiter = "AIXLE_JOB_EOF_#{SecureRandom.hex(4)}"

      <<~SH
        JOB_DIR="${AIXLE_JOB_DIR:-#{DEFAULT_JOB_DIR}}"
        mkdir -p "$JOB_DIR" 2>/dev/null || JOB_DIR="${TMPDIR:-/tmp}/aixle-jobs"
        mkdir -p "$JOB_DIR" || { echo "cannot create a job directory" >&2; exit 1; }
        BASE="$JOB_DIR/#{job_id}"
        cat > "$BASE.cmd" <<'#{delimiter}'
        #{command}
        #{delimiter}
        : > "$BASE.log"
        rm -f "$BASE.exit" "$BASE.pid"
        cat > "$BASE.run" <<'#{delimiter}_RUN'
        #!/bin/sh
        echo $$ > "$1.pid"
        sh "$1.cmd" >> "$1.log" 2>&1
        echo $? > "$1.exit"
        #{delimiter}_RUN
        chmod +x "$BASE.run"
        if command -v setsid >/dev/null 2>&1; then
          setsid "$BASE.run" "$BASE" >/dev/null 2>&1 &
        else
          nohup "$BASE.run" "$BASE" >/dev/null 2>&1 &
        fi
        echo "#{JOB_MARKER} job_id=#{job_id} job_dir=$JOB_DIR"
      SH
    end

    def status_script(job_id:, tail_lines:)
      <<~SH
        BASE=""
        for dir in "${AIXLE_JOB_DIR:-#{DEFAULT_JOB_DIR}}" "${TMPDIR:-/tmp}/aixle-jobs"; do
          if [ -e "$dir/#{job_id}.log" ] || [ -e "$dir/#{job_id}.exit" ]; then BASE="$dir/#{job_id}"; break; fi
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
        echo "#{JOB_LOG_SEPARATOR}"
        tail -n #{tail_lines} "$BASE.log" 2>/dev/null || true
      SH
    end

    def parse_status(stdout, job_id:)
      header, _, log = stdout.partition("#{JOB_LOG_SEPARATOR}\n")
      state = header[/state=(\w+)/, 1] || "unknown"
      code  = header[/exit_code=(-?\d+)/, 1]

      {
        job_id:    job_id,
        state:     state,
        exit_code: code&.to_i,
        tail:      log.to_s
      }
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
