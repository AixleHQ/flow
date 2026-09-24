# frozen_string_literal: true

require "test_helper"

class SolidQueueCleanupJobTest < ActiveSupport::TestCase
  def queued_job(finished_at:)
    SolidQueue::Job.create!(queue_name: "default", class_name: "InertiaCable::BroadcastJob",
                            arguments: {}, finished_at: finished_at)
  end

  test "deletes jobs that finished more than a day ago and keeps the rest" do
    old = queued_job(finished_at: 2.days.ago)
    recent = queued_job(finished_at: 1.hour.ago)
    pending = queued_job(finished_at: nil)

    SolidQueueCleanupJob.perform_now

    assert_not SolidQueue::Job.exists?(old.id)
    assert SolidQueue::Job.exists?(recent.id)
    assert SolidQueue::Job.exists?(pending.id)
  end
end
