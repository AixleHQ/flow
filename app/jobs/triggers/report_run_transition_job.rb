# frozen_string_literal: true

module Triggers
  # Fans one run transition out to one job per reporter that cares, so a
  # reporter retrying against a slow provider never repeats another's message.
  class ReportRunTransitionJob < ApplicationJob
    queue_as :default

    def perform(dispatch_id, transition)
      dispatch = TriggerDispatch.find_by(id: dispatch_id)
      return unless dispatch

      Triggers.origin_reporters.each do |reporter|
        ReportToOriginJob.perform_later(dispatch_id, transition, reporter.name) if reporter.applies?(dispatch, transition)
      end
    end
  end
end
