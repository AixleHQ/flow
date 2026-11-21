# frozen_string_literal: true

module Activities
  module Session
    # Hourly: reminds owners whose suspended session can be restored for three more days,
    # and finishes the ones whose 30 days are over (Sessions::SuspensionExpiry).
    class ExpireSuspendedActivity < Base
      def run(_input = nil)
        { reminded: Sessions::SuspensionExpiry.remind_due, expired: Sessions::SuspensionExpiry.expire_due }
      end
    end
  end
end
