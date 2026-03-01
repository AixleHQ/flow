# frozen_string_literal: true

class TaskWorkflowRunSerializer < ApplicationSerializer
  attributes :id, :workflow_name, :state, :mode,
             :started_at, :completed_at, :created_at

  def workflow_name
    object.workflow.name
  end
end
