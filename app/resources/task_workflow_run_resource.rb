# frozen_string_literal: true

class TaskWorkflowRunResource < ApplicationResource
  typelize_from WorkflowRun

  attributes :id, :state, :mode, :started_at, :completed_at, :created_at

  typelize :string?
  attribute :workflow_name do |run|
    run.workflow&.name
  end
end
