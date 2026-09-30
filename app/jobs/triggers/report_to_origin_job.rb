# frozen_string_literal: true

module Triggers
  class ReportToOriginJob < ApplicationJob
    queue_as :default

    # Transient provider trouble: back off for roughly an hour, then give up. A
    # report that never lands must not change the run's own outcome.
    class Retryable < StandardError; end
    retry_on Retryable, wait: :polynomially_longer, attempts: 8

    def perform(dispatch_id, transition, reporter_name)
      dispatch = TriggerDispatch.find_by(id: dispatch_id)
      return unless dispatch && Triggers::ORIGIN_REPORTERS.include?(reporter_name)

      reporter_name.constantize.report(dispatch, transition)
    end
  end
end
