# frozen_string_literal: true

class SubStepRunResource < ApplicationResource
  attributes :id, :state, :started_at, :completed_at

  attribute :sub_step_name do |ssr|
    ssr.sub_step&.name
  end

  attribute :sub_step_description do |ssr|
    ssr.sub_step&.description
  end
end
