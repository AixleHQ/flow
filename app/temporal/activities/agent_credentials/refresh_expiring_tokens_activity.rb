# frozen_string_literal: true

# Activities::AgentCredentials::RefreshExpiringTokensActivity
# Proactively refreshes agent-CLI OAuth tokens nearing expiry, driven by
# Workflows::AgentTokenRefreshWorkflow on a */5 Temporal schedule.
# Per-record rescue so one bad credential never fails the batch.
module Activities
  module AgentCredentials
    class RefreshExpiringTokensActivity < ::Activities::Base
      # Matches ClaudeCodeAdapter::REFRESH_MARGIN_MS: selecting rows the adapter will
      # not act on just re-reads and decrypts them every 5 minutes. A session needing
      # more headroom than this refreshes at launch instead
      # (AgentCredential#refresh_if_expiring!).
      REFRESH_WINDOW = 15.minutes

      # How long a holder's terminal must have been quiet before its token may be rotated
      # under it. A parked session — an interactive one nobody came back to, the shape that
      # killed six production credentials on 2026-09-17 — reads its credential file again
      # when it wakes up; one with an agent mid-turn may be holding the old grant in memory,
      # and rotating under that is what the 2026-09-05 incident looked like. Ten minutes is
      # far longer than the gap between two lines of agent output and far shorter than the
      # 25-hour reaper that used to be the only thing freeing a pinned credential.
      IDLE_BEFORE_REFRESH = 10.minutes

      def run(_input = nil)
        @refreshed = 0
        @not_needed = 0
        @errors = 0
        @delivered = 0
        @skipped_busy = 0

        due = ::AgentCredential.refreshable.refresh_due(REFRESH_WINDOW)

        due.without_live_session.find_each { |credential| refresh(credential) }
        due.with_live_session.find_each { |credential| refresh_held(credential) }

        log(:info, "token refresh sweep: refreshed=#{@refreshed} not_needed=#{@not_needed} " \
                   "errors=#{@errors} delivered_to_containers=#{@delivered} held_by_busy_session=#{@skipped_busy}")
        { refreshed: @refreshed, not_needed: @not_needed, errors: @errors,
          delivered: @delivered, skipped_busy: @skipped_busy }
      end

      private

      # A credential a live container holds. A rotating refresh invalidates the grant that
      # container is running on, so it is only done when every holder is parked rather than
      # working; a static one leaves the holder's copy valid. Either way the new token is
      # handed to the holders immediately afterwards. Doing nothing — the previous
      # behaviour — is what let a pinned token expire unattempted.
      def refresh_held(credential)
        holders = credential.live_holder_sessions.to_a
        if credential.rotating_refresh? && !holders.all? { |session| parked?(session) }
          @skipped_busy += 1
          log(:info, "credential #{credential.id} (#{credential.agent_type}) left to its container: " \
                     "a holder is mid-turn")
          return
        end

        deliver_to(credential, holders) if refresh(credential) == :refreshed
      end

      def refresh(credential)
        result = credential.renew!(source: :sweep)
        case result[:status]
        when :refreshed
          @refreshed += 1
        when :error
          @errors += 1
          log(:warn, "credential #{credential.id} (#{credential.agent_type}) refresh error: #{result[:detail]}")
        else
          @not_needed += 1
        end
        result[:status]
      end

      def deliver_to(credential, holders)
        result = ::Agents::CredentialDelivery.new.deliver(credential.reload, sessions: holders)
        @delivered += result.delivered
        return if result.failed.zero?

        log(:warn, "credential #{credential.id}: #{result.failed} holder(s) could not take the refreshed token")
      end

      # "Parked" is the absence of recent terminal output, read from the container the same
      # way the no-output watchdog reads it. A container that cannot be reached answers
      # false — unknown must never pass for idle.
      def parked?(session)
        return true if session.container_id.blank? # queued: it has not been handed anything yet

        ::Sessions::NoOutputWatchdog.new(session).silent_for?(IDLE_BEFORE_REFRESH)
      rescue StandardError => e
        log(:warn, "session #{session.id} idle probe failed: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
