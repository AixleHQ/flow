# frozen_string_literal: true

module Sessions
  class Snapshot
    # The registry of what a snapshot can hold. A check names the parts it needs
    # (Sessions::Checks::Base.parts), and Sessions::Monitor reads the union of the
    # applicable checks' parts with one exec: Command builds that exec from this registry.
    #
    # Each part is one shell fragment, run in its own section of the script, so one that
    # fails (no tmux clients to list, a log not written yet) leaves the others readable.
    # A part counts as read only when its fragment exited 0.
    module Parts
      TERMINAL_LOG_PATH = "/tmp/terminal_output.log"

      # How far back the pane is captured. A CLI renders the error it stopped on at the
      # bottom (the current screen, Snapshot#screen); the scrollback above it only feeds
      # the checks that read the whole pane.
      SCROLLBACK_LINES = 1000

      Part = Data.define(:name, :script, :parse)

      REGISTRY = {
        # The pane and its scrollback, rendered by tmux, without the ANSI redraw stream
        # of the raw log. The current screen comes out of it (Snapshot#screen).
        scrollback: Part.new(
          name: :scrollback,
          script: "tmux capture-pane -t agent -p -S -#{SCROLLBACK_LINES} 2>/dev/null",
          parse: ->(text) { text }
        ),
        # When the pane last sent a byte: the mtime of the log tmux pipe-pane writes
        # (docker/base/entrypoint.sh).
        log_mtime: Part.new(
          name: :log_mtime,
          script: "stat -c %Y #{TERMINAL_LOG_PATH} 2>/dev/null",
          parse: ->(text) { (epoch = text[/\d+/]) ? Time.zone.at(epoch.to_i) : nil }
        ),
        # tmux's record of each client attached to the agent pane: whether it is read-only
        # (the web terminal everyone but the session's owner gets) and when it last sent
        # input. The container's clock comes first, so a comparison does not depend on
        # clock skew.
        clients: Part.new(
          name: :clients,
          script: "date +%s && tmux list-clients -t agent -F '\#{client_readonly} \#{client_activity}' 2>/dev/null",
          parse: lambda do |text|
            clock, *rows = text.split("\n").map(&:strip).reject(&:empty?)
            Clients.new(clock: clock.to_i, rows: rows.map { |row| row.split.then { |ro, at| [ ro == "1", at.to_i ] } })
          end
        )
      }.freeze

      NAMES = REGISTRY.keys.freeze

      # `rows` are [read_only, last_input_epoch] pairs; `clock` is the container's epoch.
      Clients = Data.define(:clock, :rows) do
        # Whether a writable client sent input within `duration`.
        def input_within?(duration)
          rows.any? { |read_only, input_at| !read_only && clock - input_at < duration.to_i }
        end
      end

      def self.fetch(name)
        REGISTRY.fetch(name.to_sym) { raise ArgumentError, "unknown snapshot part: #{name}" }
      end
    end
  end
end
