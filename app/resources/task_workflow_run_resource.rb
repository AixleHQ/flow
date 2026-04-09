# frozen_string_literal: true

class TaskWorkflowRunResource < ApplicationResource
  attributes :id, :state, :mode, :started_at, :completed_at, :created_at

  attribute :workflow_name do |run|
    run.workflow&.name
  end
end
