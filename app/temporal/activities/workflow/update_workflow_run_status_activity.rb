# frozen_string_literal: true

module Activities
  module Workflow
    class UpdateWorkflowRunStatusActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        status = input["status"].to_sym

        case status
        when :running   then workflow_run.start!   if workflow_run.may_start?
        when :completed then WorkflowService.complete(run: workflow_run)
        when :failed    then fail_run(workflow_run, input["reason"])
        when :cancelled then WorkflowService.cancel(run: workflow_run)
        when :paused    then workflow_run.pause!    if workflow_run.may_pause?
        end

        { "workflow_run_id" => workflow_run.id, "state" => workflow_run.state }
      end

      private

      def fail_run(workflow_run, reason)
        workflow_run.update!(failure_reason: reason) if reason.present? && workflow_run.failure_reason.blank?
        WorkflowService.fail(run: workflow_run)
      end
    end
  end
end
