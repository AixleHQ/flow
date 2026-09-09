# frozen_string_literal: true

module Slack
  # Off the dispatch path: a launch skipped by TriggerEngine#fire_workflow still
  # deserves a word in the Slack thread that asked for it, but posting to Slack is
  # a network call and must not sit inside the dispatch lock.
  class NotifyLaunchFailureJob < ApplicationJob
    queue_as :default

    def perform(trigger_dispatch_id)
      dispatch = TriggerDispatch.find_by(id: trigger_dispatch_id)
      Slack::RunFailureNotifier.notify_launch_skip(dispatch)
    end
  end
end
