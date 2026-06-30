# frozen_string_literal: true

class ColumnWorkflowBindingResource < ApplicationResource
  attributes :id, :workflow_id, :trigger_mode, :cooldown_seconds, :created_at, :updated_at

  typelize :string?
  attribute :workflow_name do |binding|
    binding.workflow&.name
  end
end
