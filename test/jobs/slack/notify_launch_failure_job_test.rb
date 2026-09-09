# frozen_string_literal: true

require "test_helper"

module Slack
  class NotifyLaunchFailureJobTest < ActiveSupport::TestCase
    test "hands the dispatch to the notifier" do
      dispatch = create(:trigger_event).then do |event|
        TriggerDispatch.create!(trigger_event: event, dedup_key: "d-#{event.id}", status: "skipped")
      end

      Slack::RunFailureNotifier.expects(:notify_launch_skip).with(dispatch).once

      Slack::NotifyLaunchFailureJob.new.perform(dispatch.id)
    end

    test "is a no-op when the dispatch is gone" do
      Slack::RunFailureNotifier.expects(:notify_launch_skip).with(nil).once

      Slack::NotifyLaunchFailureJob.new.perform(-1)
    end
  end
end
