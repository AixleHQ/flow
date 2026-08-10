# frozen_string_literal: true

module Sessions
  # Reads the terminal of a session whose container is still up.
  #
  # The container captures its agent pane with `tmux pipe-pane` into
  # /tmp/terminal_output.log (docker/base/entrypoint.sh), but that file is only
  # collected into a SessionLog during the container workflow's cleanup phase —
  # so while a session runs, the only way to see it is to ask the container.
  # This is the same read Activities::Workflow::ScanQuotaErrorsActivity has done
  # since the quota watchdog shipped, factored out so the MCP tool and the
  # watchdog cannot drift apart.
  #
  # `capture-pane` rather than the raw file on purpose: it returns the rendered
  # screen plus scrollback, already free of the ANSI redraw stream that makes
  # the raw capture unreadable to anything but xterm.js.
  class LiveLogReader
    TERMINAL_LOG_PATH = "/tmp/terminal_output.log"

    # Separates the mtime probe from the pane dump in one exec's stdout. A
    # single exec keeps this to one websocket upgrade per call — the pod-exec
    # handshake is the expensive part, not the commands.
    MARKER = "__aixle_pane__"

    # status:
    #   :ok          — pane captured
    #   :not_ready   — container is there, tmux is not (still booting, or the
    #                  agent pane is gone)
    #   :unreachable — the pod/container itself is gone
    Result = Struct.new(:status, :text, :last_output_at, keyword_init: true) do
      def ok? = status == :ok
    end

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime || ContainerRuntime.build
    end

    def tail(lines:)
      return Result.new(status: :unreachable, text: "", last_output_at: nil) if session.container_id.blank?

      container = runtime.resolve_container(session.container_id)
      return Result.new(status: :unreachable, text: "", last_output_at: nil) if container.blank?

      # exec! (not exec) so a destroyed pod arrives as ContainerUnreachableError
      # instead of an exit code of 1 that looks like a command that merely failed.
      stdout, _stderr, exit_code = runtime.exec!(container, command(lines), stdout: true, stderr: true)
      mtime, pane = split_output(Array(stdout).join)

      return Result.new(status: :not_ready, text: "", last_output_at: mtime) unless exit_code.to_i.zero?

      Result.new(status: :ok, text: pane, last_output_at: mtime)
    rescue ContainerRuntime::ContainerUnreachableError
      Result.new(status: :unreachable, text: "", last_output_at: nil)
    end

    private

    attr_reader :session, :runtime

    # The pane dump runs LAST so the exec's exit code is tmux's: a container
    # whose tmux server is not up answers non-zero, which is what separates
    # :not_ready from an agent that has simply printed nothing yet.
    def command(lines)
      [
        "/bin/sh", "-c",
        "stat -c %Y #{TERMINAL_LOG_PATH} 2>/dev/null || true; " \
        "echo #{MARKER}; " \
        "tmux capture-pane -t agent -p -S -#{lines.to_i}"
      ]
    end

    def split_output(raw)
      head, _matched, tail = raw.partition(/^#{MARKER}\n?/)
      [ parse_mtime(head), tail ]
    end

    def parse_mtime(head)
      epoch = head[/\d+/]
      return nil if epoch.blank?

      Time.zone.at(epoch.to_i)
    end
  end
end
