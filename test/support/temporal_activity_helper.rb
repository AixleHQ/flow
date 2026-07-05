# frozen_string_literal: true

require "temporalio/testing"

# Runs a Temporal activity through the SDK's ActivityEnvironment — the Phase 4
# target for activity tests (docs/testing.md §2) — instead of calling #execute on
# a bare instance. ActivityEnvironment is serverless (no Temporal test server, so
# no boot/hang risk): it executes the activity inside a real activity context,
# exercising the SDK dispatch path while boundaries stay behind their fakes.
module TemporalActivityHelper
  def run_activity(activity, *args, **kwargs)
    Temporalio::Testing::ActivityEnvironment.new.run(activity, *args, **kwargs)
  end
end
