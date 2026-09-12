# frozen_string_literal: true

require "test_helper"

class QueueHealthCheckJobTest < ActiveJob::TestCase
  test "perform runs the check" do
    QueueHealthCheck.expects(:call).once

    QueueHealthCheckJob.perform_now
  end

  # A watchdog that takes a process down with it, or retries until it reports a
  # world that has already moved on, is worse than one that misses a tick: the
  # next tick is a minute away and carries a fresher answer.
  test "a failing check is discarded rather than retried" do
    QueueHealthCheck.stubs(:call).raises(ActiveRecord::StatementInvalid, "connection lost")

    assert_nothing_raised { QueueHealthCheckJob.perform_now }
    assert_equal 0, enqueued_jobs.size
  end
end
