# frozen_string_literal: true

require "digest"

module Sessions
  # A fingerprint of what a session's terminal shows, to tell a screen that changed from
  # one that was only redrawn. The bytes a pane sends are not that signal: an idle Kiro TUI
  # repaints its unchanged screen (12 KB on one resize of the pane, measured on 3.0.0), so a
  # web terminal attached to it keeps /tmp/terminal_output.log fresh while nothing happens.
  module ScreenDigest
    # The bottom of the rendered pane, where every runtime draws its working indicator.
    LINES = 40

    def self.of(text)
      Digest::SHA256.hexdigest(lines(text, last: LINES).join("\n"))
    end

    # The pane's current screen as every reader of it sees it: its last `last` nonblank
    # lines, right-trimmed. tmux pads capture-pane output to the pane height and TUIs draw
    # blank separator rows, so blank lines carry no signal, and dropping them is what makes
    # "the last line" the last thing the CLI rendered. Invalid UTF-8 is replaced rather
    # than raised on, since a pane can end in the middle of a multibyte character.
    def self.lines(text, last:)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.lines.map(&:rstrip).reject(&:empty?).last(last)
    end
  end
end
