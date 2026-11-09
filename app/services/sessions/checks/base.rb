# frozen_string_literal: true

module Sessions
  # The checks Sessions::Monitor runs on a live session's snapshot.
  module Checks
    # The one interface every check implements.
    #
    #   .applies_to?(session)  whether the check has anything to say about the session.
    #                          A session no check applies to is not read at all.
    #   .parts                 the snapshot parts it needs (Snapshot::Parts::REGISTRY).
    #   .kept_keys             the metadata keys it keeps between passes (KeptState).
    #   #call(snapshot)        looks at the snapshot, acts if it has to, and returns a
    #                          Result: go on to the next check, or stop.
    #
    # A check reads nothing itself: the terminal comes from the snapshot, and what it
    # remembers from its earlier passes comes from `kept`. It acts itself, though: it fails
    # the session, pauses it, or types into it. Before it changes the session's state it
    # reads the row again under its lock and checks that it still applies (#fail_session):
    # the snapshot and the row it came with can be seconds old.
    class Base
      # Sessions that just started: their container or tmux may not be up yet.
      MIN_AGE = 1.minute

      ACTIVE_STATES = %w[running ready].freeze

      class << self
        def applies_to?(_session) = raise(NotImplementedError, "#{name}.applies_to?")

        def parts = raise(NotImplementedError, "#{name}.parts")

        def kept_keys = [].freeze

        # A live workflow step whose container should be up by now: the sessions the
        # quota scan has always read.
        def settled_step?(session)
          session.session_type == "workflow_step" &&
            session.state.in?(ACTIVE_STATES) &&
            session.container_id.present? &&
            (session.started_at || session.created_at) < MIN_AGE.ago
        end
      end

      def initialize(session, runtime:, kept: nil)
        @session = session
        @runtime = runtime
        @kept = kept || KeptState.new(session).for(self.class)
      end

      def call(_snapshot) = raise(NotImplementedError, "#{self.class.name}#call")

      private

      attr_reader :session, :runtime, :kept

      def continue(outcome = nil) = Result.new(outcome: outcome, stop: false)

      def stop(outcome) = Result.new(outcome: outcome, stop: true)

      # Fails the session with `message` through SessionService, so its container workflow
      # is woken and its cleanup runs. It is a compare-and-set: under the session's row lock
      # the session must still be in the state the pass read it in, the check must still
      # apply to it, and `still` (when given) must still hold, or nothing is changed. A
      # session that started finishing, was finished or was auth-paused since the pass read
      # it is another path's, and the check stops.
      #
      # The message is redacted first (#redact): it quotes the pane, it is stored in
      # `error_message`, and from there it reaches the step's error and the Slack notice.
      def fail_session(message, &still)
        failed = SessionService.fail_session_if(session: session, error_message: redact(message),
                                                expected_state: session.state) do |locked|
          self.class.applies_to?(locked) && (still.nil? || still.call(locked))
        end
        return stop(:failed) if failed

        log(:info, "taken over by another path (state=#{session.state}); not failed")
        stop(:taken_over)
      end

      def log(level, message)
        Rails.logger.public_send(level, "[#{self.class.name}] session=#{session.id} #{message}")
        nil
      end

      # Masks the session's secret config items, as Sessions::LiveLogReader does for a live
      # read: the pane is the same bytes the stored log would carry.
      def redact(text)
        @redactor ||= Sessions::SecretRedactor.for_session(session)
        @redactor.call(text)
      end
    end
  end
end
