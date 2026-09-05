# frozen_string_literal: true

module Workflows
  class SessionAdmissionReconciliationWorkflow < Base
    def run(_input = nil)
      execute_activity(activities.session_reconcile_admissions_activity, {}, start_to_close_timeout: 300)
    end
  end
end
