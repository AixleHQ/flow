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
      argv = [ "coder", "ssh", workspace_name.to_s, "--", command.to_s ]

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
          stderr:    "coder ssh: timed out after #{timeout}s",
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

    private

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

    def clamp_timeout(timeout)
      t = timeout.to_i
      return DEFAULT_TIMEOUT if t <= 0
      [ t, MAX_TIMEOUT ].min
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
