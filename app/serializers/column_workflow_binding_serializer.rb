# frozen_string_literal: true

class ColumnWorkflowBindingSerializer < ApplicationSerializer
  attributes :id, :workflow_id, :workflow_name, :trigger_mode, :cooldown_seconds, :created_at, :updated_at

  def workflow_name
    object.workflow.name
  end
end
