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
    def broadcast_update(workflow_run_or_id)
      run = workflow_run_or_id.is_a?(Integer) ? WorkflowRun.find(workflow_run_or_id) : workflow_run_or_id
      broadcast_to(run, { "type" => "workflow_run.updated", "data" => { id: run.id } })
    end

    def broadcast_step_update(workflow_run, step_run)
      run = workflow_run.is_a?(Integer) ? WorkflowRun.find(workflow_run) : workflow_run
      broadcast_to(run, {
        "type" => "step_run.updated",
        "data" => { id: step_run.id, workflow_run_id: run.id }
      })
    end

    def broadcast_sub_step_update(workflow_run, sub_step_run)
      run = workflow_run.is_a?(Integer) ? WorkflowRun.find(workflow_run) : workflow_run
      broadcast_to(run, {
        "type" => "sub_step_run.updated",
        "data" => { id: sub_step_run.id, step_run_id: sub_step_run.step_run_id, workflow_run_id: run.id }
      })
    end
  end
end
