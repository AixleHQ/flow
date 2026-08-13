# frozen_string_literal: true

module Coder
  # ReapDeadWorkspacesJob — manual-invocation entry point for the dead-workspace
  # reaper. The scheduled path is `Workflows::CoderReapDeadWorkspacesWorkflow`
  # (`app/temporal/schedules.yml`) which runs the same logic via
  # `Activities::Coder::ReapDeadWorkspacesActivity`. This job stays as a
  # `perform_now` handle for the Rails console — "clean the pool now" after an
  # incident, without waiting for the next tick.
  #
  # All of the decision logic (and every safety guard) lives in
  # `Coder::DeadWorkspaceReaper`; this is a thin wrapper on purpose.
  class ReapDeadWorkspacesJob < ApplicationJob
    queue_as :low

    def perform
      totals = Coder::DeadWorkspaceReaper.reap_all
      Rails.logger.info(
        "[Coder::ReapDeadWorkspacesJob] checked #{totals[:checked]} workspaces across " \
        "#{totals[:integrations]} integrations: deleted #{totals[:deleted]}, marked #{totals[:marked]}"
      )
      totals
    end
  end
end
