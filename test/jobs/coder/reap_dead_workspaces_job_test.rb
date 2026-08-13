# frozen_string_literal: true

require "test_helper"

module Coder
  # The job is a `perform_now` handle for the console; every decision it could
  # get wrong lives in `Coder::DeadWorkspaceReaper` and is covered in
  # dead_workspace_reaper_test. What is worth pinning here is that it drives the
  # sweep and hands the totals back unchanged.
  class ReapDeadWorkspacesJobTest < ActiveSupport::TestCase
    test "drives the sweep and returns its totals" do
      totals = { integrations: 2, checked: 4, marked: 1, cleared: 0, deleted: 1, skipped: 0, errors: 0 }
      Coder::DeadWorkspaceReaper.expects(:reap_all).returns(totals)

      assert_equal totals, Coder::ReapDeadWorkspacesJob.new.perform
    end

    test "queues on the low-priority queue like the other Coder housekeeping" do
      assert_equal "low", Coder::ReapDeadWorkspacesJob.queue_name
    end
  end
end
