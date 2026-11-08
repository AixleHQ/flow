# frozen_string_literal: true

# TurnEndDetector
#
# Recognises a CLI that finished its turn and is waiting at its own input prompt for
# the next message. In a `non_interactive` session nobody will type that message: the
# session ends only through `finish_session`, so an agent that ends its turn without
# calling it leaves the step `running` until something notices (task #208 — run
# 51997 / session 55530 sat like this for ~80 minutes; session 47395 waited out the
# 30-minute no-output watchdog after a provider error ended its turn).
#
# Unlike InteractivePromptDetector this is not a blocker: its caller,
# Sessions::Checks::TurnEnd, types a reminder into the pane rather than failing the
# session. Same shape as InteractivePromptDetector, and the same rule that only the
# current screen counts, never the scrollback.
#
# Only runtimes measured in their TUI have a signature. A runtime without one is still
# ended by Sessions::NoOutputWatchdog once its screen stops changing.
class TurnEndDetector
  # The pane's trailing block, as in InteractivePromptDetector: blank rows carry no
  # signal, and a TUI's idle screen is a handful of chrome lines under the last turn.
  TAIL_LINES = 40

  SIGNATURES = {
    # Kiro CLI 3.0.0 and 2.34.0 (`--v3`, TUI). A finished turn prints its
    # `▸ Credits: turn …` summary, then the prompt box comes back with its placeholder.
    # While a turn runs, the same line reads `Kiro is working · 6s`; with a draft typed
    # into it, it shows the draft. Below the prompt sits a right-aligned hint line
    # (`/sessions to resume · /copy to clipboard`).
    #
    # Measured on 3.0.0 at 30x20, 40x20, 80x24, 160x45 and 220x50, and on 2.34.0 at 80x24.
    # The TUI redraws for the pane's width, and tmux sizes the window to the client that was
    # active last (`window-size latest`) and keeps that size after it detaches, so a web
    # terminal on a narrow screen leaves a narrow pane behind. From 80 columns down to 40 the placeholder stays on
    # one line and only the hint wraps, to two lines. At 30 the placeholder itself wraps
    # after `describe`, which leaves three lines under the prompt's first line. So the
    # prompt is matched on its start, `› ask a question`, which a draft replaces.
    #
    # A turn that ended on a provider error (task #208, case 2) leaves the same screen,
    # with the error line above the summary.
    "kiro_cli" => {
      prompt: /\A\s*›\s+ask a question\b/,
      # Lines the CLI draws under the prompt's first line: the rest of a wrapped
      # placeholder and the hint, which wraps too on a narrow pane.
      lines_below_prompt: 3,
      turn_summary: /\A\s*▸ Credits: turn [\d.,]+ • session/,
      # The status chrome between the summary and the prompt: separators, the trust
      # and root notices (up to four lines when the root warning is not shortened),
      # and the model line, each of which wraps on a narrow pane.
      summary_within: 12
    }
  }.freeze

  # @param text [String, nil] rendered terminal output (tmux capture-pane)
  # @param agent_type [String, nil] the session's runtime
  # @return [Boolean] whether the pane ends on the runtime's idle prompt after a turn
  def self.idle?(text, agent_type:)
    signature = SIGNATURES[agent_type.to_s]
    return false if signature.nil? || text.blank?

    screen = current_screen(text)
    prompt_at = screen.rindex { |line| line.match?(signature[:prompt]) }
    return false if prompt_at.nil? || prompt_at < screen.length - 1 - signature[:lines_below_prompt]

    above = screen[[ prompt_at - signature[:summary_within], 0 ].max...prompt_at]
    above.any? { |line| line.match?(signature[:turn_summary]) }
  end

  def self.current_screen(text)
    Sessions::ScreenDigest.lines(text, last: TAIL_LINES)
  end
  private_class_method :current_screen
end
