# frozen_string_literal: true

class SubStepSerializer < ApplicationSerializer
  attributes :id, :step_id, :position, :name, :description, :instructions,
             :required, :created_at, :updated_at
end
