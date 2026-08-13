# frozen_string_literal: true

# Activities::Coder::ReapDeadWorkspacesActivity
# Deletes Coder workspaces whose agent is confirmed gone for good — the spot
# interruption case, where Coder still reports the last build as a succeeded
# start while the instance behind it no longer exists. Driven by
# `Workflows::CoderReapDeadWorkspacesWorkflow` on a Temporal schedule.
#
# The activity is a thin driver: every guard that keeps a live workspace out of
# the delete path (succeeded-start builds only, positive agent evidence, no live
# lock, an SSH probe that fails to REACH the box, two sightings a confirmation
# window apart, and a per-run deletion cap) lives in
# `Coder::DeadWorkspaceReaper` and is unit-tested there.
#
# Retries are safe: a workspace whose delete build is already in flight lists as
# `transition: "delete"` and is no longer a candidate.

module Activities
  module Coder
    class ReapDeadWorkspacesActivity < ::Activities::Base
      def run(_input = nil)
        totals = ::Coder::DeadWorkspaceReaper.reap_all

        log(:info, "checked #{totals[:checked]} workspaces across #{totals[:integrations]} " \
                   "integrations: deleted #{totals[:deleted]}, marked #{totals[:marked]}, " \
                   "skipped #{totals[:skipped]}, errors #{totals[:errors]}")

        totals
      end
    end
  end
end
