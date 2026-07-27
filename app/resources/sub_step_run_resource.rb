# frozen_string_literal: true

class SubStepRunResource < ApplicationResource
  attributes :id, :state, :started_at, :completed_at

  typelize :string?
  attribute :sub_step_name do |ssr|
    ssr.sub_step&.name
  end
end
