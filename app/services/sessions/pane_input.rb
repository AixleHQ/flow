# frozen_string_literal: true

module Sessions
  # Types a message into a session's agent pane and submits it, the way a person at the
  # terminal would. Sessions::AuthPause sends its resume prompt with it,
  # Sessions::Checks::TurnEnd its reminder.
  #
  # The text and its `Enter` go in one tmux invocation (`send-keys -l TEXT ; … ; send-keys Enter`).
  # Two execs could fail between them and leave the text as an unsent draft in the prompt box,
  # where it hides the idle prompt from TurnEndDetector and nothing submits it.
  #
  # The pause before `Enter` is for Copilot CLI (measured on 1.0.108): a message of reminder
  # length arriving in one burst is taken for a paste, and an `Enter` right behind it lands
  # inside the paste and is dropped, so the message stays a draft. 0.1 s was enough; with no
  # pause a 150-character message never submitted.
  module PaneInput
    TARGET = "agent"
    SUBMIT_PAUSE = "sleep 0.2"

    # `-l` sends the text literally, so tmux does not read words in it as key names. The
    # standalone ";" arguments separate the tmux commands.
    def self.command(text)
      [ "tmux", "send-keys", "-t", TARGET, "-l", text.to_s, ";", "run-shell", SUBMIT_PAUSE, ";",
        "send-keys", "-t", TARGET, "Enter" ]
    end

    # @return [Boolean] whether tmux accepted the keys
    def self.type(session, text, runtime:)
      return false if session.container_id.blank?

      container = runtime.resolve_container(session.container_id)
      return false unless container

      Array(runtime.exec(container, command(text)))[2].to_i.zero?
    rescue StandardError => e
      Rails.logger.warn("[PaneInput] session=#{session.id} could not type into the pane: #{e.class}: #{e.message}")
      false
    end
  end
end
