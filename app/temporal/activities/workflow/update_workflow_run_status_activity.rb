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
        when :failed    then WorkflowService.fail(run: workflow_run)
        when :cancelled then WorkflowService.cancel(run: workflow_run)
        when :paused    then workflow_run.pause!    if workflow_run.may_pause?
        end

        { "workflow_run_id" => workflow_run.id, "state" => workflow_run.state }
      end
    end
  end
end
