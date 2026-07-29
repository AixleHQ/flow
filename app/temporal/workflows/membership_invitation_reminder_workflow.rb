# frozen_string_literal: true

module Workflows
  class MembershipInvitationReminderWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.membership_remind_pending_invitations_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
