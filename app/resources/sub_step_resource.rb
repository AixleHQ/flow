# frozen_string_literal: true

class SubStepResource < ApplicationResource
  attributes :id, :step_id, :name, :instructions, :position, :required,
             :created_at, :updated_at
end
