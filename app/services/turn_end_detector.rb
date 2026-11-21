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
# ended by Sessions::Checks::NoOutput once its screen stops changing.
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
      # The turn summary, above the status chrome between it and the prompt: separators,
      # the trust and root notices (up to four lines when the root warning is not
      # shortened), and the model line, each of which wraps on a narrow pane.
      above: { match: /\A\s*▸ Credits: turn [\d.,]+ • session/, within: 12 }
    },
    # Copilot CLI 1.0.108 (TUI). The pane ends on a hint line under the prompt box. A
    # finished turn leaves `← open sidebar · Interactive · …`, cut down to `Interactive`
    # and the model on a narrow pane; while a turn runs the same line reads `● Working ·
    # … ctrl+c interrupt`, and with a draft in the box it lists `@ files/sessions`. The
    # session's `Session: 2.38 AIC used` line sits four lines above the hint, whether the
    # box is drawn with rules (`❯` between two `───` lines) or, in the platform's web
    # terminal, as `╻▄▄▄` / `┃` / `╹▀▀▀`.
    #
    # Measured at 30x20, 40x20, 80x24, 112x16 and 220x50. On a plan still billed in premium
    # requests the CLI shows no usage figure, so no turn end is seen and
    # Sessions::Checks::NoOutput ends the session instead.
    "copilot_cli" => {
      prompt: /\A\s*(?:← open sidebar · Interactive · |Interactive\s{2,})/,
      lines_below_prompt: 0,
      above: { match: /Session: [\d.,]+ AIC used\z/, within: 6 }
    },
    # Antigravity CLI 1.5.13 (TUI, `-i`). The pane ends on a footer that starts with
    # `? for shortcuts` at rest and `esc to cancel` while a turn runs, at every width (the
    # model part on its right is dropped below about 60 columns). Above it sit a rule, the
    # input box line and another rule; the box line is the `> Auto mode: …` placeholder, or
    # a bare `>` once anything has been typed into it. A turn that left a command running in
    # the background puts a task panel between the box and the footer and is resumed by agy
    # itself when the command ends, so an input box anywhere but two lines up is no turn
    # end. agy prints no per-turn summary; the screen before the `-i` prompt is submitted
    # looks the same, but lasts under a second, and Sessions::Checks::TurnEnd waits for a
    # second pass on the same screen.
    "antigravity_cli" => {
      prompt: /\A\s*\? for shortcuts\b/,
      lines_below_prompt: 0,
      above: { match: /\A>(?:\z| Auto mode: )/, at: 2 }
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

    lines_above(screen, prompt_at, signature[:above]).any? { |line| line.match?(signature[:above][:match]) }
  end

  # What has to show above the prompt for the screen to be a finished turn: a line
  # `within` that many lines of it (a turn summary), or the line exactly `at` that many
  # lines up (an input box that is empty).
  def self.lines_above(screen, prompt_at, above)
    return screen[[ prompt_at - above[:within], 0 ].max...prompt_at] if above[:within]

    at = prompt_at - above.fetch(:at)
    at >= 0 ? [ screen[at] ] : []
  end
  private_class_method :lines_above

  def self.current_screen(text)
    Sessions::ScreenDigest.lines(text, last: TAIL_LINES)
  end
  private_class_method :current_screen
end
