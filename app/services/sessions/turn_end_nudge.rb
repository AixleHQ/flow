# frozen_string_literal: true

module Sessions
  # Sends an automatic session's agent back to work when it ended its turn without
  # `finish_session` (task #208).
  #
  # Automatic sessions run the CLI's TUI, and a TUI whose turn ends waits for a person at
  # its prompt. The agent ends a turn this way after a slip of the model, or because a
  # provider error ended it. Nothing else notices: the step stays `running` until the
  # no-output watchdog fails it, with the session's context lost.
  #
  # Kiro's `Stop` hook was measured first (kiro-cli 3.0.0, TUI) and not used: a `block`
  # makes the agent continue, but the hook runs once per prompt (a second turn end in the
  # same prompt does not run it), it does not run when a provider error ends the turn, and
  # its input names neither the platform session nor whether `finish_session` was called.
  # A typed message is a new prompt, so it works every time and after an error too.
  #
  # The pane is read once a minute by ScanQuotaErrorsActivity. A turn end has to be on two
  # of its reads, on the same screen, before anything is typed, and then:
  #
  #   - nothing is typed while a person is working in the session's terminal: anyone may
  #     talk to the agent there, and each answer it gives them also ends a turn;
  #   - at most LIMIT reminders per session; the turn end after the last one fails the
  #     session with a message that says so.
  class TurnEndNudge
    LIMIT = 3

    # A person who typed into the terminal this recently is still working there. Input,
    # not an attached client, decides: a browser tab left open must not hold the session.
    PERSON_QUIET = 10.minutes

    # Two reads of the once-a-minute scan.
    CONFIRM_AFTER = 50.seconds

    MESSAGE = "Aixle: your turn ended, but this automatic session is not finished. " \
              "If all work is done, call `finish_session`. Otherwise continue from where you stopped."

    SCREEN_KEY = "turn_end_screen"
    SEEN_AT_KEY = "turn_end_seen_at"
    COUNT_KEY = "turn_end_nudges"

    # tmux's own record of each client attached to the agent pane: whether it is read-only
    # (the web terminal everyone but the session's owner gets) and when it last sent input.
    # The container's clock comes with it, so the comparison does not depend on clock skew.
    CLIENTS_COMMAND = [
      "sh", "-c",
      "date +%s && tmux list-clients -t agent -F '\#{client_readonly} \#{client_activity}'"
    ].freeze

    def self.applies_to?(session)
      session.session_type == "workflow_step" &&
        session.mode == "non_interactive" &&
        session.state == "ready" &&
        !Sessions::AuthPause.paused?(session)
    end

    def self.message_after_limit
      "Session terminated: the agent ended its turn without calling `finish_session` " \
        "#{LIMIT + 1} times, and Aixle's #{LIMIT} reminders to finish or continue did not change that. " \
        "The last turn is at the end of the session's terminal."
    end

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    # One look at the pane of a live session (ScanQuotaErrorsActivity).
    # @return [Symbol, nil] :nudged, :failed, :pending (seen once, or a person is working
    #   in the terminal), or nil when the pane is not at a turn end
    def observe(pane)
      return nil if pane.blank? || !self.class.applies_to?(session)

      unless TurnEndDetector.idle?(pane, agent_type: session.agent_type)
        forget
        return nil
      end

      digest = ScreenDigest.of(pane)
      return remember(digest) unless confirmed?(digest)
      return :pending if person_working?
      return give_up if nudges >= LIMIT
      return :pending unless type_message

      session.merge_jsonb!(:metadata, COUNT_KEY => nudges + 1)
      session.remove_jsonb_keys!(:metadata, SCREEN_KEY, SEEN_AT_KEY)
      log(:info, "nudged (#{nudges}/#{LIMIT})")
      :nudged
    end

    private

    attr_reader :session

    def metadata
      session.metadata || {}
    end

    def nudges
      metadata[COUNT_KEY].to_i
    end

    def confirmed?(digest)
      return false unless metadata[SCREEN_KEY] == digest

      seen_at = Time.zone.parse(metadata[SEEN_AT_KEY].to_s)
      seen_at.present? && seen_at <= CONFIRM_AFTER.ago
    end

    def remember(digest)
      session.merge_jsonb!(:metadata, SCREEN_KEY => digest, SEEN_AT_KEY => Time.current.iso8601)
      :pending
    end

    def forget
      return unless metadata.key?(SCREEN_KEY) || metadata.key?(SEEN_AT_KEY)

      session.remove_jsonb_keys!(:metadata, SCREEN_KEY, SEEN_AT_KEY)
    end

    def give_up
      SessionService.fail_session(session: session, error_message: self.class.message_after_limit)
      log(:info, "stopped again after #{LIMIT} reminders; failed")
      :failed
    end

    # True when a writable client typed within PERSON_QUIET, and when the clients cannot
    # be read: typing over a person is worse than waiting a minute for the next scan.
    def person_working?
      stdout, _stderr, status = container_runtime.exec(container, CLIENTS_COMMAND, stdout: true, stderr: true)
      return true unless status.to_i.zero?

      now, *clients = Array(stdout).join.split("\n").map(&:strip).reject(&:empty?)
      clients.any? do |client|
        readonly, activity = client.split
        readonly == "0" && now.to_i - activity.to_i < PERSON_QUIET.to_i
      end
    rescue StandardError => e
      log(:warn, "could not read the terminal's clients: #{e.class}: #{e.message}")
      true
    end

    def type_message
      typed = container_runtime.exec(container, [ "tmux", "send-keys", "-t", "agent", "-l", MESSAGE ])
      return false unless Array(typed)[2].to_i.zero?

      Array(container_runtime.exec(container, [ "tmux", "send-keys", "-t", "agent", "Enter" ]))[2].to_i.zero?
    rescue StandardError => e
      log(:warn, "could not type the reminder: #{e.class}: #{e.message}")
      false
    end

    def container
      @container ||= container_runtime.resolve_container(session.container_id)
    end

    def container_runtime
      @runtime ||= ContainerRuntime.build
    end

    def log(level, message)
      Rails.logger.public_send(level, "[TurnEndNudge] session=#{session.id} #{message}")
      nil
    end
  end
end
