# frozen_string_literal: true

# AgentExitDetector
#
# Recognises an agent CLI that has exited and left its pane at the shell. The launch
# command is typed into a shell in the `agent` tmux session
# (AgentBaseStrategy#send_tmux_sequence), so a CLI that refuses its arguments, crashes or
# quits drops back to that shell, and a `non_interactive` step then sits on an idle prompt
# that no other check reads as finished: task #324, Cursor CLI refusing
# `composer-2.5[effort=low]` with "Cannot use this model", waited until a person cancelled
# the run, and would otherwise have waited out the 30-minute no-output watchdog.
#
# AgentSessionStrategy#launch_agent_in_tmux appends LAUNCH_SUFFIX, which prints the CLI's
# exit status on a line of its own once it returns. The pane counts as exited only while
# that line is followed by nothing but shell prompts: an agent that prints the same words
# from inside its TUI leaves the TUI's own chrome below them.
class AgentExitDetector
  LAUNCH_SUFFIX = %(; echo "[aixle] agent exited with status $?")
  MARKER = /\A\[aixle\] agent exited with status (\d+)\z/

  # bash's default PS1 in every agent image (`root@terminal-…:/workspace#`), and Enter
  # pressed on it in the web terminal.
  SHELL_PROMPT = /\A\S+@\S+:\S*[#$]\z/

  # The typed command line ends with LAUNCH_SUFFIX, so its last wrapped row ends with `?"`
  # (the `$?"` may itself be split across two rows). The CLI's output is what lies between
  # that row and the marker.
  COMMAND_END = /\?"\z/

  # How far above the marker the CLI's output is looked for, and how many of its rows are
  # kept when the command line has scrolled out of reach.
  OUTPUT_WINDOW = 200
  FALLBACK_OUTPUT_ROWS = 15

  Result = Struct.new(:exited, :status, :output, keyword_init: true) do
    def exited? = exited
  end

  NOT_EXITED = Result.new(exited: false).freeze

  # @param text [String, nil] tmux capture-pane of the agent pane
  # @return [Result] whether the CLI has exited, its exit status, and what it printed
  #   before exiting, as one line
  def self.detect(text)
    lines = Sessions::ScreenDigest.lines(text, last: OUTPUT_WINDOW)
    marker_at = lines.rindex { |line| line.match?(MARKER) }
    return NOT_EXITED if marker_at.nil?
    return NOT_EXITED unless lines[(marker_at + 1)..].all? { |line| line.match?(SHELL_PROMPT) }

    Result.new(exited: true, status: lines[marker_at][MARKER, 1].to_i, output: output_before(lines, marker_at))
  end

  def self.output_before(lines, marker_at)
    above = lines[0...marker_at]
    command_end = above.rindex { |line| line.match?(COMMAND_END) }
    rows = command_end ? above[(command_end + 1)..] : above.last(FALLBACK_OUTPUT_ROWS)
    rows.map(&:strip).join(" ").squeeze(" ")
  end
  private_class_method :output_before
end
