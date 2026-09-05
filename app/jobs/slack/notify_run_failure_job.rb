# frozen_string_literal: true

module Slack
  # Off the state transition: posting to Slack is a network call, and a failed
  # run must finish failing whether or not Slack answers.
  class NotifyRunFailureJob < ApplicationJob
    queue_as :default

    def perform(workflow_run_id)
      run = WorkflowRun.find_by(id: workflow_run_id)
      Slack::RunFailureNotifier.call(run)
    end
  end
end
