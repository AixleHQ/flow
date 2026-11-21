# frozen_string_literal: true

module Sessions
  # What Sessions::Monitor read of one live session's terminal, once, for every check that
  # applies to it (Sessions::Checks). It lives for one pass and is never stored: a check
  # keeps what its own later runs need in the session's metadata (Checks::KeptState).
  #
  # The parts come from Snapshot::Parts::REGISTRY. A part that was not asked for, or could
  # not be read, answers nil, and every helper below treats nil as "unknown", never as
  # "quiet" or "nobody there".
  #
  # The source is replaceable per runtime (.source_for). Today every session's snapshot is
  # an exec (ExecSource). Once a runner pushes its session's live log itself (task 8c), a
  # runner session's snapshot comes from that instead, behind the same interface.
  class Snapshot
    # The bottom of the rendered pane, where every runtime draws its error, its dialog,
    # its prompt and its working indicator.
    SCREEN_LINES = ScreenDigest::LINES

    def self.read(session, parts:, runtime:)
      parts = parts.map { |name| Parts.fetch(name).name }.uniq
      new(source_for(session, runtime: runtime).read(parts).to_h do |name, raw|
        [ name, Parts.fetch(name).parse.call(raw) ]
      end)
    end

    def self.source_for(session, runtime:)
      ExecSource.new(session, runtime: runtime)
    end

    def initialize(parts = {})
      @parts = parts.freeze
    end

    def read?(part) = @parts.key?(part)

    # The pane with its scrollback, or nil when it could not be read.
    def scrollback = @parts[:scrollback]

    # The pane's current screen as every check reads it: its last `last` nonblank lines,
    # right-trimmed (ScreenDigest.lines). Empty when the pane could not be read.
    def screen(last: SCREEN_LINES)
      ScreenDigest.lines(scrollback, last: last)
    end

    def screen_digest = ScreenDigest.of(scrollback)

    # When the pane last sent a byte. Only from a read that also captured the pane: a
    # container whose tmux is gone still has a log, and its mtime says nothing about an
    # agent that is no longer there.
    def last_output_at
      @parts[:log_mtime] if read?(:scrollback)
    end

    # False when the container cannot say: an unknown pane is not a quiet one.
    def quiet_for?(duration)
      last_output_at.present? && last_output_at < duration.ago
    end

    # Parts::Clients, or nil when the clients could not be read.
    def clients = @parts[:clients]
  end
end
