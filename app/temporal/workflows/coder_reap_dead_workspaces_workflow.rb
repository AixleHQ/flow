# frozen_string_literal: true

module Workflows
  # CoderReapDeadWorkspacesWorkflow — scheduled sweep that deletes Coder
  # workspaces whose agent is confirmed dead (see
  # `Coder::DeadWorkspaceReaper`). Wired into `app/temporal/schedules.yml`.
  #
  # The 600s budget is for the SSH probes: confirmation costs one probe per
  # workspace that Coder already reports as agent-dead, and each probe waits out
  # `health_probe_timeout` before it can be called unreachable.
  class CoderReapDeadWorkspacesWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.coder_reap_dead_workspaces_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
