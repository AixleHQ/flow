# frozen_string_literal: true

class WorkflowRunChannel < ApplicationCable::Channel
  def subscribed
    @workflow_run = find_workflow_run
    return reject unless @workflow_run
    return reject unless can_access?(@workflow_run)

    stream_for @workflow_run
    transmit_run_data(@workflow_run)
  end

  def unsubscribed
    # cleanup
  end

  def refresh
    return unless @workflow_run

    @workflow_run.reload
    transmit_run_data(@workflow_run)
  end

  private

  def find_workflow_run
    WorkflowRun.find_by(id: params[:run_id])
  end

  def can_access?(run)
    return false unless current_user

    run.project.accessible_by?(current_user)
  end

  def transmit_run_data(run)
    transmit({ "type" => "run_update", "data" => serialize_run(run) })
  end

  def serialize_run(run)
    WorkflowRunSerializer.new(run).serializable_hash
  end

  class << self
    def broadcast_update(workflow_run)
      broadcast_to(
        workflow_run,
        { "type" => "run_update", "data" => WorkflowRunSerializer.new(workflow_run).serializable_hash }
      )
    end

    def broadcast_step_update(workflow_run, step_run)
      broadcast_to(
        workflow_run,
        {
          "type" => "step_run_update",
          "data" => StepRunSerializer.new(step_run).serializable_hash
        }
      )
    end

    def broadcast_sub_step_update(workflow_run, sub_step_run)
      broadcast_to(
        workflow_run,
        {
          "type" => "sub_step_run_update",
          "data" => SubStepRunSerializer.new(sub_step_run).serializable_hash
        }
      )
    end
  end
end
