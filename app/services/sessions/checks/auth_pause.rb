# frozen_string_literal: true

module Sessions
  module Checks
    # Pauses a workflow step whose agent was refused its login, instead of letting the
    # no-output watchdog fail it, and ends the pause when the pane says the agent is past
    # it. The actions are Sessions::AuthPause's; this check decides from the snapshot when
    # to take them.
    #
    # A session is paused when its current screen ends on the runtime's login banner
    # (BaseAdapter#auth_banner_pattern), no resume prompt was typed below it, and the pane
    # has been quiet for QUIET_BEFORE_PAUSE. A paused one is unpaused once the banner has
    # left the screen, failed once the pause limit has passed, and healed again when due.
    # Only what the pane shows can end a pause, never the log's mtime: opening the session's
    # terminal in a browser redraws the CLI and moves it.
    #
    # Kept state: none here. The pause itself (`auth_paused_at`, `auth_pause_reason`,
    # `auth_renewed_at`) and the heal counters (`auth_heal_attempts`,
    # `auth_heal_attempted_at`) are written by Sessions::AuthPause's actions, under the
    # session's row lock, because a delivery (#resume!) and a refused login written back by
    # the CLI (#login_refused!) change them outside the pass too.
    class AuthPause < Base
      # The banner has to be the last thing the agent did, a minute ago at least.
      QUIET_BEFORE_PAUSE = 1.minute

      def self.applies_to?(session) = settled_step?(session)

      def self.parts = %i[scrollback log_mtime].freeze

      def call(snapshot)
        return continue if snapshot.scrollback.blank? # the pane could not be read: nothing to decide on
        return still_paused(snapshot) if Sessions::AuthPause.paused?(session)

        banner = banner_on(snapshot)
        return continue if banner.nil? || !snapshot.quiet_for?(QUIET_BEFORE_PAUSE)
        return stop(:taken_over) unless pause.pause!(banner) { |locked| self.class.applies_to?(locked) }

        pause.heal!
        stop(Sessions::AuthPause.paused?(session.reload) ? :paused : :resumed)
      end

      private

      def still_paused(snapshot)
        if banner_on(snapshot).nil?
          return stop(pause.unpause_quietly { |locked| self.class.applies_to?(locked) } ? :resumed : :taken_over)
        end
        if pause.expired?
          return stop(pause.expire! { |locked| self.class.applies_to?(locked) } ? :failed : :taken_over)
        end

        pause.heal! if pause.heal_due?
        stop(Sessions::AuthPause.paused?(session.reload) ? :paused : :resumed)
      end

      # The banner line, unless a resume prompt was typed below it since.
      def banner_on(snapshot)
        pattern = adapter.auth_banner_pattern
        return nil if pattern.nil?

        lines = snapshot.screen
        banner_at = lines.rindex { |line| line.match?(pattern) }
        return nil if banner_at.nil?

        marker = adapter.auth_resume_prompt[0, 30]
        nudged_at = lines.rindex { |line| line.include?(marker) }
        return nil if nudged_at && nudged_at > banner_at

        lines[banner_at].strip.truncate(500)
      end

      def pause
        @pause ||= Sessions::AuthPause.new(session, runtime: runtime)
      end

      def adapter
        @adapter ||= AgentCredentialsService.for(session.agent_type).adapter
      end
    end
  end
end
