# frozen_string_literal: true

class BoardWorkflowResource < ApplicationResource
  typelize_from Workflow

  attributes :id, :name
end
