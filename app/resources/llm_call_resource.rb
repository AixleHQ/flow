# frozen_string_literal: true

class LlmCallResource < ApplicationResource
  attributes :id, :model, :input_tokens, :output_tokens,
             :cache_read_tokens, :cache_write_tokens, :source,
             :step_run_id

  typelize :string
  attribute :occurred_at do |call|
    call.occurred_at.iso8601(3)
  end

  typelize :number
  attribute :cost_cents do |call|
    call.total_cents_precise.to_f.round(4)
  end

  typelize :string?
  attribute :step_name do |call|
    call.step_run&.step&.name
  end
end
