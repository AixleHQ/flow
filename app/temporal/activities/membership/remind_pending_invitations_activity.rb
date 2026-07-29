# frozen_string_literal: true

module Activities
  module Membership
    # Mails a reminder for invitations that are still unaccepted and about to
    # expire. Without this an invite simply goes silent after 7 days and neither
    # side learns it lapsed.
    #
    # Idempotency: `reminded_at` is stamped per membership, so a re-run (or a
    # Temporal retry) never mails twice, and the cron can safely run hourly.
    class RemindPendingInvitationsActivity < Base
      # Remind once the invitation is inside its final stretch.
      REMIND_WHEN_EXPIRING_WITHIN = 2.days

      def run(_input = nil)
        valid_for = CompanyMembership::INVITATION_VALID_FOR
        # Old enough to be near expiry, but not already expired — past that the
        # token is dead and a reminder would link nowhere.
        window = valid_for.ago..(valid_for - REMIND_WHEN_EXPIRING_WITHIN).ago

        pending = CompanyMembership.invited
                                   .where(reminded_at: nil)
                                   .where(invited_at: window)

        sent = 0
        pending.includes(:user, :company).find_each do |membership|
          # deliver_NOW, not later: ActiveJob runs on the in-memory async adapter,
          # so an enqueued mail is lost on restart — and stamping reminded_at
          # straight after enqueueing would make that loss permanent, since the
          # stamp is exactly what stops this membership being picked up again.
          # This already runs inside a Temporal activity, which is the durable
          # retry layer: send first, stamp only once the send returned.
          MembershipMailer.invitation_reminder(membership).deliver_now
          membership.update_column(:reminded_at, Time.current)
          sent += 1
        rescue StandardError => e
          # Left unstamped on purpose — the next sweep retries this one.
          log(:warn, "Failed to remind membership #{membership.id}: #{e.message}")
        end

        log(:info, "Sent #{sent} invitation reminders")
        { reminded_count: sent }
      end
    end
  end
end
